#!/usr/bin/env python3
"""Drives the studio's helper over stdio as an MCP client would, without Claude.

Usage: Studio/Scripts/drive-helper.py HELPER [look|edit|all]

HELPER is the chalkscript-mcp binary, such as the one inside the built app:
  "Studio/build/DerivedData/Build/Products/Release/ChalkScript Studio.app/Contents/Helpers/chalkscript-mcp"

ChalkScript Studio must be running with a project that holds the example equal-groups.
  look  lists the documents, reads a step and a line of equal-groups, and shows its first step.
  edit  reads the document's hash, changes a duration and a line by one patch, and shows the step.
  all   does both (the default).
Each request is printed with "->" and the text of its result with "<-". Uses only the standard
library.
"""
import json
import subprocess
import sys

DOC = "equal-groups"
# The duration of drawing each ring, and the line said as the groups are made.
DURATION = "/steps/groups/actions/build/then/ring/dur"
LINE = "/wording/en-US/everyday/make"


class Helper:
    def __init__(self, path):
        self.process = subprocess.Popen([path], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.next_id = 1

    def request(self, method, params=None, quiet=False):
        message = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            message["params"] = params
        self.next_id += 1
        line = json.dumps(message, ensure_ascii=False)
        if not quiet:
            print("->", line)
        self.process.stdin.write(line + "\n")
        self.process.stdin.flush()
        while True:
            reply = json.loads(self.process.stdout.readline())
            if reply.get("id") == message["id"]:
                return reply

    def notify(self, method):
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method}) + "\n")
        self.process.stdin.flush()

    def tool(self, name, arguments):
        reply = self.request("tools/call", {"name": name, "arguments": arguments})
        if "error" in reply:
            print("<- error", json.dumps(reply["error"], ensure_ascii=False))
            return None, True
        result = reply["result"]
        texts = []
        for block in result.get("content", []):
            if block.get("type") == "text":
                texts.append(block["text"])
            else:
                texts.append("[%s, %d characters of base64]" % (block.get("type"), len(block.get("data", ""))))
        text = "\n".join(texts)
        print("<-" + (" (tool error)" if result.get("isError") else ""), text.replace("\n", "\n   "))
        return text, result.get("isError", False)

    def close(self):
        self.process.stdin.close()
        self.process.wait(timeout=5)


def hash_of(text):
    return text.split("\n", 1)[0].removeprefix("hash ").strip()


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 64
    phase = sys.argv[2] if len(sys.argv) > 2 else "all"
    helper = Helper(sys.argv[1])
    init = helper.request("initialize", {
        "protocolVersion": "2025-11-25", "capabilities": {},
        "clientInfo": {"name": "drive-helper", "version": "1"}})
    print("<- initialize:", init["result"]["protocolVersion"], init["result"]["serverInfo"])
    helper.notify("notifications/initialized")
    tools = helper.request("tools/list", {}, quiet=True)["result"]["tools"]
    print("<- tools/list:", ", ".join(t["name"] for t in tools))

    failed = False
    if phase in ("look", "all"):
        for name, arguments in [
            ("list", {}),
            ("read", {"doc": DOC, "pointer": DURATION}),
            ("read", {"doc": DOC, "pointer": LINE}),
            ("show", {"doc": DOC, "step": "groups"}),
        ]:
            _, error = helper.tool(name, arguments)
            failed = failed or error
    if phase in ("edit", "all"):
        text, error = helper.tool("read", {"doc": DOC, "pointer": "/id"})
        failed = failed or error
        base = hash_of(text or "")
        _, error = helper.tool("edit", {"doc": DOC, "base": base, "ops": [
            {"op": "replace", "path": DURATION, "value": 0.9},
            {"op": "replace", "path": LINE, "value": "Make {groups:a}. Put {b} dots in each group."},
        ]})
        failed = failed or error
        _, error = helper.tool("edit", {"doc": DOC, "base": base, "ops": [{"op": "replace", "path": DURATION, "value": 1}]})
        print("   (the second edit reuses the old hash, so it must be refused)")
        failed = failed or not error
        for name, arguments in [
            ("read", {"doc": DOC, "pointer": DURATION}),
            ("read", {"doc": DOC, "pointer": LINE}),
            ("check", {"doc": DOC}),
            ("show", {"doc": DOC, "step": "groups"}),
        ]:
            _, error = helper.tool(name, arguments)
            failed = failed or error
    helper.close()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
