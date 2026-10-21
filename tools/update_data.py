#!/usr/bin/env python3
"""
update_data.py -- regenerate TopFit's data files from the Forever sim clone in one go.

    cd <Addons>/TopFit
    python tools/update_data.py

Expects the clone at <Addons>/Forever (next to TopFit). Anything else:
    python tools/update_data.py --repo D:/games/Forever
    set FOREVER_REPO=D:/games/Forever            (or export on Linux/macOS)

<<<<<<< HEAD
Writes  procdata.lua  (item proc / on-use data),  setdata.lua  (item set bonuses)  and the sim-preset block of
presets.lua  (EP stat weights) into the addon folder.
=======
Writes  procdata.lua  (item proc / on-use data)   and   setdata.lua  (item set bonuses)  into the addon folder.
>>>>>>> 68329dd089ce6b905f497196fff18a0ca0fdeb02
Add --pull to `git pull` the clone first; run again after a client patch or when the sim data changes.
"""
import argparse
import subprocess
import sys
<<<<<<< HEAD
from pathlib import Path

import gen_presets
=======

>>>>>>> 68329dd089ce6b905f497196fff18a0ca0fdeb02
import gen_procdata
import gen_setdata
from fvspells import add_common_args, require_repo


def main():
    parser = argparse.ArgumentParser(description="Regenerate procdata.lua and setdata.lua from the Forever sim clone.")
    add_common_args(parser)
    parser.add_argument("--pull", action="store_true", help="git pull the Forever clone first")
<<<<<<< HEAD
    parser.add_argument("--only", choices=("procs", "sets", "presets"), help="regenerate just one of the three files")
    parser.add_argument("--db", type=Path, help="wowsims.db for the item-set tables (default: <repo>/tools/database/wowsims.db)")
=======
    parser.add_argument("--only", choices=("procs", "sets"), help="regenerate just one of the two files")
>>>>>>> 68329dd089ce6b905f497196fff18a0ca0fdeb02
    args = parser.parse_args()

    repo = require_repo(args.repo)
    if args.pull:
        print("git pull in", repo)
        if subprocess.call(["git", "-C", str(repo), "pull", "--ff-only"]) != 0:
            sys.exit("git pull failed; fix the clone or run without --pull")

    print("sim data:", repo)
<<<<<<< HEAD
    if args.only in (None, "procs"):
        print("\n== procdata.lua ==")
        gen_procdata.generate(repo, args.addon / "procdata.lua")
    if args.only in (None, "presets"):
        print("\n== presets.lua (sim presets block) ==")
        gen_presets.generate(repo, args.addon / "presets.lua")
    if args.only in (None, "sets"):
        print("\n== setdata.lua ==")
        try:
            gen_setdata.generate(repo, args.addon / "setdata.lua", args.db)
        except SystemExit as exc:      # keep the procdata.lua we just wrote; report and fail at the end
            print(exc)
            print("setdata.lua NOT updated.")
            sys.exit(1)
=======
    if args.only != "sets":
        print("\n== procdata.lua ==")
        gen_procdata.generate(repo, args.addon / "procdata.lua")
    if args.only != "procs":
        print("\n== setdata.lua ==")
        gen_setdata.generate(repo, args.addon / "setdata.lua")
>>>>>>> 68329dd089ce6b905f497196fff18a0ca0fdeb02


if __name__ == "__main__":
    main()
