#!/usr/bin/env python3
"""
update_data.py -- regenerate TopFit's data files from the Forever sim clone in one go.

    cd <Addons>/TopFit
    python tools/update_data.py

Expects the clone at <Addons>/Forever (next to TopFit). Anything else:
    python tools/update_data.py --repo D:/games/Forever
    set FOREVER_REPO=D:/games/Forever            (or export on Linux/macOS)

Writes  procdata.lua  (item proc / on-use data)   and   setdata.lua  (item set bonuses)  into the addon folder.
Add --pull to `git pull` the clone first; run again after a client patch or when the sim data changes.
"""
import argparse
import subprocess
import sys

import gen_procdata
import gen_setdata
from fvspells import add_common_args, require_repo


def main():
    parser = argparse.ArgumentParser(description="Regenerate procdata.lua and setdata.lua from the Forever sim clone.")
    add_common_args(parser)
    parser.add_argument("--pull", action="store_true", help="git pull the Forever clone first")
    parser.add_argument("--only", choices=("procs", "sets"), help="regenerate just one of the two files")
    args = parser.parse_args()

    repo = require_repo(args.repo)
    if args.pull:
        print("git pull in", repo)
        if subprocess.call(["git", "-C", str(repo), "pull", "--ff-only"]) != 0:
            sys.exit("git pull failed; fix the clone or run without --pull")

    print("sim data:", repo)
    if args.only != "sets":
        print("\n== procdata.lua ==")
        gen_procdata.generate(repo, args.addon / "procdata.lua")
    if args.only != "procs":
        print("\n== setdata.lua ==")
        gen_setdata.generate(repo, args.addon / "setdata.lua")


if __name__ == "__main__":
    main()
