#!/usr/bin/env python3
"""Bundles the Axer offline boot test: harness prelude + real axer sources
(seeded into the mock filesystem) + test body, then runs the bundle with the
standalone Luau CLI."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST = ROOT / "test"
LUAU = ROOT / ".freebuff" / "tools" / "luau.exe"

SEED_FILES = [
    "axer/libraries/util.lua",
    "axer/libraries/shims.lua",
    "axer/libraries/module.lua",
    "axer/libraries/gui.lua",
    "axer/libraries/save.lua",
    "axer/main.lua",
    "axer/games/universal.lua",
]


def lua_literal(text: str) -> str:
    out = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
        .replace("\r", "\\r")
    )
    return f'"{out}"'


def main() -> int:
    if not LUAU.exists():
        print(f"Luau CLI not found at {LUAU}. Run the setup step first.")
        return 2

    prelude = (TEST / "harness_prelude.lua").read_text(encoding="utf-8")
    body = (TEST / "boot_test_body.lua").read_text(encoding="utf-8")

    seeds = []
    for rel in SEED_FILES:
        source = (ROOT / rel).read_text(encoding="utf-8")
        seeds.append(f"TESTFILES[{lua_literal(rel)}] = {lua_literal(source)}")

    boot = (
        'print("[boot] executing axer/main.lua through the loadstring pipeline")\n'
        'Axer = assert(loadstring(TESTFILES["axer/main.lua"], "main"))()\n'
    )

    bundle = "\n".join([prelude, "\n".join(seeds), boot, body]) + "\n"
    out = TEST / "boot_bundle.lua"
    out.write_text(bundle, encoding="utf-8")

    result = subprocess.run(
        [str(LUAU), str(out)],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
        timeout=120,
    )
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
