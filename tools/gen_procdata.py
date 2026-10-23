#!/usr/bin/env python3
"""
gen_procdata.py -- builds TopFit's procdata.lua from the WoW: Forever sim repo.

usage (from the TopFit folder):  python tools/gen_procdata.py [--repo ../Forever] [--addon .]
  (tools/update_data.py runs this and gen_setdata.py together.)  Writes <addon>/procdata.lua.

Reads
  assets/database/db.json                    item -> itemEffects (proc chance, ICD, duration, on-use cooldown)
  sim/core/spelldata/spells_auto_gen.go      the client's spell rows (proc flags, RPPM, aura effects)
and writes a Lua table TopFit.ProcData keyed by item ID.

Only effects that grant stats are written: anything TopFit can score (flat stats it has a key for) goes in
`stats`; stat auras it has no key for (ratings, percents, ...) go in `other` so the data is kept but never
scored by accident. Damage/heal/utility procs are skipped and counted in the summary.
"""
import argparse
import json
import re
import sys
from pathlib import Path

from fvspells import (attribution_lines, STAT_NAME_TO_TF, add_common_args, load_spells, load_stat_enum, lua_val, require_repo,
                      spell_stats, trigger_label)



def generate(repo, out_path):
    repo = require_repo(repo, "db", "spells")

    db = json.loads((repo / "assets/database/db.json").read_text(encoding="utf-8"))

    # ---------------------------------------------------------------- spell store
    spells = load_spells(repo / "sim/core/spelldata/spells_auto_gen.go")
    stat_enum = load_stat_enum(repo)     # db.json keys stats by number; the numbering changes between sim versions

    # ---------------------------------------------------------------- build
    items_out = {}
    skipped_nostat = 0
    for it in db["items"]:
        effs = it.get("itemEffects") or []
        rows = []
        for e in effs:
            buff = e.get("buffId")
            if not buff:
                continue
            is_use = "onUse" in e
            is_proc = "proc" in e
            if not (is_use or is_proc):
                continue  # plain equip aura, already in the item's tooltip stats

            # stats: the db's own per-effect scaling first, else read the aura spell(s)
            stats_sim = {}
            stats_tf_direct = {}
            other = []
            duration = e.get("effectDurationMs")
            sc = (e.get("scalingOptions") or {}).get("0", {}).get("stats")
            if sc:
                stats_sim = {int(k): v for k, v in sc.items()}
            # the "(NNN)" in buffName names the spell that carries the proc flags; buffId is the aura it applies
            paren = re.search(r"\((\d+)\)\s*$", e.get("buffName", ""))
            carrier = int(paren.group(1)) if paren else None
            if not stats_sim:
                for sid in (buff, carrier):
                    if sid:
                        s, o, d = spell_stats(sid, spells)
                        if s or o:
                            stats_tf_direct, other = s, o
                            if duration is None and d and d > 0:
                                duration = d
                            break
            if not stats_sim and not stats_tf_direct and not other:
                skipped_nostat += 1
                continue

            stats_tf, unmapped = dict(stats_tf_direct), {}
            for idx, amt in stats_sim.items():
                if amt == 0:
                    continue
                name = stat_enum.get(idx, "stat%d" % idx)
                if name in STAT_NAME_TO_TF:
                    key = STAT_NAME_TO_TF[name]
                    stats_tf[key] = stats_tf.get(key, 0) + amt
                else:
                    unmapped[name[0].lower() + name[1:]] = amt
            ap, rap = "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT"
            if ap in stats_tf and rap in stats_tf and stats_tf[ap] == stats_tf[rap]:
                del stats_tf[rap]  # TopFit counts +AP once at (AP + RAP weight); see GetEffectiveWeights
            if not stats_tf and not unmapped and not other:
                continue

            row = {"spell": buff}
            if duration and duration > 0:
                row["dur"] = duration / 1000.0
            if is_use:
                cd = e["onUse"].get("cooldownMs")
                if cd:
                    row["cd"] = cd / 1000.0
                cat = e["onUse"].get("categoryCooldownMs")
                if cat:
                    row["catcd"] = cat / 1000.0
            else:
                p = e["proc"] or {}
                if p.get("procChance") is not None:
                    row["chance"] = p["procChance"]
                if p.get("icdMs"):
                    row["icd"] = p["icdMs"] / 1000.0
                # trigger flags / RPPM live on the spell rows
                for sid in (carrier, buff):
                    sp = spells.get(sid) if sid else None
                    if sp and (sp["flags"] or sp["rppm"]):
                        row["flags"] = sp["flags"]
                        t = trigger_label(sp["flags"])
                        if t:
                            row["trigger"] = t
                        if sp["rppm"]:
                            row["rppm"] = sp["rppm"]
                        if "icd" not in row and sp["icd"]:
                            row["icd"] = sp["icd"] / 1000.0
                        if "chance" not in row and sp["chance"] and not sp["rppm"]:
                            row["chance"] = sp["chance"] / 100.0
                        break
            row["kind"] = "use" if is_use else "proc"
            if stats_tf:
                row["stats"] = stats_tf
            if unmapped or other:
                row["other"] = dict(unmapped)
                for o in other:
                    row["other"][o] = True
            rows.append(row)
        if rows:
            items_out[it["id"]] = {"name": it["name"], "effects": rows}

    # ---------------------------------------------------------------- lua
    def lua_row(r):
        parts = []
        for k in ("kind", "spell", "dur", "cd", "catcd", "chance", "rppm", "icd", "flags", "trigger"):
            if k in r:
                parts.append("%s=%s" % (k, lua_val(r[k])))
        if "stats" in r:
            parts.append("stats={%s}" % ",".join("%s=%s" % (k, lua_val(v)) for k, v in sorted(r["stats"].items())))
        if "other" in r:
            parts.append("other={%s}" % ",".join("[%s]=%s" % (lua_val(k), lua_val(v)) for k, v in sorted(r["other"].items())))
        return "{" + ", ".join(parts) + "}"

    lines = [
        "-- procdata.lua -- GENERATED by gen_procdata.py from the WoW: Forever sim data. DO NOT EDIT BY HAND.",
        *attribution_lines(repo),
        "-- Real proc chance / internal cooldown / trigger flags / durations per item, taken from the",
        "-- client's own spell data (via the sim). Consumed by procparser.lua before it falls back to",
        "-- tooltip parsing.  Fields:",
        "--   kind    \"use\" or \"proc\"        spell  aura spell the item applies",
        "--   dur     buff duration, sec       cd     on-use cooldown, sec   catcd  shared category cooldown, sec",
        "--   chance  proc chance per trigger event (0-1); absent when the spell is RPPM-based or unknown",
        "--   rppm    real procs per minute    icd    internal cooldown, sec",
        "--   flags   client proc-flag bitmask (dbcenums/proc_flags.go)   trigger  human-readable form of flags",
        "--   stats   flat stats keyed by TopFit stat key (scoreable)",
        "--   other   stat auras TopFit has no flat key for (ratings, percents, ...) -- kept, never scored",
        "-- (TopFit is the global created in core.lua; this file loads after it.)",
        "TopFit.ProcData = {",
    ]
    for iid in sorted(items_out):
        d = items_out[iid]
        lines.append("\t[%d] = { -- %s" % (iid, d["name"].replace("\n", " ")))
        for r in d["effects"]:
            lines.append("\t\t" + lua_row(r) + ",")
        lines.append("\t},")
    lines.append("}")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    n_eff = sum(len(d["effects"]) for d in items_out.values())
    n_stat = sum(1 for d in items_out.values() for r in d["effects"] if "stats" in r)
    n_use = sum(1 for d in items_out.values() for r in d["effects"] if r["kind"] == "use")
    n_chance = sum(1 for d in items_out.values() for r in d["effects"] if "chance" in r or "rppm" in r)
    print("items: %d  effects: %d  (with TopFit-scoreable stats: %d, on-use: %d, with chance/rppm: %d)"
          % (len(items_out), n_eff, n_stat, n_use, n_chance))
    print("effects skipped (no stat aura found): %d" % skipped_nostat)
    print("wrote", out_path)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate procdata.lua from the Forever sim clone.")
    add_common_args(parser)
    args = parser.parse_args(argv)
    generate(args.repo, args.addon / "procdata.lua")


if __name__ == "__main__":
    main()
