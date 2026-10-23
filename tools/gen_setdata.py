#!/usr/bin/env python3
"""
gen_setdata.py -- builds TopFit's setdata.lua (item set bonuses) from the WoW: Forever sim repo.

usage (from the TopFit folder):  python tools/gen_setdata.py [--repo ../Forever] [--addon .] [--db wowsims.db]
  (tools/update_data.py runs this and gen_procdata.py together.)  Writes <addon>/setdata.lua.

Reads the client's item-set tables (ItemSet = set -> piece item IDs, ItemSetSpell = set -> piece threshold +
bonus spell) from, in order of preference:
  1. tools/database/wowsims.db in the sim clone (SQLite; built by `make db` / db2tool from YOUR client, so it is
     always the build you play)                                   -- or any file given with --db
  2. tools/data_watch/.cache/ItemSet*_<build>.csv (older clone layout; newest build found)
plus sim/core/spelldata/spells_auto_gen.go for what each bonus spell does,
and writes TopFit.SetData (by set ID) and TopFit.SetByItem (item ID -> set ID).

Only flat stat bonuses TopFit can score are kept in `stats`. Bonuses TopFit has no stat key for (procs, movement,
ratings, ...) stay in `other` -- visible, never scored. Sets with nothing scoreable are left out entirely.
"""
import argparse
import csv
import json
import re
import sqlite3
import sys
from pathlib import Path

from fvspells import attribution_lines, add_common_args, load_spells, lua_val, require_repo, spell_stats



MISSING_TABLES_HELP = """No item-set tables found. The sim keeps them in tools/database/wowsims.db, which is gitignored and
built from your game client -- in the Forever clone run

    make db                       (needs Go and the WoW install named in tools/database/generator-settings.json)
    or: go run ./tools/db2tool -s tools/database/generator-settings.json --output tools/database/wowsims.db --cdn

then run this again (or point --db at an existing wowsims.db). Until then setdata.lua is left as it was."""


def _columns(con, table):
    cur = con.execute('SELECT * FROM "%s" LIMIT 0' % table)
    return [c[0] for c in cur.description]


def _find_table(con, name):
    for (t,) in con.execute("SELECT name FROM sqlite_master WHERE type='table'"):
        if t.lower() == name.lower():
            return t
    return None


def _load_from_sqlite(db_path):
    """-> (sets {id: {name, items}}, bonus rows [(setID, threshold, spellID)], description)"""
    con = sqlite3.connect("file:%s?mode=ro" % Path(db_path).as_posix(), uri=True)
    t_set, t_spell = _find_table(con, "ItemSet"), _find_table(con, "ItemSetSpell")
    if not t_set or not t_spell:
        sys.exit("%s has no ItemSet/ItemSetSpell table; it was built without them. Rebuild it with db2tool." % db_path)
    sets = {}
    cur = con.execute('SELECT * FROM "%s"' % t_set)
    cols = [c[0] for c in cur.description]
    for row in cur:
        r = dict(zip(cols, row))
        items = []
        if r.get("ItemID"):  # array column: JSON text, plus generated ItemID_0.. columns
            try:
                items = [int(x) for x in json.loads(r["ItemID"])]
            except (ValueError, TypeError):
                items = []
        if not items:
            per = sorted((int(re.search(r"_(\d+)$", c).group(1)), c) for c in cols if re.fullmatch(r"ItemID_\d+", c))
            items = [int(r[c] or 0) for _, c in per]
        items = list(dict.fromkeys(i for i in items if i))
        name = r.get("Name_lang") or r.get("Name") or ""
        sets[int(r["ID"])] = {"name": name, "items": items, "bonuses": {}}
    rows = []
    cur = con.execute('SELECT * FROM "%s"' % t_spell)
    cols = [c[0] for c in cur.description]
    for row in cur:
        r = dict(zip(cols, row))
        rows.append((int(r["ItemSetID"]), int(r["Threshold"]), int(r["SpellID"])))
    return sets, rows, "%s (%d sets, %d bonus rows)" % (Path(db_path).name, len(sets), len(rows))


def _load_from_csv(cache):
    def newest(prefix):
        def key(p):
            return [int(x) for x in re.findall(r"\d+", p.name[len(prefix):])]
        files = sorted(cache.glob(prefix + "_*.csv"), key=key)
        return files[-1] if files else None

    sets_csv, spells_csv = newest("ItemSet"), newest("ItemSetSpell")
    if not sets_csv or not spells_csv:
        return None
    sets = {}
    for r in csv.DictReader(open(sets_csv, encoding="utf-8")):
        items = []
        for i in range(17):
            iid = int(r["ItemID_%d" % i] or 0)
            if iid and iid not in items:
                items.append(iid)
        sets[int(r["ID"])] = {"name": r["Name_lang"], "items": items, "bonuses": {}}
    rows = [(int(r["ItemSetID"]), int(r["Threshold"]), int(r["SpellID"]))
            for r in csv.DictReader(open(spells_csv, encoding="utf-8"))]
    return sets, rows, "%s + %s" % (sets_csv.name, spells_csv.name)


def load_set_tables(repo, db_path=None):
    if db_path:
        if not Path(db_path).is_file():
            sys.exit("--db file not found: %s" % db_path)
        return _load_from_sqlite(db_path)
    default_db = repo / "tools/database/wowsims.db"
    if default_db.is_file():
        return _load_from_sqlite(default_db)
    cache = repo / "tools/data_watch/.cache"
    if cache.is_dir():
        found = _load_from_csv(cache)
        if found:
            return found
    sys.exit(MISSING_TABLES_HELP)


def generate(repo, out_path, db_path=None):
    repo = require_repo(repo, "spells")
    spells = load_spells(repo / "sim/core/spelldata/spells_auto_gen.go")
    sets, bonus_rows, source = load_set_tables(repo, db_path)

    n_rows = n_scored = n_unscored = n_missing = 0
    for sid, thr_, spell_ in bonus_rows:
        sid, thr, spell = sid, thr_, spell_
        if sid not in sets:
            continue
        n_rows += 1
        if spell not in spells:
            n_missing += 1
            continue
        stats, other, _ = spell_stats(spell, spells, follow_triggers=False)
        entry = sets[sid]["bonuses"].setdefault(thr, {"stats": {}, "other": []})
        for k, v in stats.items():
            entry["stats"][k] = entry["stats"].get(k, 0) + v
        entry["other"] += other
        entry.setdefault("spells", []).append(spell)
        if stats:
            n_scored += 1
        else:
            n_unscored += 1

    out_sets = {sid: s for sid, s in sets.items() if any(b["stats"] for b in s["bonuses"].values())}
    by_item = {}
    for sid in sorted(out_sets):
        for iid in out_sets[sid]["items"]:
            by_item.setdefault(iid, sid)

    lines = [
        "-- setdata.lua -- GENERATED by gen_setdata.py from the WoW: Forever client tables. DO NOT EDIT BY HAND.",
        *attribution_lines(repo),
        "-- Item set piece lists and the flat-stat part of each set bonus (client ItemSet / ItemSetSpell tables, spell",
        "-- effects read from the sim's spell store). Used by calculation.lua to credit set bonuses when scoring a",
        "-- combination.  Per set:  name, items = { itemIDs }, bonuses = { [pieces] = { stats = { TopFit stat key = amount },",
        "-- other = { stat auras TopFit does not score }, spells = { bonus spell IDs } } }",
        "-- (TopFit is the global created in core.lua; this file loads after it.)",
        "TopFit.SetData = {",
    ]
    for sid in sorted(out_sets):
        s = out_sets[sid]
        lines.append("\t[%d] = { name=%s, items={%s}, bonuses={" % (sid, lua_val(s["name"]), ",".join(map(str, s["items"]))))
        for thr in sorted(s["bonuses"]):
            b = s["bonuses"][thr]
            parts = []
            if b["stats"]:
                parts.append("stats={%s}" % ",".join("%s=%s" % (k, lua_val(v)) for k, v in sorted(b["stats"].items())))
            if b["other"]:
                parts.append("other={%s}" % ",".join(lua_val(o) for o in sorted(set(b["other"]))))
            parts.append("spells={%s}" % ",".join(map(str, b["spells"])))
            lines.append("\t\t[%d] = {%s}," % (thr, ", ".join(parts)))
        lines.append("\t}},")
    lines.append("}")
    lines.append("TopFit.SetByItem = {")
    row = []
    for iid in sorted(by_item):
        row.append("[%d]=%d" % (iid, by_item[iid]))
        if len(row) == 8:
            lines.append("\t" + ",".join(row) + ",")
            row = []
    if row:
        lines.append("\t" + ",".join(row) + ",")
    lines.append("}")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    print("source:", source)
    print("sets in client: %d, kept (with scoreable bonuses): %d, mapped items: %d" % (len(sets), len(out_sets), len(by_item)))
    print("bonus rows: %d (scoreable %d, not scoreable %d, spell missing from store %d)" % (n_rows, n_scored, n_unscored, n_missing))
    print("wrote", out_path)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate setdata.lua from the Forever sim clone.")
    add_common_args(parser)
    parser.add_argument("--db", type=Path, help="wowsims.db to read the ItemSet tables from (default: <repo>/tools/database/wowsims.db)")
    args = parser.parse_args(argv)
    generate(args.repo, args.addon / "setdata.lua", args.db)


if __name__ == "__main__":
    main()
