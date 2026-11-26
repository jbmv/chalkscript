import Foundation
import Testing
@testable import ChalkScript

// The declaration of the areas a document is made for (EXP-17, section 8.2 of the format's
// reference): its structure, the layouts it names, and the warnings the code `areas` gives.

struct AreasTests {
    let tiny = DocumentFixture.tiny

    /// The small document with `layouts` and `areas` given as JSON text; nil leaves one out.
    func doc(layouts: String?, areas: String?) -> JSONValue {
        var d = tiny
        if let layouts { d = d.setting("/layouts", try! JSONValue.parse(layouts)) }
        if let areas { d = d.setting("/areas", try! JSONValue.parse(areas)) }
        return d
    }

    static let tall = #"{"stage": {"size": [1000, 540]}, "tall": {"suits": "areaW <= areaH * 1.35", "size": [640, "round(640 * areaH / areaW)"]}}"#
    static let both = #"[{"layout": "tall", "ratio": [0.6, 1.35]}, {"layout": "stage", "ratio": [1.35, 2.2]}]"#

    func areaFindings(_ r: DocumentReading) -> [DocumentFinding] { r.findings.filter { $0.code == .areas } }

    @Test func theExamplesDeclareTheAcceptedBounds() throws {
        let sub = DocumentFixture.subtraction.areaEntries
        #expect(sub.map(\.layout) == ["tall", "stage"])
        #expect(sub.map(\.min) == [0.6, 1.35])
        #expect(sub.map(\.max) == [1.35, 2.2])
        let groups = DocumentFixture.equalGroups.areaEntries
        #expect(groups.map(\.layout) == ["stage"] && groups.map(\.min) == [0.9] && groups.map(\.max) == [2.2])
        #expect(DocumentFixture.subtraction.findings.isEmpty)
        #expect(DocumentFixture.equalGroups.findings.isEmpty)
    }

    @Test func aDocumentWithAreasThatAgreeHasNoFinding() {
        let r = read(doc(layouts: Self.tall, areas: Self.both))
        #expect(r.conforms && r.findings.isEmpty, "\(r.findings)")
        let one = read(doc(layouts: nil, areas: #"[{"layout": "stage", "ratio": [0.9, 2.2]}]"#))
        #expect(one.findings.isEmpty, "\(one.findings)")
        // An entry that declares one shape.
        let single = read(doc(layouts: Self.tall, areas: #"[{"layout": "tall", "ratio": [1, 1]}]"#))
        #expect(single.findings.isEmpty, "\(single.findings)")
    }

    @Test func aDocumentWithoutAreasGetsNoNewFinding() {
        // The layouts here would disagree with any declaration; with none, nothing is said.
        let r = read(doc(layouts: Self.tall + "", areas: nil))
        #expect(r.findings.isEmpty, "\(r.findings)")
        let many = read(doc(layouts: #"{"tall": {"suits": "areaW <= areaH", "size": [1, 1]}, "wide": {"suits": "areaW > areaH * 3", "size": [1, 1]}}"#, areas: nil))
        #expect(many.findings.isEmpty, "\(many.findings)")
    }

    @Test func theStructureOfAnEntryIsChecked() {
        has(read(doc(layouts: nil, areas: "[]")), .error, .schema, "/areas", "non-empty")
        has(read(doc(layouts: nil, areas: #"{"layout": "stage"}"#)), .error, .schema, "/areas", "non-empty")
        has(read(doc(layouts: nil, areas: #"[{"ratio": [1, 2]}]"#)), .error, .schema, "/areas/0", "'layout'")
        has(read(doc(layouts: nil, areas: #"[{"layout": "stage"}]"#)), .error, .schema, "/areas/0", "'ratio'")
        has(read(doc(layouts: nil, areas: #"[{"layout": "stage", "ratio": [1]}]"#)), .error, .schema, "/areas/0/ratio")
        has(read(doc(layouts: nil, areas: #"[{"layout": "stage", "ratio": [1, 2, 3]}]"#)), .error, .schema, "/areas/0/ratio")
        has(read(doc(layouts: nil, areas: #"[{"layout": "stage", "ratio": [1, "wide"]}]"#)), .error, .schema, "/areas/0/ratio/1", "not a number")
        has(read(doc(layouts: nil, areas: #"[{"layout": "stage", "ratio": [0, 2]}]"#)), .error, .schema, "/areas/0/ratio/0", "not more than 0")
        has(read(doc(layouts: nil, areas: #"[{"layout": "stage", "ratio": [-1, 2]}]"#)), .error, .schema, "/areas/0/ratio/0")
        has(read(doc(layouts: nil, areas: #"[{"layout": "stage", "ratio": [2, 1]}]"#)), .error, .schema, "/areas/0/ratio", "more than the greatest")
        has(read(doc(layouts: nil, areas: #"[{"layout": "stage", "ratio": [1, 2], "colour": 1}]"#)), .warning, .unknown, "/areas/0/colour")
    }

    @Test func anEntryNamingNoLayoutIsARefError() {
        let r = read(doc(layouts: nil, areas: #"[{"layout": "wide", "ratio": [1, 2]}]"#))
        has(r, .error, .ref, "/areas/0/layout", "no layout 'wide'")
        #expect(!r.conforms)
    }

    @Test func aShapeAtWhichAnotherLayoutIsChosenIsAWarning() {
        // `tall` suits areas up to 1.35 but is declared for up to 1.5; there the stage is chosen.
        let r = read(doc(layouts: Self.tall, areas: #"[{"layout": "tall", "ratio": [0.6, 1.5]}]"#))
        #expect(r.conforms)
        let f = areaFindings(r)
        #expect(f.count == 1, "\(r.findings)")
        #expect(f.first?.severity == .warning && f.first?.path == "/areas/0")
        #expect(f.first?.values == DocumentFixture.values(("a", 1)))
        #expect(f.first?.message.contains("the layout is stage, not tall") == true)
        #expect(f.first?.message.contains("at ratio 1.") == true)
        has(r, .warning, .areas, "/areas/0", "not tall")
        // The same range for `stage` disagrees where `tall` is chosen.
        let s = read(doc(layouts: Self.tall, areas: #"[{"layout": "stage", "ratio": [1, 2]}]"#))
        has(s, .warning, .areas, "/areas/0", "the layout is tall, not stage")
    }

    @Test func aShapeInAnotherEntrysRangeIsAccepted() {
        // 1.35 ends one entry and begins the other, and either layout is accepted there.
        let r = read(doc(layouts: Self.tall, areas: Self.both))
        #expect(areaFindings(r).isEmpty)
        // Overlapping ranges: where the stage entry reaches into `tall`'s, `tall` is chosen and
        // is the other entry's layout, so nothing is reported for it.
        let o = read(doc(layouts: Self.tall, areas: #"[{"layout": "tall", "ratio": [0.6, 1.35]}, {"layout": "stage", "ratio": [1.0, 2.2]}]"#))
        #expect(areaFindings(o).isEmpty, "\(o.findings)")
        // But a `tall` range that reaches past where it suits, outside any other range, is reported.
        let past = read(doc(layouts: Self.tall, areas: #"[{"layout": "tall", "ratio": [0.6, 1.5]}, {"layout": "stage", "ratio": [1.6, 2.2]}]"#))
        has(past, .warning, .areas, "/areas/0", "the layout is stage, not tall")
    }

    @Test func aLayoutNoEntryNamesIsAWarning() {
        let layouts = #"{"tall": {"suits": "areaW <= areaH", "size": [1, 1]}, "wide": {"suits": "areaW > areaH * 3", "size": [1, 1]}}"#
        let r = read(doc(layouts: layouts, areas: #"[{"layout": "tall", "ratio": [0.5, 1]}, {"layout": "stage", "ratio": [1.01, 2]}]"#))
        has(r, .warning, .areas, "/layouts/wide", "no entry of areas names this layout")
        #expect(!r.findings.contains { $0.path == "/layouts/tall" })
        // Stage needs no entry.
        let s = read(doc(layouts: Self.tall, areas: #"[{"layout": "tall", "ratio": [0.6, 1.3]}]"#))
        #expect(areaFindings(s).isEmpty, "\(s.findings)")
    }

    @Test func aSuitsThatDependsOnTheAreasSizeIsAWarning() {
        let layouts = #"{"tall": {"suits": "areaW <= areaH and areaW < 700", "size": [1, 1]}}"#
        let r = read(doc(layouts: layouts, areas: #"[{"layout": "tall", "ratio": [0.5, 1]}]"#))
        has(r, .warning, .areas, "/layouts/tall/suits", "depends on the area's size")
        #expect(areaFindings(r).filter { $0.path == "/layouts/tall/suits" }.count == 1)
        #expect(areaFindings(r).first { $0.path == "/layouts/tall/suits" }?.values == DocumentFixture.values(("a", 1)))
    }

    @Test func findingsAreNotMadeForADocumentWithAnError() {
        let r = read(doc(layouts: Self.tall, areas: #"[{"layout": "tall", "ratio": [0.6, 1.5]}]"#).setting("/title", nil))
        #expect(areaFindings(r).isEmpty)
    }
}
