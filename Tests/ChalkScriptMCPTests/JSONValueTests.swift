import Testing
@testable import ChalkScriptMCP

struct JSONValueTests {
    @Test func keepsKeyOrderAndNumberText() throws {
        let text = #"{"z":1,"a":[0.10,-2e3,true,null],"m":{"é":"line\nbreak \"q\" \u00e9"}}"#
        let value = try JSONValue.parse(text)
        #expect(value.object?.keys == ["z", "a", "m"])
        #expect(value["a"]?.array?[0] == .number("0.10"))
        #expect(value.serialized == #"{"z":1,"a":[0.10,-2e3,true,null],"m":{"é":"line\nbreak \"q\" é"}}"#)
        #expect(!value.serialized.contains("\n"), "one line, as the stdio framing needs")
    }

    @Test func decodesSurrogatePairs() throws {
        #expect(try JSONValue.parse(#""\ud83d\ude00""#) == .string("😀"))
    }

    @Test(arguments: [
        "", "{", "[1,]", "{\"a\":1,}", "{\"a\":1,\"a\":2}", "01", "1.", "-", "1e", "tru", "\"\\ud800\"",
        "\"\\udc00x\"", "\"\u{01}\"", "\"\\x\"", "{} {}", "nul", "[1 2]", "{\"a\" 1}", "{1:2}",
    ])
    func refusesWhatIsNotJSON(_ text: String) {
        #expect(throws: JSONParseError.self) { try JSONValue.parse(text) }
    }

    @Test func refusesDeepNestingWithoutCrashing() {
        let deep = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        #expect(throws: JSONParseError.self) { try JSONValue.parse(deep) }
    }

    @Test func refusesInvalidUTF8() {
        #expect(throws: JSONParseError.self) { try JSONValue.parse([0x22, 0xFF, 0xFE, 0x22]) }
    }

    @Test func writesControlCharactersEscaped() {
        #expect(JSONValue.string("a\u{01}\u{2028}b").serialized == #""a\u0001\u2028b""#)
    }

    @Test func objectSubscriptReplacesInPlaceAndRemoves() {
        var object: JSONObject = ["a": .int(1), "b": .int(2)]
        object["a"] = .int(3)
        object["b"] = nil
        object["c"] = .null
        #expect(JSONValue.object(object).serialized == #"{"a":3,"c":null}"#)
    }
}
