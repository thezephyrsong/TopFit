#!/usr/bin/env python3
"""
gen_presets.py -- refreshes the sim-sourced stat-weight presets in TopFit's presets.lua from the WoW: Forever sim.

usage (from the TopFit folder):  python tools/gen_presets.py [--repo ../Forever] [--addon .] [--level 60] [--dry-run]
  (tools/update_data.py runs this together with gen_procdata.py and gen_setdata.py.)

Reads, from the sim clone
  ui/specs/<class>/<spec>/presets.ts                       the sim's own EP-weight presets (makePresetEpWeights)
  assets/db_inputs/basestats-forever/CombatRatings.txt     rating points per 1% (or per skill point) at --level
and rewrites ONLY the block between the BEGIN/END GENERATED SIM PRESETS markers in <addon>/presets.lua.
Everything else in presets.lua -- the hand-pasted per-spec sets and the GetPresets code -- is left alone, and a
generated preset never replaces a hand-made one: they appear in the preset menu as "Sim: <spec>: <preset>".

How a sim weight becomes a TopFit weight (the same rules presets.lua's header documents for the hand-made sets):
  * Strength/Agility/Stamina/Intellect/Spirit, Attack Power, Ranged Attack Power, MP5, Spell Damage, school
    damage, Healing Power, Spell Piercing, Block Value -> the matching TopFit stat, weight unchanged.
  * The sim weighs RATING points; TopFit works in percent, so a rating weight is multiplied by that rating's
    points-per-percent from CombatRatings.txt: hit, crit, haste, expertise, dodge, parry, block. Defense rating
    is 1 rating per skill point and TopFit counts flat defense skill, so it keeps its weight.
  * Hit / Crit -> TOPFIT_HIT_CHANCE_ALL / TOPFIT_CRIT_CHANCE_ALL; casters also get the SPELL keys, because a pure
    caster's gear says "improves your chance to hit/crit" on the generic key and on the spell key.
  * Haste -> TOPFIT_HASTE_PERCENT.  Expertise -> TOPFIT_DODGE_PARRY_REDUCTION.
  * Armor -> RESISTANCE0_NAME (0.001 tie-break when the preset has none).  Armor Penetration is dropped: no item
    tooltip pattern feeds TopFit's armor-penetration key.
  * Weapon DPS is not a sim stat: 14 attack power = 1 weapon DPS, so melee specs get 14 x Attack Power weight on
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT and Hunters get 14 x Ranged Attack Power on TOPFIT_RANGED_DPS. (The sim
    normalises EP to Attack Power = 1, so a missing Attack Power weight is taken as 1 and the preset says so in
    `notes`.) Casters keep a 0.001 wand tie-break.
  * No caps (the sim's hit/expertise weights are marginal values below the cap), and weightsAssumeFullTalents is
    left off: these are hand-curated presets, not output from a full-talent run.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

from fvspells import add_common_args, require_repo

BEGIN = "-- BEGIN GENERATED SIM PRESETS"
END = "-- END GENERATED SIM PRESETS"

AP_PER_WEAPON_DPS = 14

CLASS_TOKEN = {"druid": "DRUID", "hunter": "HUNTER", "mage": "MAGE", "paladin": "PALADIN", "priest": "PRIEST",
               "rogue": "ROGUE", "shaman": "SHAMAN", "warlock": "WARLOCK", "warrior": "WARRIOR"}

SPEC_LABEL = {
    "druid/balance": "Balance", "druid/feralbear": "Feral Bear", "druid/feralcat": "Feral Cat",
    "druid/restoration": "Restoration Druid", "hunter/dps": "Hunter", "mage/dps": "Mage",
    "paladin/holy": "Holy Paladin", "paladin/protection": "Protection Paladin",
    "paladin/retribution": "Retribution", "priest/dps": "Priest DPS", "priest/healer": "Priest Healer",
    "rogue/dps": "Rogue", "shaman/elemental": "Elemental", "shaman/enhancement": "Enhancement",
    "shaman/restoration": "Restoration Shaman", "warlock/dps": "Warlock", "warrior/dps": "Warrior",
    "warrior/protection": "Protection Warrior",
}

# casters put hit/crit on the SPELL keys as well; healers/tanks etc. are decided by this list, not guessed
CASTER_SPECS = {"druid/balance", "druid/restoration", "mage/dps", "paladin/holy", "priest/dps", "priest/healer",
                "shaman/elemental", "shaman/restoration", "warlock/dps"}
RANGED_SPECS = {"hunter/dps"}

# sim stat (Stat.Stat<Name>) -> TopFit key, weight unchanged
DIRECT = {
    "Strength": "ITEM_MOD_STRENGTH_SHORT", "Agility": "ITEM_MOD_AGILITY_SHORT",
    "Stamina": "ITEM_MOD_STAMINA_SHORT", "Intellect": "ITEM_MOD_INTELLECT_SHORT",
    "Spirit": "ITEM_MOD_SPIRIT_SHORT", "AttackPower": "ITEM_MOD_ATTACK_POWER_SHORT",
    "RangedAttackPower": "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", "MP5": "ITEM_MOD_MANA_REGENERATION_SHORT",
    "SpellDamage": "TOPFIT_SPELL_DAMAGE_FLAT", "HealingPower": "TOPFIT_SPELL_HEALING_FLAT",
    "ArcaneDamage": "TOPFIT_ARCANE_DAMAGE_FLAT", "FireDamage": "TOPFIT_FIRE_DAMAGE_FLAT",
    "FrostDamage": "TOPFIT_FROST_DAMAGE_FLAT", "HolyDamage": "TOPFIT_HOLY_DAMAGE_FLAT",
    "NatureDamage": "TOPFIT_NATURE_DAMAGE_FLAT", "ShadowDamage": "TOPFIT_SHADOW_DAMAGE_FLAT",
    "SpellPiercing": "ITEM_MOD_SPELL_PENETRATION_SHORT", "BlockValue": "ITEM_MOD_BLOCK_VALUE_SHORT",
    "Armor": "RESISTANCE0_NAME",
}
# sim rating stat -> (CombatRatings.txt column, TopFit key(s)); weight is multiplied by the column's rate
RATED = {
    "HitRating": ("Hit - Melee", ["TOPFIT_HIT_CHANCE_ALL"]),
    "CritRating": ("Crit - Melee", ["TOPFIT_CRIT_CHANCE_ALL"]),
    "HasteRating": ("Haste - Melee", ["TOPFIT_HASTE_PERCENT"]),
    "ExpertiseRating": ("Expertise", ["TOPFIT_DODGE_PARRY_REDUCTION"]),
    "DodgeRating": ("Dodge", ["TOPFIT_DODGE_CHANCE_ALL"]),
    "ParryRating": ("Parry", ["TOPFIT_PARRY_CHANCE_ALL"]),
    "BlockRating": ("Block", ["TOPFIT_BLOCK_CHANCE_ALL"]),
    "DefenseRating": ("Defense Skill", ["TOPFIT_DEFENSE_FLAT"]),
}
SPELL_ALSO = {"TOPFIT_HIT_CHANCE_ALL": "TOPFIT_HIT_CHANCE_SPELL", "TOPFIT_CRIT_CHANCE_ALL": "TOPFIT_CRIT_CHANCE_SPELL"}
IGNORED = {"ArmorPenetration", "BonusArmor", "ArmorNoMods", "PhysicalDamage"}


def load_rates(repo, level):
    path = repo / "assets/db_inputs/basestats-forever/CombatRatings.txt"
    if not path.is_file():
        sys.exit("%s is missing from the clone (rating conversions); is it up to date?" % path)
    rows = [l.rstrip("\r\n").split("\t") for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    head = [h.strip() for h in rows[0]]
    for r in rows[1:]:
        if r[0].strip() == str(level):
            vals = {head[i]: float(r[i]) for i in range(1, min(len(head), len(r))) if r[i].strip()}
            return vals
    sys.exit("level %s not found in %s" % (level, path.name))


def parse_presets(repo):
    """-> [(spec 'rogue/dps', preset name, {StatName: weight})] from every ui/specs/*/*/presets.ts"""
    found = []
    for f in sorted((repo / "ui/specs").glob("*/*/presets.ts")):
        spec = "%s/%s" % (f.parent.parent.name, f.parent.name)
        text = f.read_text(encoding="utf-8")
        for m in re.finditer(r"makePresetEpWeights\(\s*(['\"])(.+?)\1\s*,\s*Stats\.fromMap\(\s*\{(.*?)\}", text, re.S):
            weights = {k: float(v) for k, v in re.findall(r"\[(?:Pseudo)?Stat\.(?:Pseudo)?Stat(\w+)\]\s*:\s*(-?[\d.]+)", m.group(3))}
            found.append((spec, m.group(2), weights))
    return found


def convert(spec, weights, rates):
    out, notes, unknown = {}, [], []
    caster = spec in CASTER_SPECS

    def add(key, value):
        out[key] = round(out.get(key, 0) + value, 4)

    for stat, w in weights.items():
        if stat in IGNORED:
            continue
        if stat in DIRECT:
            add(DIRECT[stat], w)
        elif stat in RATED:
            col, keys = RATED[stat]
            rate = rates.get(col)
            if not rate:
                unknown.append("%s (no '%s' rate)" % (stat, col))
                continue
            for k in keys:
                add(k, w * rate)
                if caster and k in SPELL_ALSO:
                    add(SPELL_ALSO[k], w * rate)
        else:
            unknown.append(stat)

    # weapon DPS: 14 attack power = 1 DPS
    if spec in RANGED_SPECS:
        ap = weights.get("RangedAttackPower")
        if ap is None:
            ap, _ = 1.0, notes.append("weapon DPS assumes a Ranged Attack Power weight of 1 (not in the sim preset)")
        add("TOPFIT_RANGED_DPS", AP_PER_WEAPON_DPS * ap)
    elif not caster and ("AttackPower" in weights or "Strength" in weights or "Agility" in weights):
        ap = weights.get("AttackPower")
        if ap is None:
            ap, _ = 1.0, notes.append("weapon DPS assumes an Attack Power weight of 1 (not in the sim preset)")
        add("ITEM_MOD_DAMAGE_PER_SECOND_SHORT", AP_PER_WEAPON_DPS * ap)
    else:
        add("ITEM_MOD_DAMAGE_PER_SECOND_SHORT", 0.001)       # wand tie-break
    out.setdefault("RESISTANCE0_NAME", 0.001)                 # armor tie-break
    return out, notes, unknown


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(v):
    return ("%.4f" % v).rstrip("0").rstrip(".") if v != int(v) else str(int(v))


def git_sha(repo):
    try:
        return subprocess.check_output(["git", "-C", str(repo), "rev-parse", "--short", "HEAD"],
                                       stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return None


def build_block(repo, level):
    rates = load_rates(repo, level)
    presets = parse_presets(repo)
    if not presets:
        sys.exit("no makePresetEpWeights(...) presets found under %s" % (repo / "ui/specs"))
    by_class, warnings = {}, []
    for spec, name, weights in presets:
        cls = CLASS_TOKEN.get(spec.split("/")[0])
        if not cls or not weights:
            warnings.append("skipped %s: %s (%s)" % (spec, name, "unknown class" if not cls else "no weights parsed"))
            continue
        tf, notes, unknown = convert(spec, weights, rates)
        if unknown:
            warnings.append("%s: %s -> not converted: %s" % (spec, name, ", ".join(unknown)))
        by_class.setdefault(cls, []).append((spec, name, tf, notes))

    used = ["%s %s" % (lbl, num(rates[col])) for lbl, col in
            (("hit", "Hit - Melee"), ("crit", "Crit - Melee"), ("haste", "Haste - Melee"), ("expertise", "Expertise"),
             ("dodge", "Dodge"), ("parry", "Parry"), ("block", "Block"), ("defense", "Defense Skill")) if col in rates]
    sha = git_sha(repo)
    lines = [
        "%s -- written by tools/gen_presets.py; edit the script, not this block" % BEGIN,
        "-- Source: the Forever sim's ui/specs/*/*/presets.ts EP presets%s." % (" (clone at %s)" % sha if sha else ""),
        "-- Rating points per 1%% at level %s (CombatRatings.txt): %s." % (level, ", ".join(used)),
        "TopFit.simPresets = {",
    ]
    count = 0
    for cls in sorted(by_class):
        lines.append("\t[%s] = {" % lua_str(cls))
        for spec, name, tf, notes in sorted(by_class[cls], key=lambda x: (x[0], x[1])):
            count += 1
            title = "Sim: %s: %s" % (SPEC_LABEL.get(spec, spec), name)
            lines.append("\t\t{")
            lines.append("\t\t\tname = %s," % lua_str(title))
            lines.append("\t\t\tsimSpec = %s," % lua_str(spec))
            if notes:
                lines.append("\t\t\tnotes = %s," % lua_str("; ".join(notes)))
            lines.append("\t\t\tweights = {")
            for k in sorted(tf):
                lines.append("\t\t\t\t[%s] = %s," % (lua_str(k), num(tf[k])))
            lines.append("\t\t\t},")
            lines.append("\t\t\tcaps = {},")
            lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    lines.append(END)
    return "\n".join(lines), count, warnings


def generate(repo, presets_path, level=60, dry_run=False):
    repo = require_repo(repo)
    block, count, warnings = build_block(repo, level)
    for w in warnings:
        print("warning:", w)
    presets_path = Path(presets_path)
    raw = presets_path.read_bytes().decode("utf-8")
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")
    b, e = text.find(BEGIN), text.find(END)
    if b < 0 or e < 0 or e < b:
        sys.exit("%s has no '%s' ... '%s' block to update. Use the presets.lua that ships with these tools, or "
                 "add the block above `function TopFit:GetPresets()`." % (presets_path, BEGIN, END))
    e_end = e + len(END)
    new_text = text[:b] + block + text[e_end:]
    changed = new_text != text
    print("%d sim presets (%s)" % (count, "changed" if changed else "unchanged"))
    if dry_run:
        print("dry run: %s not written" % presets_path.name)
        return
    if changed:
        presets_path.write_bytes((new_text.replace("\n", "\r\n") if crlf else new_text).encode("utf-8"))
    print("wrote", presets_path)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Refresh the sim-sourced presets in presets.lua from the Forever sim clone.")
    add_common_args(parser)
    parser.add_argument("--level", type=int, default=60, help="level whose rating conversions to use (default %(default)s)")
    parser.add_argument("--dry-run", action="store_true", help="parse and convert, but don't write presets.lua")
    args = parser.parse_args(argv)
    generate(args.repo, args.addon / "presets.lua", args.level, args.dry_run)


if __name__ == "__main__":
    main()
