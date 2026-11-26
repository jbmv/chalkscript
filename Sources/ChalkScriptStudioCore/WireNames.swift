#if os(macOS)
import ChalkScriptMCP

// The helper's JSON value, as the protocol carries it; this file imports only the helper's library.

/// A JSON value as the helper protocol carries it, with its numbers' text kept.
typealias WireJSON = JSONValue
typealias WireObject = JSONObject
#endif
