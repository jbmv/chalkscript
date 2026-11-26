#if os(macOS)
import ChalkScript

// The engine and the helper's library each define a JSON value. These names say which is meant in
// the files that use both; this file imports only the engine.

/// A JSON value as the engine's reader holds it.
typealias DocJSON = JSONValue
typealias DocObject = JSONObject
#endif
