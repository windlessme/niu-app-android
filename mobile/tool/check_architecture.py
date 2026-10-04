#!/usr/bin/env python3
"""Fail when lib/ imports cross a layer boundary.

Layers, lowest first; a layer may import only itself and those below it:

    shared   design tokens and widgets
    core     session, storage, network, platform bridges, demo data
    features one folder per feature
    app      startup, routing, the main-tab shell

Features may import one another, but core and shared stay feature-free so
they can be reused and tested without any screen.
"""
import re
import sys
from pathlib import Path

LIB = Path(__file__).resolve().parent.parent / "lib"
RANK = {"shared": 0, "core": 1, "features": 2, "app": 3}
IMPORT = re.compile(r"^(?:import|export)\s+'([^']+)'", re.M)


def layer(path: Path) -> str | None:
    parts = path.relative_to(LIB).parts
    return parts[0] if len(parts) > 1 and parts[0] in RANK else None


def main() -> int:
    errors = []
    for source in sorted(LIB.rglob("*.dart")):
        own = layer(source)
        if own is None:
            continue
        for spec in IMPORT.findall(source.read_text(encoding="utf-8")):
            if spec.startswith("package:niu_mobile/"):
                target = LIB / spec[len("package:niu_mobile/"):]
            elif spec.startswith(("package:", "dart:")):
                continue
            else:
                target = (source.parent / spec).resolve()
            other = layer(target)
            if other is not None and RANK[other] > RANK[own]:
                errors.append(f"{source.relative_to(LIB.parent)}: {own} must not import {other} ({spec})")
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"{len(errors)} layer violation(s); see tool/check_architecture.py", file=sys.stderr)
        return 1
    print("architecture: layers ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
