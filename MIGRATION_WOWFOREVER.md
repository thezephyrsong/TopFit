# TopFit → WoW: Forever Migration Checklist

Status: **pre-launch audit**. WoW: Forever has no public client, PTR, or addon API
docs yet, so nothing below has been tested against a live client. This is a
list of every WotLK-3.3.5a-era API call in the codebase, grouped by family,
with the known retail-side replacement and a risk rating for how confident we
are that the replacement is correct. Confirm each item empirically once the
client is available, then delete its row.

Legend: 🟢 low risk (near drop-in) · 🟡 medium risk (signature/behavior change)
· 🔴 high risk (API family may not exist at all / needs redesign)

---

## 1. Container / bag API — 🟡 medium risk

Retail replaced the global bag functions with a `C_Container` namespace
(this happened years before WoW: Forever, so it's near-certain to apply).
The function names moved but argument order and return values are mostly
unchanged, so this is mechanical find-and-replace once wrapped.

| Legacy call | Retail replacement | Occurrences |
|---|---|---|
| `GetContainerItemLink(bag, slot)` | `C_Container.GetContainerItemLink(bag, slot)` | `tooltip.lua:41`, `inventory.lua:37,29,495`, `core.lua:656,118`, `simc_export.lua:418` |
| `GetContainerNumSlots(bag)` | `C_Container.GetContainerNumSlots(bag)` | `inventory.lua:36,28,494`, `core.lua:655,117`, `simc_export.lua:416` |
| `PickupContainerItem(bag, slot)` | `C_Container.PickupContainerItem(bag, slot)` | `core.lua:151` |

**Action:** wrap in `TopFit:GetContainerItemLink(bag, slot)` /
`TopFit:GetContainerNumSlots(bag)` / `TopFit:PickupContainerItem(bag, slot)`
in `inventory.lua`, each trying `C_Container.X` then falling back to global
`X`. Replace all call sites above with the wrapper. One-file change once the
real API is confirmed either way.

---

## 2. Inventory slot API — 🟢 low risk

These are plain global functions on live retail today and have been stable
across expansions; low risk they change for WoW: Forever specifically.

| Legacy call | Notes | Occurrences |
|---|---|---|
| `GetInventoryItemLink("player", slot)` | unchanged on retail | `tooltip.lua:44`, `frame.lua:693`, `inventory.lua:531,45`, `core.lua:98,677,171,132,110`, `simc_export.lua:623,546` |
| `GetInventoryItemTexture("player", i)` | unchanged on retail | `core.lua:23` |
| `GetInventorySlotInfo(slotName)` | unchanged on retail | `core.lua:506` |
| `GetInventoryItemsForSlot(slotID)` | confirm still returns the same set on a 3-tree/level-60 ruleset | `inventory.lua:458` |

**Action:** no wrapper needed unless testing reveals a change; just re-verify
return values once a client exists.

---

## 3. Item data API — 🟡 medium risk

`GetItemInfo` still exists on retail but became **partially asynchronous**:
on an uncached item it can return `nil` for one or more calls until the
server round-trip completes, whereas on 3.3.5a it blocked until data was
available. TopFit calls this in several places expecting synchronous data.

| Call site | Risk detail |
|---|---|
| `procparser.lua:189` | single value read, cheap to guard |
| `tooltip.lua:37` | tooltip-time call, item is usually already cached from the tooltip itself — low practical risk |
| `frame.lua:753,686,460,440` | reads item texture/name for UI icons; a nil mid-render would show a blank icon rather than erroring, but should add an `GetItemInfoInstant` fallback or `ITEM_DATA_LOAD_RESULT` retry |
| `inventory.lua:73` | full 10-value unpack used to build the internal item record — **this is the important one**, since a partial/nil result here would silently corrupt an item's cached stats |
| `calculation.lua:942` | reads class/subclass/equipSlot for scoring — same corruption risk as above |
| `simc_export.lua:627,550,453,420,209` | export-time reads; low frequency, acceptable to just retry-on-nil since export isn't real-time |
| `plugins/virtual_items.lua:182,100` | UI display only |

**Action:** add a single `TopFit:GetItemInfoSafe(item)` wrapper in
`inventory.lua` that calls `GetItemInfo`, and if the first return is `nil`,
calls `C_Item.RequestLoadItemDataByID`/`GetItemInfoInstant` and retries on
the next frame or via `ITEM_DATA_LOAD_RESULT`. Route the `inventory.lua:73`
and `calculation.lua:942` sites through it first — those two build the data
the rest of the scoring pipeline trusts.

---

## 4. Gem / item-stats API — 🟡 medium risk

| Legacy call | Retail replacement | Occurrences |
|---|---|---|
| `GetItemGem(item, i)` | `C_Item.GetItemGem(item, i)` | `inventory.lua:150`, `simc_export.lua:450` |
| `GetItemStats(itemLink)` | still exists as a global on retail, but the **key names in the returned table** have shifted over expansions (e.g. rating-stat keys were renamed at points) | `inventory.lua:95`, referenced in `simc_export.lua:258` comment |

**Action:** wrap `GetItemGem` the same way as the container API (namespace
fallback). For `GetItemStats`, once a client exists, dump the returned table
for a known item and diff its keys against what `inventory.lua` currently
expects — this is the one place a silent key mismatch would cause TopFit to
just treat every item as having zero of some stat, with no error thrown.

---

## 5. Equipment Manager — 🔴 high risk

| Legacy call | Status | Occurrences |
|---|---|---|
| `EquipmentManagerIgnoreSlotForSave(slotID)` | Equipment Manager (the WotLK-era swap-set UI these belong to) was replaced by Equipment Sets / `C_EquipmentSet` well before WoW: Forever. These specific functions may not exist at all on the unified client. | `core.lua:187` |
| `EquipmentManagerClearIgnoredSlotsForSave()` | same | `core.lua:183` |

**Action:** this is the one item where "port" likely means "reimplement,"
not "rename." Find what `core.lua:180-190` is actually trying to accomplish
(almost certainly: stop the game's own gear-swap system from fighting
TopFit's equip actions) and re-derive the equivalent using `C_EquipmentSet`
once we can see whether it's even still relevant on WoW: Forever's UI.

---

## 6. Talent API — 🔴 high risk (open question, not yet a known answer)

You've confirmed WoW: Forever keeps the classic 3-tree talent layout, so
conceptually `calculation.lua`'s and `simc_export.lua`'s talent-reading code
doesn't need a redesign — but that doesn't guarantee the **API surface**
survives. Retail deprecated `GetTalentInfo` / `GetTalentTabInfo` /
`GetNumTalentTabs` entirely years ago in favor of `C_ClassTalents` /
`C_Traits`, as part of the same client-unification work that's presumably
bringing WoW: Forever onto the retail codebase. A classic-style talent UI
running on that codebase could either:

- keep the old global functions alive as a compatibility shim for a
  classic-shaped tree, or
- expose the same 3-tree data through `C_ClassTalents`/`C_Traits` with a
  different call shape entirely.

We can't resolve this without a live client. Real call sites to migrate,
once we know which world we're in:

| Call site | Purpose |
|---|---|
| `calculation.lua:124,121` | guards scoring until talent data is loaded this session |
| `calculation.lua:84,81` | hardcoded Titan's Grip / Dual Wield tab+index checks |
| `calculation.lua:133` | generic `(tab, index) → rank` lookup used by the scoring pipeline |
| `simc_export.lua:48,64,69` | `GetNumTalentTabs()` calls |
| `simc_export.lua:55,77,92` | `GetTalentInfo(tab, i)` rank reads |
| `simc_export.lua:72` | `GetTalentTabInfo(tab)` name read |

`talentbonuses.lua` itself only *references* `GetTalentInfo` in comments —
it's a static per-class rating-bonus table, not live API calls, so it
doesn't need touching here. It will, however, need its actual **talent
content** redone once WoW: Forever's changed talents are known, which is a
data problem, not a porting problem — worth tracking separately from this
checklist.

**Action:** don't build against either API shape yet. When a client is
available, the very first test should be `print(GetNumTalentTabs())` vs.
`C_ClassTalents.GetActiveConfigID()` to settle which family is live, then
this whole section collapses to either "no change" or "full rewrite of six
call sites" — there's no useful middle-ground work to do before that's known.

---

## 7. Spell info — 🟢 low risk

| Legacy call | Notes | Occurrences |
|---|---|---|
| `GetSpellInfo(glyphSpellID)` | Retail's `GetSpellInfo` now returns a single table instead of positional values in some contexts — check the exact call shape at `simc_export.lua:376`, but the function itself is present | `simc_export.lua:376` |

---

## 8. Itemization model — flat/percent "Equip:" stats, not GetItemStats — 🔴 high risk, confirmed real bug

The Items & Gear panel screenshot Dan shared uses real Classic items (Lionheart
Helm, Hide of the Wild, Edgemaster's Handguards) whose bonuses are phrased as
percentage or flat on-equip spell text, not WotLK-style itemMod ratings. This
is the pre-rating itemization model, and it is **not exposed via
`GetItemStats()`** — those functions only return structured stat mods (`+N
Strength`, `+N Hit Rating`), and these percentage/flat bonuses were
historically implemented as on-equip spell auras instead, invisible to that
API going all the way back to Vanilla/TBC (confirmed by Pawn's own changelog,
which flags this exact category of effect as something it has never been
able to assign a value to). If WoW: Forever's itemization matches this model
— and Season of Discovery, Blizzard's prior Classic+ experiment on the same
unified client, confirms it does — `inventory.lua:95`'s `GetItemStats(itemLink)`
call will silently return nothing for these bonuses.

**Confirmed real tooltip templates** (pulled from live Season of Discovery
items, which share this itemization model and very likely share exact
wording with WoW: Forever):

Percentage-based (needs tooltip parsing, not GetItemStats):
- `"Equip: Improves your chance to hit with all spells and attacks by N%."` — Craft of the Shadows, Duskwraith Chestguard, Soulforge Chestguards
- `"Equip: Improves your chance to get a critical strike with all spells and attacks by N%."` — Lucky Doubloon
- `"Equip: Improves your chance to get a critical strike with spells by N%."` — datamined Atiesh variant; confirms melee/ranged/spell crit can appear as **separate** lines instead of always combined
- `"Equip: Reduces the chance for your attacks to be dodged or parried by N%."` — High Commander's Guard, Duskwraith Chestguard. Note the wording differs slightly from the screenshot's "Reduces chance to be dodged or parried by 1.0%" (missing "for your attacks") — the parser needs to tolerate both.

Flat integer (simpler — no percent math, just `Increased <Name> +N`):
- `"Equip: Increased Defense +N."`
- `"Equip: Increased Swords +N."` / Daggers / Axes / Maces / etc. (per weapon-skill type — matches Edgemaster's Handguards in the screenshot exactly)

Dual-stat single line (one Equip: line encoding two different pseudo-stats):
- `"Increases healing done by up to X and damage done by up to Y for all magical spells and effects."` — confirmed as a standard recurring template, not a one-off, via the datamined Atiesh text as well as Hide of the Wild.

**The concrete bug this exposes in `procparser.lua`:** `LooksLikeTriggeredEffect`
(line 209-214) classifies any `Equip:` line containing the word "chance" as a
triggered proc. Every percentage-based passive stat above uses the word
"chance" in ordinary English phrasing ("your **chance** to hit," "the
**chance** ... to be dodged or parried") despite being permanent, always-on
stats with no duration or cooldown. Right now these get routed into the proc
path, fail to find a duration/cooldown (correctly, since there isn't one),
and per the module's own honest-limits design get stored as
`hasUnscoredProc = true` while contributing **zero** to `totalBonus` — so a
Lionheart Helm would silently score as having no hit bonus at all, with
nothing surfaced to say so.

**Recommended fix (not yet implemented, needs your go-ahead):**
1. Add explicit pattern checks for the confirmed permanent-stat templates
   above, run *before* the generic `find("chance")` fallback in
   `LooksLikeTriggeredEffect` — if a line matches one of these known passive
   patterns, short-circuit to "not a triggered effect" regardless of the word
   "chance" appearing in it.
2. Extend `GetStatNameTable`/`ParseStatAndAmount` (or add a parallel path)
   to recognize these phrase-based stats and map them to TopFit's internal
   stat keys (needs new keys for "hit chance," "crit chance," "dodge/parry
   reduction," "weapon skill: <type>," since none of these have a
   corresponding `ITEM_MOD_*` global to borrow a display name from).
3. Handle the dual-stat line as two separate `(statKey, amount)` results
   instead of one, since `ParseStatAndAmount` currently assumes one stat per
   line.
4. Handle flat `Increased <Name> +N` separately from the percent patterns —
   simpler parsing (no `%` sign, no "by" phrasing), but same "not in
   GetItemStats" problem.

This is real parsing work, not just a WoW: Forever-specific flag — it should
hold up even if some detail of Forever's wording differs from SoD's, since
the underlying mechanism (on-equip spell text outside GetItemStats) is the
same category of problem either way.

---

## Summary by effort

1. **Do now, safely:** wrapper functions for container API, `GetItemGem`,
   and a `GetItemInfoSafe` retry shim — all mechanical, all reversible, none
   depend on unknowns about WoW: Forever specifically.
2. **Do now, needs care:** re-point `inventory.lua:73` and
   `calculation.lua:942` through the safe item-info wrapper first, since
   those two feed the whole scoring pipeline.
3. **Blocked on client access:** Equipment Manager reimplementation, talent
   API family confirmation, `GetItemStats` key-name diffing, `GetSpellInfo`
   return-shape check.
4. **Do now, real bug fix (not blocked on a client):** the
   `LooksLikeTriggeredEffect` misclassification in section 8 — the confirmed
   tooltip templates are real, current WoW text, so this can be built and
   tested against live Season of Discovery items today, ahead of WoW: Forever
   even launching.
