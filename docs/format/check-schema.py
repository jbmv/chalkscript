"""Checks the explainer format's JSON Schema against the example documents.

The schema must accept both examples and refuse a document with an unknown verb, a missing
required key, a value of the wrong type, or an `areas` entry that lacks `layout` or `ratio`, whose
`ratio` is not two numbers above 0, an empty `areas`, an element's `let` that is not an object of
named values, a `turn` or `pivot` on a text element, an outline or a piece, or a `turn` verb whose `to` is not a
number, a document colour with no value and no suggested colour or with a value that is not `#RRGGBB`, an `appearances` that is empty, repeats a name, is not an array or names anything but `light` and `dark`, a `profile` that is not a name, and a
`style.palette`, a `width` on a line, arrow, outline or shape that is 0, below 0, a list or an empty string, and a `width` on a text element, a group without `members`, with a `progress` in its `start` or with a `width`, an `appear` with both `from` and `rise` or with a `from` that is not a point or a selection, an arc entry of two numbers, with a key other than `arc`, `from` and `to`, or without `to`, a shot whose `up` is a list, a group without `members`, with a `progress` in its `start` or with a `width`, an `appear` with both `from` and `rise` or with a `from` that is not a point or a selection, and a `style.overrides` entry with no value. It must accept a `style.overrides` entry with its values, with or without `asked`, a `profile`, `appearances` of one or of both, `colours` by values (one value in a document made for one appearance) and by a suggested colour, a `tag` with an `ink`, arc entries among a shape's `points`, a group with its keys, an `appear` from a point or an instance, an element's `let` of expressions, a shot's `up`, and the keys `turn` and `pivot` of a line, arrow or
shape and the verb `turn` (the capability `drawing.turn`), and a `width` that is a number above 0 or an expression on a line, arrow, outline and shape. Each refused document is an example with one
change, and the check also requires that the schema refuses it at the place that was changed. That a
document that uses `drawing.turn` lists it in `requires` is a finding of the reader, not of the schema.

Usage: python3 docs/format/check-schema.py

The `jsonschema` package is used when it is installed. Otherwise the script uses its own validator
of the keywords the schema uses (draft 2020-12), which refuses a schema with any other keyword.
"""
import copy
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SCHEMA = HERE / "explainer-1.0.schema.json"
HAND = {"kind": "shape", "closed": True, "fill": "text", "pivot": [200, 300],
        "points": [[210, 300], [200, 200], [190, 300], [200, 320]]}
EXAMPLES = [HERE / "examples" / "subtraction.explainer", HERE / "examples" / "equal-groups.explainer"]

ANNOTATIONS = {"$schema", "$defs", "title", "description"}
KEYWORDS = {
    "type", "const", "enum", "pattern", "minLength", "maxLength", "minimum", "maximum", "exclusiveMinimum",
    "exclusiveMaximum", "properties", "required", "additionalProperties", "propertyNames", "minProperties",
    "dependentRequired", "items", "prefixItems", "minItems", "maxItems", "uniqueItems", "oneOf", "anyOf", "allOf",
    "if", "then", "$ref",
}


def is_type(value, name):
    if name == "object":
        return isinstance(value, dict)
    if name == "array":
        return isinstance(value, list)
    if name == "string":
        return isinstance(value, str)
    if name == "boolean":
        return isinstance(value, bool)
    if name == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if name == "integer":
        return is_type(value, "number") and float(value).is_integer()
    raise ValueError(f"unknown type {name}")


def same(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    return a == b


class Validator:
    """A validator of the subset of JSON Schema 2020-12 that the format's schema uses."""

    def __init__(self, schema):
        self.root = schema
        self.check_schema(schema)

    def check_schema(self, s):
        if isinstance(s, bool):
            return
        unknown = set(s) - KEYWORDS - ANNOTATIONS
        if unknown:
            raise ValueError(f"the fallback validator does not implement {sorted(unknown)}")
        for k in ("properties", "$defs"):
            for sub in s.get(k, {}).values():
                self.check_schema(sub)
        for k in ("additionalProperties", "propertyNames", "items", "if", "then"):
            if k in s:
                self.check_schema(s[k])
        for k in ("prefixItems", "oneOf", "anyOf", "allOf"):
            for sub in s.get(k, []):
                self.check_schema(sub)

    def resolve(self, ref):
        if not ref.startswith("#/"):
            raise ValueError(f"only local references are implemented: {ref}")
        node = self.root
        for part in ref[2:].split("/"):
            node = node[part.replace("~1", "/").replace("~0", "~")]
        return node

    def errors(self, value, schema=None, path=""):
        """Yields (path, message) for every way `value` fails `schema`."""
        s = self.root if schema is None else schema
        if s is True:
            return
        if s is False:
            yield path, "no value is allowed here"
            return
        if "$ref" in s:
            yield from self.errors(value, self.resolve(s["$ref"]), path)
        if "type" in s:
            types = s["type"] if isinstance(s["type"], list) else [s["type"]]
            if not any(is_type(value, t) for t in types):
                yield path, f"expected {' or '.join(types)}"
                return
        if "const" in s and not same(value, s["const"]):
            yield path, f"expected {s['const']!r}"
        if "enum" in s and not any(same(value, e) for e in s["enum"]):
            yield path, f"expected one of {s['enum']}"
        if isinstance(value, str):
            if "pattern" in s and not re.search(s["pattern"], value):
                yield path, f"{value!r} does not match {s['pattern']}"
            if len(value) < s.get("minLength", 0):
                yield path, "too short"
            if "maxLength" in s and len(value) > s["maxLength"]:
                yield path, "too long"
        if is_type(value, "number"):
            if "minimum" in s and value < s["minimum"]:
                yield path, f"less than {s['minimum']}"
            if "maximum" in s and value > s["maximum"]:
                yield path, f"more than {s['maximum']}"
            if "exclusiveMinimum" in s and value <= s["exclusiveMinimum"]:
                yield path, f"not more than {s['exclusiveMinimum']}"
            if "exclusiveMaximum" in s and value >= s["exclusiveMaximum"]:
                yield path, f"not less than {s['exclusiveMaximum']}"
        if isinstance(value, dict):
            yield from self.object_errors(value, s, path)
        if isinstance(value, list):
            yield from self.array_errors(value, s, path)
        for sub in s.get("allOf", []):
            yield from self.errors(value, sub, path)
        if "anyOf" in s and not any(self.valid(value, sub, path) for sub in s["anyOf"]):
            yield path, "matches none of the alternatives"
        if "oneOf" in s:
            n = sum(self.valid(value, sub, path) for sub in s["oneOf"])
            if n != 1:
                # Report the closest alternative's errors, so the place at fault is named.
                if n == 0:
                    best = min((list(self.errors(value, sub, path)) for sub in s["oneOf"]), key=len)
                    yield from best if best else [(path, "matches none of the alternatives")]
                else:
                    yield path, "matches more than one alternative"
        if "if" in s and self.valid(value, s["if"], path) and "then" in s:
            yield from self.errors(value, s["then"], path)

    def object_errors(self, value, s, path):
        for k in s.get("required", []):
            if k not in value:
                yield path, f"missing required key {k!r}"
        for k, keys in s.get("dependentRequired", {}).items():
            if k in value:
                for d in keys:
                    if d not in value:
                        yield path, f"{k!r} requires {d!r}"
        if len(value) < s.get("minProperties", 0):
            yield path, "too few keys"
        props = s.get("properties", {})
        for k, v in value.items():
            p = f"{path}/{k.replace('~', '~0').replace('/', '~1')}"
            if "propertyNames" in s:
                for _, msg in self.errors(k, s["propertyNames"], p):
                    yield p, f"key {k!r}: {msg}"
            if k in props:
                yield from self.errors(v, props[k], p)
            elif "additionalProperties" in s:
                if s["additionalProperties"] is False:
                    yield p, f"unknown key {k!r}"
                else:
                    yield from self.errors(v, s["additionalProperties"], p)

    def array_errors(self, value, s, path):
        if len(value) < s.get("minItems", 0):
            yield path, f"fewer than {s['minItems']} items"
        if "maxItems" in s and len(value) > s["maxItems"]:
            yield path, f"more than {s['maxItems']} items"
        if s.get("uniqueItems"):
            seen = [json.dumps(v, sort_keys=True) for v in value]
            if len(set(seen)) != len(seen):
                yield path, "items are not unique"
        prefix = s.get("prefixItems", [])
        for i, v in enumerate(value):
            sub = prefix[i] if i < len(prefix) else s.get("items", True)
            yield from self.errors(v, sub, f"{path}/{i}")

    def valid(self, value, schema, path=""):
        return next(iter(self.errors(value, schema, path)), None) is None


def validator(schema):
    """Returns a function from a document to its list of (path, message) errors, and its name."""
    try:
        import jsonschema
    except ImportError:
        v = Validator(schema)
        return (lambda doc: list(v.errors(doc))), "the script's own validator"
    jsonschema.Draft202012Validator.check_schema(schema)
    v = jsonschema.Draft202012Validator(schema)

    def errors(doc):
        out = []
        for e in v.iter_errors(doc):
            # Descend into the alternatives, so the place at fault is named.
            leaves = [e]
            while leaves[0].context:
                leaves = sorted(leaves[0].context, key=lambda c: -len(c.absolute_path))
            out += [("/" + "/".join(str(p) for p in leaf.absolute_path), leaf.message) for leaf in leaves]
        return out

    return errors, f"jsonschema {jsonschema.__version__}"


def changed(doc, change):
    d = copy.deepcopy(doc)
    change(d)
    return d


def main():
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    errors, used = validator(schema)
    failures = 0
    print(f"validating with {used}")
    docs = {}
    for path in EXAMPLES:
        docs[path.name] = json.loads(path.read_text(encoding="utf-8"))
        found = errors(docs[path.name])
        print(f"{'accepted' if not found else 'REFUSED'}: {path.name}")
        for p, m in found[:10]:
            print(f"    {p}: {m}")
        failures += bool(found)

    groups = docs["equal-groups.explainer"]
    refused = [
        ("an unknown verb", "/steps/same/actions/mark/do",
         lambda d: d["steps"]["same"]["actions"]["mark"].update({"do": "spin"})),
        ("an unknown verb inside an each", "/steps/skip/actions/count/then/tag/do",
         lambda d: d["steps"]["skip"]["actions"]["count"]["then"]["tag"].update({"do": "erase"})),
        ("a missing required key (sequence)", "",
         lambda d: d.pop("sequence")),
        ("a missing required key (a verb's parameter)", "/steps/same/actions/mark",
         lambda d: d["steps"]["same"]["actions"]["mark"].pop("ink")),
        ("a value of the wrong type (samples)", "/samples",
         lambda d: d.update({"samples": {"a": 2, "b": 2}})),
        ("a value of the wrong type (a duration)", "/steps/same/actions/loop/dur",
         lambda d: d["steps"]["same"]["actions"]["loop"].update({"dur": [0.9]})),
        ("an areas entry without layout", "/areas/0",
         lambda d: d["areas"][0].pop("layout")),
        ("an areas entry without ratio", "/areas/0",
         lambda d: d["areas"][0].pop("ratio")),
        ("an areas ratio of one number", "/areas/0/ratio",
         lambda d: d["areas"][0].update({"ratio": [0.9]})),
        ("an areas ratio that is not numbers", "/areas/0/ratio/1",
         lambda d: d["areas"][0].update({"ratio": [0.9, "wide"]})),
        ("an areas ratio with a minimum of 0", "/areas/0/ratio/0",
         lambda d: d["areas"][0].update({"ratio": [0, 2.2]})),
        ("an empty areas", "/areas",
         lambda d: d.update({"areas": []})),
        ("an element's let that is not an object", "/elements/dot/let",
         lambda d: d["elements"]["dot"].update({"let": "i + 1"})),
        ("an element's let value that is not a value", "/elements/dot/let/k",
         lambda d: d["elements"]["dot"].update({"let": {"k": ["i"]}})),
        ("a turn on a text element", "/elements/equation/turn",
         lambda d: d["elements"]["equation"].update({"turn": 30})),
        ("a pivot on a text element", "/elements/equation/pivot",
         lambda d: d["elements"]["equation"].update({"pivot": [0, 0]})),
        ("a turn on an outline", "/elements/ring/turn",
         lambda d: d["elements"]["ring"].update({"turn": 30})),
        ("a turn on a piece", "/elements/dot/turn",
         lambda d: d["elements"]["dot"].update({"turn": 30})),
        ("a turn that is not a number", "/elements/hand/turn",
         lambda d: d["elements"].update({"hand": dict(HAND, turn=[30])})),
        ("a pivot that is not a point", "/elements/hand/pivot",
         lambda d: d["elements"].update({"hand": dict(HAND, pivot=[0])})),
        ("a turn verb whose to is not a number", "/steps/same/actions/spin/to",
         lambda d: d["steps"]["same"]["actions"].update({"spin": {"do": "turn", "target": "hand", "to": [90]}})),
        ("a document colour with neither value nor a suggested colour", "/colours/hour",
         lambda d: d.update({"colours": {"hour": {"cue": "the short hand"}}})),
        ("an appearance that is not light or dark", "/appearances/0",
         lambda d: d.update({"appearances": ["sepia"]})),
        ("an empty appearances", "/appearances",
         lambda d: d.update({"appearances": []})),
        ("a repeated appearance", "/appearances",
         lambda d: d.update({"appearances": ["dark", "dark"]})),
        ("appearances that is not an array", "/appearances",
         lambda d: d.update({"appearances": "dark"})),
        ("a document colour that is not #RRGGBB", "/colours/hour/light",
         lambda d: d.update({"colours": {"hour": {"light": "red", "dark": "#F59623"}}})),
        ("a profile that is not a name", "/profile",
         lambda d: d.update({"profile": 3})),
        ("a palette in a document's style", "/style/palette",
         lambda d: d.update({"style": {"palette": {"light": {"text": "#000000"}}}})),
        ("a width of 0 on a line", "/elements/rule/width",
         lambda d: d["elements"].update({"rule": {"kind": "line", "from": [0, 0], "to": [0, 10], "width": 0}})),
        ("a width below 0 on an arrow", "/elements/pointer/width",
         lambda d: d["elements"].update({"pointer": {"kind": "arrow", "ink": "multiply", "from": [0, 0], "to": [0, 10], "width": -2}})),
        ("a width of 0 on an outline", "/elements/ring/width",
         lambda d: d["elements"]["ring"].update({"width": 0})),
        ("a width that is a list on a shape", "/elements/hand/width",
         lambda d: d["elements"].update({"hand": dict(HAND, width=[4])})),
        ("a width that is an empty string on a line", "/elements/rule/width",
         lambda d: d["elements"].update({"rule": {"kind": "line", "from": [0, 0], "to": [0, 10], "width": ""}})),
        ("a width on a text element", "/elements/equation/width",
         lambda d: d["elements"]["equation"].update({"width": 4})),
        ("a group without members", "/elements/pair",
         lambda d: d["elements"].update({"pair": {"kind": "group"}})),
        ("a group whose start has a progress", "/elements/pair/start/progress",
         lambda d: d["elements"].update({"pair": {"kind": "group", "members": "dot", "start": {"progress": 0}}})),
        ("a group with a width", "/elements/pair/width",
         lambda d: d["elements"].update({"pair": {"kind": "group", "members": "dot", "width": 3}})),
        ("an appear with from and rise", "/steps/same/actions/enter/rise",
         lambda d: d["steps"]["same"]["actions"].update({"enter": {"do": "appear", "target": "dot", "from": [0, 0], "rise": 10}})),
        ("an appear whose from is one number", "/steps/same/actions/enter/from",
         lambda d: d["steps"]["same"]["actions"].update({"enter": {"do": "appear", "target": "dot", "from": [0]}})),
        ("an arc entry of two numbers", "/elements/hand/points/0",
         lambda d: d["elements"].update({"hand": dict(HAND, points=[{"arc": [0, 0], "from": 0, "to": 90}])})),
        ("an arc entry with a key other than arc, from and to", "/elements/hand/points/0",
         lambda d: d["elements"].update({"hand": dict(HAND, points=[{"arc": [0, 0, 5], "from": 0, "to": 90, "sweep": 90}])})),
        ("an arc entry without to", "/elements/hand/points/0",
         lambda d: d["elements"].update({"hand": dict(HAND, points=[{"arc": [0, 0, 5], "from": 0}])})),
        ("a shot whose up is a list", "/shots/look/up",
         lambda d: d.update({"shots": {"look": {"region": [0, 0, 100, 100], "up": [90]}}})),
        ("a changed operation colour with no value", "/style/overrides/multiply",
         lambda d: d.update({"style": {"overrides": {"multiply": {"asked": "orange, please"}}}})),
    ]
    accepted = [
        ("a turn and a pivot on a line, an arrow and a shape",
         lambda d: d["elements"].update({
             "hand": dict(HAND, turn="30 * 2", pivot=[200, "a"]),
             "rule": {"kind": "line", "from": [0, 0], "to": [0, 10], "turn": 45},
             "pointer": {"kind": "arrow", "ink": "multiply", "from": [0, 0], "to": [0, 10], "turn": 45, "pivot": [0, 5]}})),
        ("the verb turn, with and without to, and inside an each",
         lambda d: d["steps"]["same"]["actions"].update({
             "spin": {"do": "turn", "target": "hand", "to": "a * 30", "dur": 1, "ease": "linear", "mark": True},
             "back": {"do": "turn", "target": "hand", "at": "end(spin)"},
             "each": {"do": "each", "target": "hand", "gap": 0.2, "then": {"spin": {"do": "turn", "to": 90}}}})),
        ("a group, with members, a pivot and a turn, and a repeated one with a let",
         lambda d: d["elements"].update({
             "pair": {"kind": "group", "members": "dot + ring", "pivot": [10, "a"], "turn": 30, "start": {"opacity": 0}, "z": 2, "fixed": False},
             "pairs": {"kind": "group", "repeat": 2, "let": {"k": "i"}, "when": "a > 0", "members": "dot[k]"}})),
        ("an appear from a point and from one instance, in an each too",
         lambda d: d["steps"]["same"]["actions"].update({
             "enter": {"do": "appear", "target": "dot", "from": [0, "a"], "grow": 0.25},
             "again": {"do": "appear", "target": "dot", "from": "ring", "dur": 1},
             "each": {"do": "each", "target": "dot", "gap": 0.2, "then": {"enter": {"do": "appear", "from": "ring[i]"}}}})),
        ("arc entries, with expressions, among a shape's points",
         lambda d: d["elements"].update({
             "orbit": {"kind": "shape", "ink": "line", "points": [{"arc": [440, 270, 170], "from": 270, "to": -90}]},
             "lit": dict(HAND, points=[[0, 0], {"arc": ["a", 0, 10, "a * 2"], "from": 0, "to": "a"}])})),
        ("a width, a number or an expression, on a line, an arrow, an outline and a shape",
         lambda d: (d["elements"]["ring"].update({"width": "a * 2"}),
                    d["elements"].update({
                        "hand": dict(HAND, width=12),
                        "rule": {"kind": "line", "from": [0, 0], "to": [0, 10], "width": 0.5},
                        "pointer": {"kind": "arrow", "ink": "multiply", "from": [0, 0], "to": [0, 10], "width": "a + 2"}}))),
        ("a profile, document colours by values and by a suggested colour, and a tag with an ink",
         lambda d: (d.update({"profile": "open", "colours": {
             "hour": {"light": "#B5481F", "dark": "#F59623", "cue": "the short hand"},
             "minute": {"suggested": "purple", "cue": "the long hand"}}}),
             d["steps"]["same"]["actions"].update({"card": {"do": "tag", "target": "equation", "text": "same", "ink": "hour"}}))),
        ("appearances of one, with a document colour that gives only that value",
         lambda d: d.update({"appearances": ["dark"], "colours": {"hour": {"dark": "#F59623", "cue": "the short hand"}}})),
        ("appearances of both",
         lambda d: d.update({"appearances": ["light", "dark"]})),
        ("a changed operation colour with its values and no request",
         lambda d: d.update({"style": {"overrides": {"multiply": {"light": "#B5481F", "dark": "#F59623"}}}})),
        ("a changed operation colour with its values and the request",
         lambda d: d.update({"style": {"overrides": {"multiply": {"light": "#B5481F", "dark": "#F59623", "asked": "orange, please"}}}})),
        ("an element's let of expressions", lambda d: d["elements"]["dot"].update({"let": {"k": "i + 1", "r": "k * 2"}})),
        ("a shot's up, a number and an expression",
         lambda d: d.update({"shots": {"look": {"region": [0, 0, 100, 100], "up": 90}, "along": {"region": [0, 0, 100, 100], "up": "a * 45"}}})),
    ]
    for what, change in accepted:
        found = errors(changed(groups, change))
        print(f"{'accepted' if not found else 'REFUSED'}: {what}")
        for p, m in found[:10]:
            print(f"    {p}: {m}")
        failures += bool(found)

    for what, where, change in refused:
        found = errors(changed(groups, change))
        named = any(p == where or (where and p.startswith(where + "/")) for p, _ in found)
        ok = bool(found) and named
        print(f"{'refused' if ok else 'NOT REFUSED AT THE PLACE CHANGED'}: {what}, at {where or '/'}")
        if not ok:
            for p, m in found[:10]:
                print(f"    {p}: {m}")
        failures += not ok

    print("ok" if not failures else f"{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
