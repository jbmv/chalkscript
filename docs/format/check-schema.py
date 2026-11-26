"""Checks the explainer format's JSON Schema against the example documents.

The schema must accept both examples and refuse a document with an unknown verb, a missing
required key, or a value of the wrong type. Each refused document is an example with one change,
and the check also requires that the schema refuses it at the place that was changed.

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
    ]
    for what, where, change in refused:
        found = errors(changed(groups, change))
        named = any(p == where for p, _ in found)
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
