import AppKit
import AVFoundation
import ChalkScript

/// Speaks an explainer's lines with the system voice (EXP-10), so that a draft is heard in the
/// studio's window. A line with no spoken form is finished at once and nothing is said.
@MainActor
final class SystemVoice: ExplainerVoice {
    /// The user default that holds whether the window speaks lines.
    static let enabledKey = "StudioSpeakLines"

    private let voice: AVSpeechSynthesisVoice?
    private let volume: Float
    private var said: AVSpeechUtterance?

    /// - Parameters:
    ///   - locale: The tag of the locale the lines are in, such as `en-US`. A language the Mac
    ///     has no voice for is spoken in the Mac's own voice.
    ///   - volume: From 0 to 1, of the Mac's output volume.
    init(locale: String, volume: Float = 1) {
        voice = Self.voice(for: locale)
        self.volume = volume
    }

    func say(_ line: Line, onFinish: @escaping @MainActor () -> Void) {
        // Without a letter or a digit there is nothing to hear, and the synthesizer may report
        // no end for it.
        guard let spoken = line.spoken, spoken.contains(where: { $0.isLetter || $0.isNumber }) else { return onFinish() }
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = voice
        utterance.volume = volume
        said = utterance
        Speaker.shared.speak(utterance, onEnd: onFinish)
    }

    func stop() {
        if let said { Speaker.shared.stop(said) }
        said = nil
    }

    /// The Mac's voice for `locale`: for the tag itself, or else for the same language in the
    /// Mac's own region, or else in any region.
    static func voice(for locale: String) -> AVSpeechSynthesisVoice? {
        if let exact = AVSpeechSynthesisVoice(language: locale) { return exact }
        guard let language = locale.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) else { return nil }
        let own = AVSpeechSynthesisVoice.currentLanguageCode()
        if own.hasPrefix(language + "-"), let voice = AVSpeechSynthesisVoice(language: own) { return voice }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language == language || $0.language.hasPrefix(language + "-") }
    }
}

/// The app's one synthesizer. Every player has its own `SystemVoice`, and a player is replaced
/// whenever the document is edited, so the voices share the synthesizer and a voice stops only
/// what it said itself.
@MainActor
private final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var current: (utterance: AVSpeechUtterance, onEnd: @MainActor () -> Void)?

    override private init() {
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cut() }
        }
    }

    /// Speaks `utterance` in place of whatever is being said, and calls `onEnd` once it has been
    /// heard to its end, unless it is stopped first.
    func speak(_ utterance: AVSpeechUtterance, onEnd: @escaping @MainActor () -> Void) {
        cut()
        current = (utterance, onEnd)
        synthesizer.speak(utterance)
    }

    /// Cuts `utterance` off if it is the one being said; its `onEnd` is not called.
    func stop(_ utterance: AVSpeechUtterance) {
        guard current?.utterance === utterance else { return }
        cut()
    }

    private func cut() {
        current = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        ended(ObjectIdentifier(utterance))
    }

    /// A line the synthesizer gave up on is ended too, so that a step waiting for it goes on.
    /// One this class cut off is no longer `current`, so nothing is called for it.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        ended(ObjectIdentifier(utterance))
    }

    nonisolated private func ended(_ utterance: ObjectIdentifier) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let current = self.current, ObjectIdentifier(current.utterance) == utterance else { return }
                self.current = nil
                current.onEnd()
            }
        }
    }
}
