"""
fvspells.py -- shared helpers for gen_procdata.py and gen_setdata.py.

Parses the WoW: Forever sim's generated spell store (sim/core/spelldata/spells_auto_gen.go) and turns a spell's
wearer-side stat auras into TopFit stat keys.
"""
import os
import re
import sys
from pathlib import Path

# tools/ lives inside the addon folder:  <Addons>/TopFit/tools/*.py
# The Forever sim clone is expected next to it:  <Addons>/Forever   (override with --repo or FOREVER_REPO)
ADDON_DIR = Path(__file__).resolve().parent.parent
DEFAULT_REPO = Path(os.environ.get("FOREVER_REPO") or ADDON_DIR.parent / "Forever")

REPO_FILES = {
    "db": "assets/database/db.json",
    "spells": "sim/core/spelldata/spells_auto_gen.go",
    "cache": "tools/data_watch/.cache",
}


def add_common_args(parser):
    parser.add_argument("--repo", type=Path, default=DEFAULT_REPO,
                        help="Forever sim clone (default: %(default)s; or set FOREVER_REPO)")
    parser.add_argument("--addon", type=Path, default=ADDON_DIR,
                        help="TopFit addon folder the .lua files are written to (default: %(default)s)")


def require_repo(repo, *keys):
    """Exit with a readable message if the Forever clone (or one of the files we read from it) is missing."""
    repo = Path(repo)
    if not repo.is_dir():
        sys.exit("Forever sim clone not found: %s\n  clone it next to the addon, or pass --repo <path> / set FOREVER_REPO" % repo)
    for key in keys:
        p = repo / REPO_FILES[key]
        if not p.exists():
            sys.exit("%s is missing from the clone (%s). Is it up to date?  (git -C \"%s\" pull)" % (REPO_FILES[key], p, repo))
    return repo

# ----------------------------------------------------------------------------- spell store
def load_spells(go_path):
    text = Path(go_path).read_text(encoding="utf-8")
    spells = {}
    for blk in re.split(r"\n(?=\t\{ID: \d+,)", text):
        m = re.match(r"\t\{ID: (\d+),", blk)
        if not m:
            continue
        sid = int(m.group(1))
        head = blk.split("\n", 1)[0]

        def num(field, cast=int):
            mm = re.search(r"\b%s: (-?[\d.]+)" % field, head)
            return cast(mm.group(1)) if mm else None

        flags = re.search(r"ProcFlags: \[2\]uint32\{([^}]*)\}", head)
        flag0 = flag1 = 0
        if flags:
            for part in flags.group(1).split(","):
                k, _, v = part.partition(":")
                if k.strip() == "0":
                    flag0 = int(v.strip(), 16)
                elif k.strip() == "1":
                    flag1 = int(v.strip(), 16)
        name = re.search(r'Name: "([^"]*)"', head)
        effects = []
        for line in blk.split("\n")[1:]:
            if not line.startswith("\t\t\t{ID:"):
                continue
            aura = re.search(r"Aura: dbcenums\.(\w+)", line)
            tgt = re.search(r"Target: \[2\]dbcenums\.ImplicitTarget\{(\d+)", line)
            effects.append({
                "type": (re.search(r"Type: dbcenums\.(\w+)", line) or [None, None])[1],
                "aura": aura.group(1) if aura else None,
                "base": int(re.search(r"BasePoints: (-?\d+)", line).group(1)) if "BasePoints:" in line else 0,
                "misc": int(re.search(r"\bMisc: (-?\d+)", line).group(1)) if re.search(r"\bMisc: ", line) else 0,
                "trigger": int(re.search(r"TriggerID: (\d+)", line).group(1)) if "TriggerID:" in line else None,
                # first implicit target; 1 = the caster/wearer. Anything else (enemy debuffs, party auras) is not
                # a stat the wearer gets, so it must never be scored.
                "target": int(tgt.group(1)) if tgt else 0,
            })
        spells[sid] = {
            "name": name.group(1) if name else "",
            "chance": num("ProcChance"),
            "flags": flag0,
            "flags2": flag1,
            "icd": num("ICDMs"),
            "duration": num("DurationMs"),
            "rppm": num("RPPM", float),
            "effects": effects,
        }
    return spells

# ----------------------------------------------------------------------------- stat mapping
# sim Stat enum index (proto/common.proto) -> TopFit stat key, for flat stats TopFit scores directly
SIM_STAT_TO_TF = {
    0: "ITEM_MOD_STRENGTH_SHORT", 1: "ITEM_MOD_AGILITY_SHORT", 2: "ITEM_MOD_STAMINA_SHORT",
    3: "ITEM_MOD_INTELLECT_SHORT", 16: "ITEM_MOD_SPIRIT_SHORT",
    4: "TOPFIT_SPELL_HEALING_FLAT", 5: "TOPFIT_SPELL_DAMAGE_FLAT",
    6: "TOPFIT_ARCANE_DAMAGE_FLAT", 7: "TOPFIT_FIRE_DAMAGE_FLAT", 8: "TOPFIT_FROST_DAMAGE_FLAT",
    9: "TOPFIT_HOLY_DAMAGE_FLAT", 10: "TOPFIT_NATURE_DAMAGE_FLAT", 11: "TOPFIT_SHADOW_DAMAGE_FLAT",
    17: "ITEM_MOD_ATTACK_POWER_SHORT", 18: "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    19: "ITEM_MOD_FERAL_ATTACK_POWER_SHORT",
    27: "ITEM_MOD_BLOCK_VALUE_SHORT", 30: "RESISTANCE0_NAME",
    34: "ITEM_MOD_MANA_REGENERATION_SHORT",
    35: "RESISTANCE6_NAME", 36: "RESISTANCE2_NAME", 37: "RESISTANCE4_NAME",
    38: "RESISTANCE3_NAME", 39: "RESISTANCE5_NAME",
}
SIM_STAT_NAMES = {
    12: "spellHitRating", 13: "spellCritRating", 14: "spellHasteRating", 15: "spellPiercing",
    20: "meleeHitRating", 21: "meleeCritRating", 22: "meleeHasteRating", 23: "armorPenetration",
    24: "expertiseRating", 25: "defenseRating", 26: "blockRating", 28: "dodgeRating", 29: "parryRating",
    31: "bonusArmor", 32: "health", 33: "mana", 40: "physicalDamage",
}
SCHOOL_BIT_TO_SIM_STAT = {2: 9, 4: 7, 8: 10, 16: 8, 32: 11, 64: 6}  # holy, fire, nature, frost, shadow, arcane
SCHOOL_BIT_TO_RESIST_KEY = {2: "RESISTANCE1_NAME", 4: "RESISTANCE2_NAME", 8: "RESISTANCE3_NAME",
                            16: "RESISTANCE4_NAME", 32: "RESISTANCE5_NAME", 64: "RESISTANCE6_NAME"}
PRIMARY_MISC_TO_SIM_STAT = {0: 0, 1: 1, 2: 2, 3: 3, 4: 16}


def _add(d, k, v):
    d[k] = d.get(k, 0) + v


def effect_stats(eff):
    """One wearer-side aura effect -> ({TopFit key: amount}, [other descriptions]).
    Hit/crit are handled by spell_stats (they depend on which effects sit together)."""
    a, v, misc = eff["aura"], eff["base"], eff["misc"]
    if eff["target"] != 1 or not a:
        return {}, []
    if a == "A_MOD_STAT":
        if misc == -1:
            return {SIM_STAT_TO_TF[s]: v for s in (0, 1, 2, 3, 16)}, []
        if misc in PRIMARY_MISC_TO_SIM_STAT:
            return {SIM_STAT_TO_TF[PRIMARY_MISC_TO_SIM_STAT[misc]]: v}, []
    elif a == "A_MOD_ATTACK_POWER":
        return {SIM_STAT_TO_TF[17]: v}, []
    elif a == "A_MOD_RANGED_ATTACK_POWER":
        return {SIM_STAT_TO_TF[18]: v}, []
    elif a in ("A_MOD_RESISTANCE", "A_MOD_BASE_RESISTANCE"):
        out = {}
        if misc & 1:
            out["RESISTANCE0_NAME"] = v
        for bit, key in SCHOOL_BIT_TO_RESIST_KEY.items():
            if misc & bit:
                out[key] = v
        if out:
            return out, []
        return {}, ["%s school=%d %d" % (a, misc, v)]
    elif a == "A_MOD_DAMAGE_DONE":
        if misc & 126 == 126:
            return {SIM_STAT_TO_TF[5]: v}, []
        schools = [b for b in SCHOOL_BIT_TO_SIM_STAT if misc & b]
        if len(schools) == 1:
            return {SIM_STAT_TO_TF[SCHOOL_BIT_TO_SIM_STAT[schools[0]]]: v}, []
        return {}, ["%s schools=%d %d" % (a, misc, v)]
    elif a == "A_MOD_HEALING_DONE":
        return {SIM_STAT_TO_TF[4]: v}, []
    elif a == "A_MOD_BLOCK_VALUE_FLAT":
        return {SIM_STAT_TO_TF[27]: v}, []
    elif a == "A_MOD_POWER_REGEN" and misc == 0:
        return {SIM_STAT_TO_TF[34]: v}, []          # mana per 5 sec
    elif a == "A_MOD_SKILL" and misc == 95:
        return {"TOPFIT_DEFENSE_FLAT": v}, []        # defense skill
    elif a.startswith("A_MOD_") and "DECREASE_SPEED" not in a:
        return {}, ["%s misc=%d %d" % (a, misc, v)]
    return {}, []


def spell_stats(spell_id, spells, follow_triggers=True, depth=0, seen=None):
    """Wearer-side stats a spell grants -> ({TopFit key: amount}, [other], duration_ms).
    follow_triggers: also read spells reached through A_PROC_TRIGGER_SPELL / A_PERIODIC_TRIGGER_SPELL / A_DUMMY
    (needed for item procs; set bonuses pass False because a triggered spell there is a proc, not a flat bonus)."""
    seen = seen or set()
    if spell_id in seen or spell_id not in spells or depth > 2:
        return {}, [], None
    seen.add(spell_id)
    sp = spells[spell_id]
    stats, other = {}, []
    hit_phys = hit_spell = crit_spell = crit_phys = None
    for eff in sp["effects"]:
        a = eff["aura"]
        if a in ("A_PROC_TRIGGER_SPELL", "A_PERIODIC_TRIGGER_SPELL", "A_DUMMY") and eff["trigger"]:
            if follow_triggers:
                s2, o2, _ = spell_stats(eff["trigger"], spells, follow_triggers, depth + 1, seen)
                for k, v in s2.items():
                    _add(stats, k, v)
                other += o2
            continue
        if eff["target"] == 1:
            if a == "A_MOD_HIT_CHANCE":
                hit_phys = (hit_phys or 0) + eff["base"]; continue
            if a == "A_MOD_SPELL_HIT_CHANCE":
                hit_spell = (hit_spell or 0) + eff["base"]; continue
            if a == "A_MOD_SPELL_CRIT_CHANCE":
                crit_spell = (crit_spell or 0) + eff["base"]; continue
            if a in ("A_MOD_WEAPON_CRIT_PERCENT", "A_MOD_CRIT_PCT"):
                crit_phys = (crit_phys or 0) + eff["base"]; continue
        s, o = effect_stats(eff)
        for k, v in s.items():
            _add(stats, k, v)
        other += o
    # "+1% to hit" is two effects (melee + spell); one without the other is not TopFit's all-hit stat
    if hit_phys and hit_spell and hit_phys == hit_spell:
        _add(stats, "TOPFIT_HIT_CHANCE_ALL", hit_phys)
    else:
        if hit_phys: other.append("A_MOD_HIT_CHANCE (physical only) %d" % hit_phys)
        if hit_spell:
            _add(stats, "TOPFIT_HIT_CHANCE_SPELL", hit_spell)
    if crit_spell and crit_phys and crit_spell == crit_phys:
        _add(stats, "TOPFIT_CRIT_CHANCE_ALL", crit_spell)
    else:
        if crit_phys: _add(stats, "TOPFIT_CRIT_CHANCE_PHYSICAL", crit_phys)
        if crit_spell: _add(stats, "TOPFIT_CRIT_CHANCE_SPELL", crit_spell)
    # TopFit counts "+AP" once at (AP weight + RAP weight) -- see GetEffectiveWeights -- so a spell granting the
    # same amount of both is stored as AP only, exactly as enchant.lua collapses enchant records.
    ap, rap = "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT"
    if ap in stats and rap in stats and stats[ap] == stats[rap]:
        del stats[rap]
    stats = {k: v for k, v in stats.items() if v}
    return stats, other, sp["duration"]


def trigger_label(flags):
    """coarse, human-readable trigger from the client's proc flags (see dbcenums/proc_flags.go)."""
    labels = []
    for bit, text in ((0x4, "melee swing"), (0x10, "melee ability"), (0x40, "ranged attack"),
                      (0x100, "ranged ability"), (0x1000, "harmful ability"), (0x10000, "harmful spell"),
                      (0x4000 | 0x400, "helpful spell"), (0x40000, "periodic damage"),
                      (0x8 | 0x20, "hit by melee"), (0x100000, "took damage"), (0x20000000, "cast ended"),
                      (0x2, "kill")):
        if flags & bit:
            labels.append(text)
    return "/".join(labels)


# ----------------------------------------------------------------------------- lua output helpers
def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return ("%.4f" % v).rstrip("0").rstrip(".")
    return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'
