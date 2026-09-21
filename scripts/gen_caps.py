#!/usr/bin/env python3
"""Regenerate caps.mbt from the ncurses Caps capability table.

The Caps file is the source of truth for term.h (MIT/X11 license):
    https://github.com/ThomasDickey/ncurses-snapshots/blob/master/include/Caps

Fetch it with:

    gh api -H "Accept: application/vnd.github.raw+json" \
        repos/ThomasDickey/ncurses-snapshots/contents/include/Caps -o Caps

Each data line is split on whitespace runs (the multiple tabs in the file
are only column padding).  Fields:

    1. long capability name      e.g. `clear_screen`
    2. terminfo code             e.g. `clear`      (always present)
    3. type: bool | num | str
    4. termcap name, `-` if none e.g. `cl`
    5. KEY_xxx name, `-` if none
    6. KEY_xxx value, `-` if none
    7. termcap-translation flags (unused here)
    8. description

The order of the tables defines the binary index of each capability in a
compiled terminfo file, so it must never be reordered (SVr4 compatibility).

Usage:  python scripts/gen_caps.py Caps > caps.mbt
"""
import re
import sys
import datetime


def parse_caps(path):
    caps = []
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if not line.strip() or line.strip().startswith("#"):
            continue
        f = line.split()
        if len(f) < 3 or f[2] not in ("bool", "num", "str"):
            continue
        caps.append(
            {
                "name": f[0],
                "code": f[1],
                "type": f[2],
                "termcap": f[3] if len(f) > 3 and f[3] != "-" else None,
            }
        )
    return caps


def emit(kind, typ, caps):
    """Emit names array, long-name index map, and code/termcap index map."""
    names = [c["name"] for c in caps if c["type"] == typ]
    desc = {"bool": "Boolean", "num": "Numeric", "str": "String"}[typ]

    print(f"///|")
    print(f"/// Standard {desc} capability names, in {typ.title()}Codes order.")
    print(f"pub let {kind}_names : Array[String] = [")
    for n in names:
        print(f'  "{n}",')
    print("]")
    print()

    print(f"///|")
    print(f"/// Name -> binary index lookup for {desc.lower()} capabilities.")
    print(f"pub let {kind}_index : Map[String, Int] = {{")
    for i, c in enumerate(c for c in caps if c["type"] == typ):
        print(f'  "{c["name"]}": {i},')
    print("}")
    print()

    print(f"///|")
    print(
        f"/// Alternate names -> binary index lookup: the two-character"
    )
    print(
        f"/// terminfo code and the termcap name of each capability"
    )
    print(
        f"/// (e.g. `cols`/`co` for `columns`). Source entries may use any"
    )
    print(f"/// of the three spellings.")
    print(f"pub let {kind}_code_index : Map[String, Int] = {{")
    emitted = {}
    for i, c in enumerate(c for c in caps if c["type"] == typ):
        for key in (c["code"], c["termcap"]):
            if key is None:
                continue
            if key not in emitted:
                emitted[key] = i
    for key, i in emitted.items():
        print(f'  "{key}": {i},')
    print("}")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    caps = parse_caps(sys.argv[1])
    counts = {}
    for c in caps:
        counts[c["type"]] = counts.get(c["type"], 0) + 1
    print("// Generated from the ncurses Caps file (MIT/X11 license), which is")
    print("// the source of truth for term.h. The order of each table defines")
    print("// the binary index of the capability in a compiled terminfo file")
    print("// and is fixed for SVr4 binary compatibility; never reorder.")
    print("//")
    print("// Reference: https://github.com/ThomasDickey/ncurses-snapshots/blob/master/include/Caps")
    print(f"// Regenerated {datetime.date.today().isoformat()} by scripts/gen_caps.py")
    print(f"// ({counts.get('bool', 0)} bools, {counts.get('num', 0)} nums, {counts.get('str', 0)} strs)")
    print()
    emit("bool", "bool", caps)
    print()
    emit("num", "num", caps)
    print()
    emit("str", "str", caps)


if __name__ == "__main__":
    main()
