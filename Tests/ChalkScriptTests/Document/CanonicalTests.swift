import Foundation
import Testing
@testable import ChalkScript

// The canonical form, the hash and the revision (EXP-19, section 19 of the format's reference).

struct CanonicalTests {
    /// The example of RFC 8785, section 3.2.4.
    @Test func theRFCsExampleIsCanonicalised() throws {
        let input = #"""
            {
              "numbers": [333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001],
              "string": "\u20ac$\u000F\u000aA'\u0042\u0022\u005c\\\"\/",
              "literals": [null, true, false]
            }
            """#
        let want = #"{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\u000f\nA'B\"\\\\\"/"}"#
        #expect(Canonical.form(try JSONValue.parse(input)) == want)
    }

    /// Members are sorted by their keys' UTF-16 code units (RFC 8785, section 3.2.3).
    @Test func keysAreSortedByUTF16CodeUnits() throws {
        let input = #"{"\u20ac": 1, "\r": 2, "\ufb33": 3, "1": 4, "\ud83d\ude00": 5, "\u0080": 6, "\u00f6": 7}"#
        #expect(Canonical.form(try JSONValue.parse(input)) == "{\"\\r\":2,\"1\":4,\"\u{80}\":6,\"ö\":7,\"€\":1,\"😀\":5,\"\u{FB33}\":3}")
    }

    /// Numbers as ECMAScript writes them (RFC 8785, appendix B).
    @Test func numbersAreWrittenAsECMAScriptWritesThem() {
        let cases: [(Double, String)] = [
            (0, "0"), (-0.0, "0"), (1, "1"), (-1, "-1"), (2.5, "2.5"), (100, "100"), (0.1, "0.1"), (0.18, "0.18"),
            (5e-324, "5e-324"), (1.7976931348623157e308, "1.7976931348623157e+308"), (9007199254740992, "9007199254740992"),
            (-9007199254740992, "-9007199254740992"), (295147905179352830000, "295147905179352830000"),
            (9.999999999999997e22, "9.999999999999997e+22"), (1e23, "1e+23"), (1e21, "1e+21"), (1e20, "100000000000000000000"),
            (999999999999999700000, "999999999999999700000"), (0.000001, "0.000001"), (1e-7, "1e-7"),
            (9.999999999999997e-7, "9.999999999999997e-7"), (123e-20, "1.23e-18"), (0.000123, "0.000123"),
        ]
        for (n, want) in cases { #expect(Canonical.number(n) == want, "\(n)") }
    }

    /// The hash is SHA-256 of the canonical form's UTF-8 bytes, in lowercase hexadecimal; the
    /// expected digests were computed by `shasum -a 256` over the canonical text.
    @Test func theHashIsSHA256OfTheCanonicalForm() throws {
        #expect(Canonical.hash(.object(JSONObject())) == "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a")
        let v = try JSONValue.parse(#"""
            {"b": [1, 2.5, -0, 1e21, 1e-7, 0.000001, 100, "x\u00e9\u20ac\n\"\\"], "a": {"z": true, "y": null, "\u00f6": "\u0001"},
             "c": 333333333.33333329}
            """#)
        #expect(Canonical.form(v) == #"{"a":{"y":null,"z":true,"ö":"\u0001"},"b":[1,2.5,0,1e+21,1e-7,0.000001,100,"xé€\n\"\\"],"c":333333333.3333333}"#)
        #expect(Canonical.hash(v) == "6a94a6c8c7720a2c0f3238024b21898a5d052887c6412a3e51622ce628aad6ea")
        #expect(Canonical.shortHash(v) == "6a94a6c8c772")
    }

    @Test func theDocumentsHashIgnoresLayoutButNotContent() throws {
        let d = DocumentFixture.subtraction
        #expect(d.hash.count == 64 && d.shortHash == String(d.hash.prefix(12)))
        // Reformatted and reordered, it is the same document.
        let reordered = try #require(ExplainerDocument.read(Data(Canonical.form(d.json).utf8)).document)
        #expect(reordered.hash == d.hash)
        let changed = try #require(ExplainerDocument.read(d.json.setting("/about/notes", .string("x")).data).document)
        #expect(changed.hash != d.hash)
    }

    @Test func theRevisionChangesOnlyWithWhatAWordingAndLocaleShowAndSay() throws {
        let d = DocumentFixture.subtraction
        let everyday = d.revision(wording: "everyday", locale: "en-US")
        let formal = d.revision(wording: "formal", locale: "en-US")
        #expect(everyday.count == 12 && everyday != formal)
        func doc(_ v: JSONValue) throws -> ExplainerDocument { try #require(ExplainerDocument.read(v.data).document) }
        // Not changed by about, by translators' notes and lengths, by another wording, or by another locale.
        let same: [JSONValue] = [
            d.json.setting("/about/authors", .array([.string("A. Author")])),
            d.json.setting("/wording/en-US/everyday/show", try JSONValue.parse(#"{"text": "This is {a}.", "notes": "said first", "maxLength": 40}"#)),
            d.json.setting("/wording/en-US/formal/show", .string("{a} is the number.")),
            d.json.setting("/wording/fr", try JSONValue.parse(#"{"shared": {}, "everyday": {}, "formal": {}}"#)),
        ]
        for v in same { #expect(try doc(v).revision(wording: "everyday", locale: "en-US") == everyday) }
        // Changed by its own lines, by the shared entries, and by the steps.
        let different: [JSONValue] = [
            d.json.setting("/wording/en-US/everyday/show", .string("Here is {a}.")),
            d.json.setting("/wording/en-US/shared/unknown", try JSONValue.parse(#"{"text": "…", "visual": true}"#)),
            d.json.setting("/steps/show/hold", .number(0.2)),
        ]
        for v in different { #expect(try doc(v).revision(wording: "everyday", locale: "en-US") != everyday) }
    }

    @Test func aTranslationRecordsTheHashOfItsSource() throws {
        let d = DocumentFixture.subtraction
        let entry = try #require(d.json.value(at: "/wording/en-US/everyday/show"))
        #expect(d.sourceHash(section: "everyday", entry: "show") == String(Canonical.hash(entry).prefix(8)))
        #expect(Canonical.hash(entry) == Canonical.hash(.string("This is {a}.")))
    }

    @Test func jsonPointersAddressTheDocument() {
        let d = DocumentFixture.subtraction.json
        #expect(d.value(at: "/steps/trade/actions/travel/dur") == .number(1.5))
        #expect(d.value(at: "/sequence/0") == .string("show"))
        #expect(d.value(at: "/sequence/01") == nil && d.value(at: "/nothing") == nil)
        #expect(DocumentPath.join("/x", "a/b", "c~d") == "/x/a~1b/c~0d")
    }
}
