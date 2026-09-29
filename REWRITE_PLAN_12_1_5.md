# TopFit Rewrite Plan — WoW: Forever / Client 12.1.5

Supersedes `MIGRATION_WOWFOREVER.md`. That doc was written around a
wrapper/fallback strategy (try modern API, fall back to legacy global). This
plan drops that entirely: every call site is rewritten straight to the
12.1.5 API surface, no `X or LegacyX` fallback pattern anywhere in the
codebase. If WoW: Forever's client ever lacks a function this assumes,
that's a bug to fix when found, not a case to defensively code around now.

Beta window: **17 September – 21 October 2026.** That's tomorrow. Sections
below are split into what can be built and tested today against live
retail 12.1.5 (already shipped, PTR for 12.1.5 itself heading to ~Oct 6),
versus what is genuinely blocked on a Forever client existing.

---

## Guiding rule

No compatibility layer, no `local F = C_Container or _G`, no version
detection. Every function call in the codebase should be the one that's
correct for 12.1.5 and nothing else. This is a clean break, not a shim.

---

## 1. Build now, verify against live retail 12.1.5 — no Forever needed

These API families exist on live retail today. There is no reason to wait
for Forever's beta to write and test this code; 12.1.5 already ships them.

### Container / bag API → `C_Container`
Rewrite every call site directly, no fallback:

| Old (remove entirely) | New (only version) |
|---|---|
| `GetContainerItemLink(bag, slot)` | `C_Container.GetContainerItemLink(bag, slot)` |
| `GetContainerNumSlots(bag)` | `C_Container.GetContainerNumSlots(bag)` |
| `PickupContainerItem(bag, slot)` | `C_Container.PickupContainerItem(bag, slot)` |

Call sites: `tooltip.lua:41`, `inventory.lua:37,29,495,36,28,494`,
`core.lua:656,118,655,117,151`, `simc_export.lua:418,416`. Just rename in
place — no wrapper function needed once there's no fallback path to hide
behind.

### Item data → `GetItemInfo` (kept) + async handling
`GetItemInfo` itself is still the right function on 12.1.5, but write the
async-safe version from day one rather than the synchronous-assuming code
TopFit has now:

```lua
function TopFit:GetItemInfoSafe(item, callback)
    local info = { GetItemInfo(item) }
    if info[1] then
        if callback then callback(unpack(info)) end
        return unpack(info)
    end
    -- not cached yet -- request it and let the caller retry on the event
    C_Item.RequestLoadItemDataByID(type(item) == "number" and item or nil)
    return nil
end
```
Route `inventory.lua:73` and `calculation.lua:942` through this first —
they feed the whole scoring pipeline, so a silent nil here is the costliest
place for it to happen. Register a single `ITEM_DATA_LOAD_RESULT` handler
in `core.lua` that re-triggers whatever scan was waiting, rather than
scattering retry logic per call site.

### Gems → `C_Item.GetItemGem`
`inventory.lua:150`, `simc_export.lua:450`. Direct rename, no fallback.

### Equipment Manager → `C_EquipmentSet`
This is a full reimplementation, not a rename — confirmed by reading what
`core.lua:180-223` actually does: after equipping TopFit's picks, it
(a) clears any previously ignored slots, (b) marks every slot TopFit did
*not* fill as ignored so the next set-save doesn't capture stale gear in
those slots, then (c) calls `CanUseEquipmentSets()` /
`GetEquipmentSetInfoByName()` / `SaveEquipmentSet()` to write the set.

Direct 12.1.5 replacements for the parts that map cleanly:

| Old | New |
|---|---|
| `CanUseEquipmentSets()` | `C_EquipmentSet.CanUseEquipmentSets()` |
| `GetEquipmentSetInfoByName(name)` | `C_EquipmentSet.GetEquipmentSetID(name)` then `C_EquipmentSet.GetEquipmentSetInfo(id)` |
| `SaveEquipmentSet(name, iconIndex)` | `C_EquipmentSet.SaveEquipmentSet(setID, icon)` (create via `C_EquipmentSet.CreateEquipmentSet(name, icon)` if it doesn't exist yet) |
| `RefreshEquipmentSetIconInfo()` / `GetEquipmentSetIconInfo(i)` | replaced by icon handling built into `C_EquipmentSet.CreateEquipmentSet`/`SaveEquipmentSet` args directly — no separate refresh call needed |

**Open question, first thing to test on beta:** `EquipmentManagerIgnoreSlotForSave`
/ `EquipmentManagerClearIgnoredSlotsForSave` have no obvious
`C_EquipmentSet` equivalent in the modern API — modern Equipment Sets may
simply always snapshot every currently-equipped slot with no per-slot
ignore concept. If so, the fix isn't a renamed function, it's a design
change: instead of equipping everything then telling the game to ignore
some slots, TopFit needs to only *equip* into slots it actually has a
recommendation for and leave everything else physically untouched, so
there's nothing to ignore in the first place. Worth checking
`C_EquipmentSet` docs for an ignore-equivalent before assuming a redesign
is needed, but plan for the redesign as the fallback plan.

### Addon-loaded checks → `C_AddOns`
Not yet flagged in the earlier audit, but worth catching now since it's
part of the same client-unification break: `IsAddOnLoaded`/`GetAddOnInfo`
(if used anywhere in `core.lua`'s CallbackHandler compatibility fix
mentioned in memory) become `C_AddOns.IsAddOnLoaded`/`C_AddOns.GetAddOnInfo`.

### Itemization tooltip parsing (procparser.lua)
Unchanged from before — this is a text-parsing bug against *current* WoW
text, not a client-version question, so no reason to wait for anything:

1. Add explicit pattern checks in `LooksLikeTriggeredEffect` for the
   confirmed permanent-stat templates, checked *before* the generic
   `find("chance")` fallback:
   - `"[Ii]mproves your chance to hit with all spells and attacks by"`
   - `"[Ii]mproves your chance to get a critical strike with"` (melee /
     ranged / spells / "all spells and attacks" variants)
   - `"[Rr]educes the? chance (for your attacks )?to be dodged or parried by"`
2. New stat-key mappings for phrase-based stats with no `ITEM_MOD_*` global
   to borrow a name from: hit chance, crit chance (melee/ranged/spell/all),
   dodge/parry reduction, per-weapon-type skill.
3. Dual-stat line handling (`"...healing done by up to X and damage done by
   up to Y..."`) returning two `(statKey, amount)` pairs instead of one.
4. Flat `"Increased <Name> +N"` parsed separately from the percent patterns
   (no `%` sign, no "by" phrasing, no ambiguity with the proc classifier
   since it never contains "chance").

Confirmed real Shaman-talent instance of the same pattern, found while
scraping wowforevertalents.com: **Thundering Strikes** ("Improves your
chance to get a critical strike with all spells and attacks by N%," 1%/
rank) and **Tidal Focus** ("...increases your chance to hit with all
spells and attacks by N%," also 1%/rank) are talent-granted versions of
the exact same phrase templates as the item bonuses. If TopFit's talent
math ever reads talent tooltip text the same way it might read item
tooltip text, the same parser needs to apply there too — worth keeping
one shared phrase-matching function rather than two copies.

---

## 2. Blocked on Forever beta — stub cleanly, test day one

### Talents — the one real unknown left
Confirmed from wowforevertalents.com: Forever keeps 51 points, 3 trees,
5-points-per-row gating — the classic shape. But 12.1.5's native talent
API (`C_ClassTalents`/`C_Traits`) was built for retail's completely
different tree shape (class tree + spec tree, choice nodes, no 3-tab/
51-point structure — confirmed by checking what 12.1.5's live Warrior tree
actually looks like). Forever must be running a classic-shaped UI on top of
a client whose native talent data model wasn't designed for that shape.
Whether that surfaces through an adapted `C_ClassTalents`, a dedicated new
namespace, or something else is not something that can be worked out from
outside — it needs a client.

Keep this fully isolated: one module (extend `talentbonuses.lua` or split
a new `talents.lua`) behind a single interface —
`TopFit:GetTalentRank(tab, index)` and `TopFit:GetNumTalentTabs()` — that
the rest of the codebase calls. Everything in `calculation.lua` and
`simc_export.lua` that currently calls `GetTalentInfo`/`GetTalentTabInfo`/
`GetNumTalentTabs` directly should be rewritten to call through this
interface instead, so day one of beta is "implement six lines inside one
module" rather than "trace every call site across the codebase again."

**First thing to run on beta, before anything else:**
```lua
/dump C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
/dump C_Traits and C_Traits.GetConfigInfo
```
This single check settles whether section 2 is "wire up the real API" or
"build something from scratch," and nothing else in the talent module
should be written until it's answered.

### `GetItemStats` key-name diff
Works today on 12.1.5 in principle, but the actual key names returned for
Forever's flat-stat items (once beta items exist to test) need diffing
against what `inventory.lua:95` currently expects, since percent-based
Equip: bonuses were established (section 1) to *not* come through this
function at all — but the plain numeric stats like Strength/Stamina on the
same items still do, and their key names are what needs confirming.

### `GetSpellInfo` return shape (`simc_export.lua:376`)
Low risk, but a two-minute check once there's a glyph spell ID to test
against on Forever specifically — the function itself is present and
stable on 12.1.5, this is just about the specific spell IDs involved.

---

## Suggested sequence

1. **Today:** rewrite container/item/gem calls to `C_Container`/`C_Item`
   directly (no fallback), build the async-safe `GetItemInfoSafe`, fix the
   `procparser.lua` classification bug and add the new phrase mappings —
   all of this is testable against your live retail client right now.
2. **Today/tomorrow:** design the `C_EquipmentSet` reimplementation against
   12.1.5's live API docs, including deciding the ignore-slot redesign if
   needed. Test end-to-end on live retail before beta even starts, since
   Equipment Sets aren't Forever-specific.
3. **Beta day one:** run the `C_ClassTalents`/`C_Traits` dump above first,
   before touching anything else. That answer determines whether the
   talent module is a thin wire-up or a rebuild, and there's no point
   guessing further until it's known.
4. **Beta week one:** diff `GetItemStats` keys against real Forever items,
   validate the itemization tooltip phrase patterns against real Forever
   tooltips (not just SoD's, in case wording differs), confirm
   `GetSpellInfo` glyph behavior.

---

## Progress log

**2026-09-16 — step 1 done, step 2 done except one open item.**

- `C_Container`/`C_Item`/`C_Item.GetItemGem` rewritten directly across
  `tooltip.lua`, `frame.lua`, `inventory.lua`, `core.lua`, `simc_export.lua`
  — no fallback path left anywhere, verified by grep.
- Async-safe item info: `TopFit:GetItemInfoTable` (`inventory.lua`) and
  `TopFit:IsOnehandedWeapon` (`calculation.lua`) now request missing item
  data via `C_Item.RequestLoadItemDataByID` and queue a retry instead of
  silently returning incomplete data. Wired to a new
  `GET_ITEM_INFO_RECEIVED` handler in `core.lua` → `TopFit:RescanPendingItem`.
- `procparser.lua`: `LooksLikeTriggeredEffect` now checks the confirmed
  permanent-stat phrase templates before the generic "chance" fallback.
  New `TopFit:ParsePermanentStatLine` / `TopFit:ScanItemPermanentPercentStats`
  extract the flat/percent Equip: stats from section 8 of
  `MIGRATION_WOWFOREVER.md` into new `TOPFIT_*` pseudo-stat keys, merged
  into `inventory.lua`'s item table and registered in `core.lua`'s
  `TopFit.statList` (Weights & Caps UI) so they're assignable weights, not
  just parsed-and-discarded data.
- **Correction, logged rather than hidden:** first pass at this built a new
  standalone `pawn_compat.lua` for Pawn EP-string import/export without
  checking for existing code first. TopFit already had a complete,
  working Pawn/AMR/TopFit import-export pipeline in `import.lua`
  (`statNameToKey`, `ParsePawn`, `SanitizeScales`, the popup dialogs, all
  wired to `/topfit import`/`export pawn`). Removed the duplicate module
  and extended the existing `statNameToKey` table instead with the new
  `TOPFIT_*` pseudo-stat keys. Flagged (not guessed) one real ambiguity
  left open: `import.lua`'s existing `CombineStat(..., "SpellPower",
  "SpellDamage"/"Healing")` assumes WotLK's unified-spell-power model,
  while Forever's itemization may keep healing-done and damage-done
  separate (per the Hide of the Wild tooltip) — noted in `import.lua`
  directly, not resolved, since resolving it means guessing which model
  Forever actually uses.
- `C_EquipmentSet` rewrite done in `core.lua`; the ignore-slot redesign
  question from section 1 is left as an explicit `FIXME` comment in place
  (current behavior: saves the full current loadout, same open risk noted
  above — needs beta to resolve, not guessed at).
- `TopFit.toc` bumped `## Interface: 30300` → `120105`.
- All edited files pass `luac5.1 -p`.

Still not done: talents (blocked as planned), `GetItemStats` key diffing,
validating the itemization phrase patterns against real Forever tooltips
instead of SoD's.

**2026-09-17: checked BujuArena/AutoGear (a real, actively-maintained addon
spanning Vanilla through The War Within in one codebase) for reference.**
It takes the opposite approach from this rewrite — alias-with-fallback for
every version (`local X = X or (C_Namespace and C_Namespace.X)`) rather
than a clean no-compat rewrite — which makes sense for an addon supporting
nine-plus client generations at once, and isn't the right model for
TopFit now that it only targets one client. But two concrete things
surfaced from reading it:

1. **Confirms the talent-API question more sharply than before, with real
   code rather than docs.** AutoGear's own compatibility line is:
   ```lua
   local GetNumTalentTabs = GetNumTalentTabs or GetNumSpecializations
   ```
   This isn't a real signature-compatible replacement — `GetNumSpecializations`
   returns a spec count (usually 3), not talent-tab data, and AutoGear's
   actual spec-detection logic (`AutoGearDetectSpec`) branches into two
   **entirely separate implementations** depending on client version: pre-
   MoP clients walk `GetNumTalentTabs()`/`GetTalentTabInfo()`/`GetTalentInfo()`
   to find which tree has the most points spent; MoP+ clients call
   `GetSpecialization()`/`GetSpecializationInfo()` instead and never touch
   the old talent functions at all. There is no shared code path, no
   shim that actually works for both — just two unrelated systems
   maintained side by side. This confirms in real, tested code exactly
   what section 6 already flagged as an open risk: the pre-MoP tree-tab
   model and everything from MoP onward (specializations, and later
   Dragonflight's node-based `C_ClassTalents`/`C_Traits` trees) are
   fundamentally different data models with no mapping between them.
   Forever's confirmed 3-tree/51-point layout doesn't obviously map to
   either existing retail system, which is exactly why this stays a
   beta-day-one question rather than something to pre-build against.

2. **Found and fixed a real, separate bug this surfaced**: `InterfaceOptions_AddCategory`
   and `InterfaceOptionsFrame_OpenToCategory` (TopFit's options-panel
   registration and its "open options" command) were replaced by the
   `Settings` namespace around Dragonflight 10.0 — AutoGear's own
   polyfill confirms the replacement shape. TopFit had 5 call sites still
   on the old API (`options.lua:85`, `core.lua:223,230`,
   `MinimapButton.lua:42`, `plugins/stats.lua:122`), plus a more
   fundamental issue underneath: `TopFit.InterfaceOptionsFrame` was
   parented to `InterfaceOptionsFramePanelContainer`, a frame that no
   longer exists at all under the new system — this wasn't a "wrong
   function name" bug, the options panel would have failed to even
   *create* on 12.1.5. Fixed: the frame now parents to `UIParent`,
   registration goes through `Settings.RegisterCanvasLayoutCategory` +
   `Settings.RegisterAddOnCategory` (storing the returned category ID),
   and a new `TopFit:OpenOptionsPanel()` helper (calling `createOptions()`
   first, then `Settings.OpenToCategory`) replaces all 4 open-panel call
   sites so registration is guaranteed to have happened before anything
   tries to open the panel. All touched files re-verified with
   `luac5.1 -p`.

This was a genuinely useful check independent of the talent question —
worth doing this kind of "read a real addon that already had to solve
this" pass again if anything else in the rewrite feels uncertain.

**2026-09-17: checked generalwrex/wowsimsexporter (TBC Classic).** Its
talent-reading code uses the identical old `GetNumTalentTabs()`/
`GetTalentInfo(tab, index)` API TopFit's WotLK code already used —
confirms Classic-family client builds (TBC Classic, presumably BCC/
Anniversary too) keep this API fully alive, because they're a genuinely
separate client binary from unified retail, not just a different ruleset
on the same one. This sharpens rather than resolves the open question:
Forever is built specifically on retail (12.1.5), not in the Classic-
family client lineage, so BCC/Anniversary keeping the old API doesn't
imply Forever does, even though Forever's gameplay resembles BCC's. Genuinely
still unresolved without a beta client — this is exactly the risk
section 6 already flagged, now with a concrete comparison point rather
than pure speculation.

One reusable artifact did come out of it: the community-standard talent-
string format (`GetNumTalents(tabIndex)` per tab, then each talent's
current rank concatenated in order, `-` separating the three trees — e.g.
`50032100005-31023000000000-0500002`). This is what Wowhead-style talent
calculators and the wider Classic tool ecosystem already expect a build
serialized as. Worth using this exact format if/when Forever's talent
module needs to represent a build as a shareable string (sharing a build,
or as part of whatever the eventual sim export needs), rather than
inventing a new one.

**2026-09-17: talent-existence correction, not an API question — Dan
confirmed Titan's Grip and the Shaman dual-wield talent don't exist in
Forever's trees at all**, separate from whether the classic talent API
works. `calculation.lua`'s `(tab, index)` lookups for both pointed at
coordinates that are simply meaningless now. Removed the lookups rather
than leave them pointing at nothing; both flags default to `false`
pending confirmation of what actually grants each:

- **Titan's Grip**: defaulting to always-false is probably just correct
  — Warriors likely can't 2H-dual-wield at all anymore if the talent's
  gone with nothing mentioned replacing it.
- **Shaman dual-wield**: genuinely open, not assumed. Dual-wield is
  central to Enhancement's identity, so if it turns out to be baseline
  for the spec now (no talent required) rather than removed outright, an
  always-false default would silently misscore every Enhancement set,
  including Dan's own (Zaenith). Needs a real answer, not a guess, before
  this is filled in.
- Existing `simulateDualWield`/`simulateTitansGrip` manual override
  toggles (`options.lua`, per-set) are untouched and still work as a
  stopgap — checking "simulate dual wield" on a set bypasses
  auto-detection entirely, usable for testing right now regardless of
  how the underlying question resolves.

**2026-09-17, follow-up — Dan confirmed the actual mechanics: Enhancement
Shaman has no dual-wield at all (not baseline, not gated, just absent —
consistent with Forever's Vanilla-rooted design, since Shaman dual-wield
was a TBC-era talent addition to begin with), Warriors get ordinary
1H dual-wield same as Rogue/DK/Hunter with no talent needed, and Titan's
Grip does not exist as a mechanic at all, for any class.** Resolved the
FIXME from the entry above with this, and went further: the "Force dual-
wield" (Shaman-only) and "Force Titan's Grip" (Warrior-only) override
checkboxes in `plugins/stats.lua` existed specifically because those were
the one talent-gated case per mechanic in WotLK — every other dual-wield
class was unconditionally capable by the relevant level, no override
needed. With Shaman dual-wield now simply absent rather than gated, and
Titan's Grip absent for everyone, both checkboxes would let someone check
a box and get gear recommendations that are physically impossible to use
in-game — worse than just unused, actively misleading. Removed both
checkbox-creation blocks entirely (the remaining references elsewhere in
the file were already `if statsFrame.X then` guarded, so this degrades
safely with no crash). `calculation.lua`'s `simulateTitansGrip` handling
is commented out rather than deleted, with an explanation, so it can't be
silently reintroduced by a future edit. Note this removes the *only* UI
entry point for `simulateDualWield` too (it was Shaman-only to begin
with — Rogue/DK/Warrior/Hunter never had this checkbox since they're
unconditionally dual-wield capable already). The `simulateDualWield` data
field and `calculation.lua`'s handling of it still work if set
programmatically, but there's currently no UI checkbox exposing it for
any class. Not adding one back without knowing whether there's a real
use case for it in Forever specifically now that its original reason
(Shaman's talent gate) is gone.
Both files re-verified with `luac5.1 -p`.

**2026-09-18, real load-breaking bug — my mistake, caught via an in-game
error report:** `core.lua:12: attempt to perform indexed assignment on
global 'TopFit' (a nil value)`. The talent safe-accessor block added on
2026-09-17 was inserted near the top of `core.lua`, before the line that
actually creates the `TopFit` global (`TopFit = LibStub("AceAddon-3.0")
:NewAddon(...)`, further down the file) — so `TopFit.hasClassicTalentAPI
= ...` tried to index a nil global and the whole addon failed to load,
not just the talent-related parts. This is exactly the kind of mistake
the "no compat layer, hard-target one client" simplification doesn't
protect against — load order still matters regardless of which API
version is being targeted. Moved the whole block to immediately after
the `NewAddon` line, added a comment on it explaining why it can't move
back above that line, and re-verified with `luac5.1 -p` plus a full
codebase sweep to confirm nothing else has the same ordering problem.
Worth being more careful about load-order when inserting new top-level
code near the start of a file going forward, rather than assuming syntax-
clean means load-safe.

**2026-09-18, second load-time crash, caught within minutes of the
first:** `Libs/tekKonfig/tekKonfigAboutPanel.lua:11: attempt to call a
nil value`, during the same `OnInitialize` sequence. Root cause was the
identical category of bug already fixed in TopFit's own `options.lua` --
`InterfaceOptions_AddCategory` and a frame parented to
`InterfaceOptionsFramePanelContainer` -- but in a bundled third-party
library file that had never been swept, since every previous audit this
session explicitly excluded `/Libs/`. Reasonable for the real Ace3
libraries (AceAddon-3.0 etc., pure-Lua logic that rarely touches WoW API
directly), not reasonable for tekKonfig, which is a small unmaintained-
for-retail UI helper bundled directly in the addon rather than pulled
from an actively maintained upstream.

Fixed with the same `Settings` namespace approach as before, but wrapped
in `pcall` rather than assumed correct outright: this lib also supports
registering as a *subcategory* under an existing category (TopFit's own
call site uses this, nesting an "About" panel under the main TopFit
category), which needs `Settings.GetCategory(name)` to resolve a category
by the string name rather than by ID -- a pattern borrowed from AutoGear's
own compatibility code, real and tested there, but not something this
session has independently confirmed the exact signature of. Given this
exact call site had already taken down addon load once tonight, an About
panel isn't worth risking a repeat over an educated-but-unconfirmed API
guess -- if `Settings.GetCategory` doesn't behave as expected, the pcall
catches it, the About panel silently doesn't register, and everything
else still loads.

While fixing this, swept the whole `Libs/` folder (not just tekKonfig)
for the same class of legacy-API pattern for the first time this session
-- came back clean elsewhere. Separately found and fixed a real
`luac5.1`-blocking issue in three tekKonfig files (`tekKonfigAboutPanel
.lua`, `tekKonfigHeading.lua`, `tekKonfigCheckbox.lua`): a leading UTF-8
BOM that WoW's own Lua runtime tolerates fine (these files worked in-game
for years with it) but the standalone `luac5.1` compiler treats as a
syntax error. Pre-existing, not something introduced this session, and
harmless in-game -- stripped anyway so it can't cause this exact false-
alarm confusion again during a syntax check. Full codebase (everything
except the pure-Lua Ace3/CallbackHandler/LibStub libraries, which were
never a plausible source of WoW-API-version issues to begin with)
re-verified clean after all of the above.

**2026-09-18, third and fourth issues, both caught within the same
minute via the next in-game error report:**

1. `core.lua:719: attempt to call a nil value` — `IsEquippableItem`, used
   at 7 call sites across `core.lua`, `inventory.lua`, and `tooltip.lua`,
   was removed outright in patch 10.2.6 (confirmed via warcraft.wiki.gg's
   own patch history, not guessed), replaced by `C_Item.IsEquippableItem`.
   This one had never been flagged anywhere in this doc before tonight —
   it wasn't in the original container/item/gem audit's function list at
   all. Renamed all 7 call sites directly, no fallback.
2. `Libs/tekKonfig/tekKonfig.xml:2 Error loading .../LibStub.lua` —
   separate from the Lua-level bugs above, this is a bundling defect in
   the XML load chain itself. `embeds.xml` already loads the real
   `Libs\LibStub\LibStub.lua` correctly; `tekKonfig.xml` (included
   afterward) had its own redundant `<Script file="LibStub.lua"/>` line
   pointing at a copy that was never bundled at that path. Removed the
   line entirely (redundant even if the path were fixed, since LibStub is
   already global by the time this include runs) and documented why in
   an XML comment.

While fixing #2, made a real mistake of my own worth logging plainly: my
first version of that explanatory XML comment used `--` as a dash
separator several times, which XML comments don't allow in their body —
broke well-formedness, caught immediately by validating with Python's
`xml.etree.ElementTree` before shipping it, rewrote without the double-
hyphens. Also used this as a prompt to validate every `.xml` file in the
addon, not just the one touched: everything else parses clean except
`embeds.xml`, which reports a namespace-prefix warning from Python's
strict parser (missing `xmlns:xsi` declaration for its
`xsi:schemaLocation` attribute) — this is standard, ubiquitous
boilerplate identical to Blizzard's own addon templates, pre-existing and
untouched this session, and the game's own XML parser has always
tolerated it. Left alone rather than "fixed" on a false positive from a
stricter external validator than the actual consumer.

Full codebase re-verified with `luac5.1 -p` plus XML well-formedness
checks after both fixes.

**2026-09-17: crash-hardened every talent call site ahead of beta,
prompted by "will the zip actually be usable to test with in 12 hours".**
Found a real, previously-missed risk: `calculation.lua`'s dual-wield/
Titan's Grip detection called `GetTalentInfo` **unconditionally** at the
start of every single calculation (short-circuited only by class, so it
fires immediately for Dan's own Shaman), and `simc_export.lua`'s talent-
string builder/`DebugTalentCounts` called `GetNumTalentTabs()`
unconditionally too. If these globals don't exist on Forever at all
(the open question this whole section is about), every one of these was
one `/topfit export` or gear-set calculation away from a hard Lua error
-- "attempt to call a nil value" -- that would have blocked testing
everything else in the addon, not just the talent-dependent parts.

Added `TopFit.hasClassicTalentAPI` (checked once, via `type(...) ==
"function"`) plus four safe wrappers in `core.lua`
(`GetNumTalentTabsSafe`, `GetNumTalentsSafe`, `GetTalentTabNameSafe`,
`GetTalentRankSafe`) that return 0/nil instead of erroring when the API
doesn't exist. Rewired every direct call in `calculation.lua` and
`simc_export.lua` to go through these -- confirmed via grep that no live
call sites remain, only comments/print-string labels mentioning the
function names. `talentbonuses.lua` never had live calls to begin with
(just documentation).

Net effect: if Forever turns out not to have this API, TopFit now
degrades to "talent-granted bonuses read as zero, dual-wield/Titan's Grip
auto-detection silently skipped, talent string export returns a clear
`no_talent_api` reason" instead of crashing. Container scanning, item
scoring, itemization parsing, and equipment sets -- everything actually
testable right now -- stays fully usable regardless of how the talent
question resolves. All touched files re-verified with `luac5.1 -p`.

---

## 3. Sim export target: community WowSims, not a custom sim/frontend

2026-09-16 decision: all Triumvirate work (the `simc-triumvirate` C++ fork
and everything built on it) is cancelled. TopFit's export feature should
target community-developed WowSims (wowsims.com, Go-based) as a sim
backend once one exists for Forever, rather than TopFit or a custom
project hosting its own sim/web frontend.

Checked the actual WowSimsExporter addon (v3.2.4, the real companion tool
for wowsims.com) to see what there is to build against today. Findings:

- **Plain JSON, not a custom binary format.** `Env.CreateCharacter():
  FillForExport()` → `LibParse:JSONEncode(character)`. Nothing exotic to
  reverse-engineer.
- **Item schema is protobuf-derived and versioned by an `elseif` chain**
  on `Env.IS_CLASSIC_ERA` / `IS_CLASSIC_TBC` / `IS_CLASSIC_WRATH` /
  `IS_CLASSIC_CATA` / `IS_CLASSIC_MISTS` flags (`ExportStructures/
  ItemSpec.lua`), each adding fields like `gems`, `random_suffix`,
  `reforging`, `upgrade_step` as that version's itemization needs them.
  No Forever branch exists, and can't yet — WowSims itself has no Forever
  support, so this isn't a TopFit-side gap to close, it's upstream not
  existing yet. Once the community (or Dan) forks WowSims for Forever,
  this file is exactly the pattern to extend, and TopFit's own export
  should mirror whatever field set that fork settles on rather than
  inventing a competing schema.
- **The addon has zero retail/Forever interface support today** (TOC tops
  out at Mists Classic, interface `50504`) and gates itself on
  `WOW_PROJECT_ID` via `Env.IS_CLIENT_SUPPORTED`. If Forever doesn't get
  its own distinct `WOW_PROJECT_ID`, this addon (and by extension anything
  modeled on it) needs the same kind of heuristic detection it already
  uses for Season of Discovery — SoD shares Classic Era's project ID and
  is instead detected via `C_Engraving.IsEngravingEnabled()`, a SoD-
  exclusive API. **Added to the beta-day-one checklist below.**
- Its own legacy-API footprint (`GetTalentInfo`/`GetNumTalentTabs`/
  `GetSpellInfo`/`GetInventoryItemLink`) has the identical talent-API
  unknown TopFit already has flagged in section 6 — not a new problem,
  just confirmation it's shared across the whole addon ecosystem, not
  particular to TopFit's own code.

**Updated beta-day-one checklist** (in addition to the `C_ClassTalents`/
`C_Traits` dump from section 2):
```lua
/dump WOW_PROJECT_ID
-- if it doesn't match a known constant, look for a Forever-exclusive
-- C_* function/API the way C_Engraving.IsEngravingEnabled() flags SoD
```

No code changes to TopFit yet for this target — there's nothing concrete
to build against until WowSims itself has a Forever branch. Revisit once
that exists.

---

## 4. SixtyUpgrades schema — confirmed, not assumed (partial)

2026-09-17: got a real sample export (character envelope + stats block,
from Zaenith). Confirms what section "SixtyUpgrades is NOT the Pawn
format" already suspected, now with an actual schema instead of an
assumption:

```json
{
    "name": "Zaenith",
    "character": { "name", "level", "gameClass", "race", "faction" },
    "items": [], "consumables": [], "buffs": [], "talents": [], "points": [],
    "stats": {
        "agility", "armor", "attackPower", "block", "blockValueBonus",
        "crit", "defense", "dodge", "health", "intellect", "mana", "parry",
        "spellCrit", "spirit", "stamina", "strength"
    },
    "exportOptions": { "buffs": true, "talents": true }
}
```

- **Third independent confirmation of the flat-percentage itemization
  model** (`crit`, `spellCrit`, `dodge`, `parry`, `block` all plain
  percentages, no rating fields) — now confirmed at the item-tooltip level,
  the talent-tooltip level, and the sim tool's own character schema.
- **Not Pawn-compatible naming**, confirmed rather than assumed: camelCase
  vs Pawn's PascalCase, and several fields don't map 1:1 (`attackPower` vs
  Pawn's `Ap`, `spellCrit` vs `SpellCritRating`, `blockValueBonus` vs
  `BlockValue`). A SixtyUpgrades importer needs its own mapping table, not
  a shared one with the existing Pawn pipeline in `import.lua`.
- **Gap this sample doesn't close:** `items`/`talents`/`points` are all
  empty in this sample, so the per-item schema (SixtyUpgrades' equivalent
  of WowSims's `ItemSpec` — itemID/enchant/gems shape) and per-talent
  schema are still unconfirmed. That's the part actually needed to build
  export, not just the envelope. Need a sample with gear/talents filled in
  to close this out.
- No `hit`/`haste`/`expertise` fields present — consistent with a bare,
  ungeared level-60 character (no gear-granted hit/haste to report) rather
  than evidence those stats don't exist in this schema; revisit once a
  geared sample is available.

**2026-09-17, geared sample received — gap partially closed. NOTE: this
sample is a Season of Discovery gear set built in SixtyUpgrades purely to
see the export system's shape, not Forever data. Corrected below after
initially (wrongly) treating it as Forever-sourced.**

- ~~Item IDs are new, not reused from Classic's database~~ — **retracted.**
  This was SoD data, not Forever data, so the item IDs are real SoD IDs
  and say nothing about whether Forever will reuse Classic's item ID space
  or use fresh ones. That question is still fully open, not answered.
- **`items` schema confirmed** (this part still holds regardless of source,
  since it's SixtyUpgrades' export format, not something specific to SoD):
  flat `{name, id, slot}` only — no `enchant`, `gems`, or `randomSuffix`
  fields even with a full loadout present. Either this export type (a
  saved "prebis"/wishlist preset, per the envelope's `name`/`phase`
  fields) intentionally omits socket-level detail since it's a target list
  rather than actually-worn gear, or the schema genuinely doesn't carry
  that granularity — needs a sample of an *equipped* character (not a
  preset) to tell which.
- **`points` schema confirmed**: named EP scales, `{name, stats:
  {statKey: weight}}`. Sample includes SixtyUpgrades' own built-in
  "Enhancement EP" scale for SoD: `attackPower:1, strength:2, agility:1.17,
  crit:23.38, hit:24, dps:14, speed:50, intellect:1` — SoD-specific
  reference numbers, useful as a sanity-check data point but not
  necessarily Forever's eventual weights.
- **New stat category surfaced**: `undeadAttackPower` (creature-type-
  conditional damage) confirmed present in SoD's schema, matching the
  "Undead Slaying" gear in the same loadout. Whether Forever's schema
  carries the same category is unconfirmed, but the SixtyUpgrades export
  *format itself* clearly supports it as a concept, which is the useful
  part for planning purposes.
- ~~**SixtyUpgrades has no Forever support either**~~ — **RETRACTED
  2026-09-27:** a later live export (see "Live Forever export" below) has
  `sixtyupgrades.com/forever/...` set and talent links in it, so
  SixtyUpgrades DOES have live Forever support. This bullet was true when
  written (that earlier sample was a Season of Discovery stand-in) but
  went stale and never got corrected until now. Original text follows for
  the record — this whole exercise was Dan using SoD as a stand-in
  supported game mode just to learn the export tool's shape ahead of
  Forever existing, which is exactly the right move given nothing Forever-
  specific exists to test against yet. The schema shape (envelope, items,
  points, stats block) should carry over once Forever support is added,
  since it's the same addon/format — but any *values* in this sample
  (item IDs, the specific EP weights) are SoD's, not Forever's, and
  shouldn't be treated as Forever data anywhere else in this doc.

Slot names confirmed as an enum-like string set: `HEAD, NECK, SHOULDERS,
CHEST, WAIST, LEGS, FEET, WRISTS, HANDS, FINGER_1, FINGER_2, TRINKET_1,
TRINKET_2, BACK, MAIN_HAND, RANGED` (no `OFF_HAND` in this particular
sample — this loadout may simply not have one itemized yet, not
necessarily evidence the slot doesn't exist in the schema).

**2026-09-16, continued:**

- `simc_export.lua`'s glyph export used the global `GetSpellInfo` — confirmed
  via warcraft.wiki.gg's own patch-change notes that this was **removed
  outright in patch 11.0.0** (deprecation fallback removed in 11.0.2), not
  just changed shape. It doesn't exist on 12.1.5 at all; the old code would
  have hard-errored the first time a glyph was equipped. Fixed to
  `C_Spell.GetSpellInfo(glyphSpellID)`, which returns one table (`.name`,
  `.iconID`, `.castTime`, etc.) instead of positional values.
- Flagged, not fixed or removed: `GetNumGlyphSockets`/`GetGlyphSocketInfo`
  (the rest of that same function) assume Inscription glyphs exist as a
  system at all. Forever's confirmed 51-point/3-tree talent scale matches
  Vanilla, not WotLK (which is where glyphs were introduced) — weak but
  real evidence Forever may not have glyphs, in which case this function is
  moot for Forever rather than broken. Left in place since the existing
  `and`-guards already no-op it safely either way; noted in-code to
  confirm and either delete or clear the comment once beta's up.
- Confirmed, incidentally, while checking `GetSpellInfo`'s removal patch:
  `GetItemInventorySlotInfo`'s own deprecation notice states its fallback
  is being removed **in patch 12.1.5 specifically** — independent
  confirmation that 12.1.5 is exactly the patch where a batch of long-
  deprecated compatibility shims get pruned, which is good validation for
  going no-compat now rather than waiting.
- `GetInventoryItemsForSlot` (`inventory.lua:503`) checked against current
  API docs — no deprecation notice, still valid. No change needed.
- All files re-verified with `luac5.1 -p` after these changes.

**2026-09-17: full re-sweep across every file, including the ones not
touched in the first pass (`options.lua`, `presets.lua`, `plugin.lua`,
`MinimapButton.lua`, `plugins/*.lua`).** Found and fixed one real miss:
`options.lua`'s `DeleteSet`/`RenameSet` still called the bare legacy
`CanUseEquipmentSets()`/`GetEquipmentSetInfoByName()`/`DeleteEquipmentSet()`/
`RenameEquipmentSet()` globals — these hadn't been touched in the
`core.lua` Equipment Manager rewrite since they're a separate call site.
Rewritten to `C_EquipmentSet.CanUseEquipmentSets()` /
`C_EquipmentSet.GetEquipmentSetID()` / `C_EquipmentSet.DeleteEquipmentSet(id)`
/ `C_EquipmentSet.RenameEquipmentSet(id, newName)`, matching the id-based
pattern the modern API uses throughout (name-based lookup, then operate by
ID, rather than the old name-based calls directly). Everything else in
`presets.lua`/`plugin.lua`/`MinimapButton.lua`/`plugins/*.lua` came back
clean. Whole codebase re-verified with `luac5.1 -p`, and the earlier
"leftover legacy calls" false alarms during this sweep were self-inflicted
grep mistakes (matching substrings inside already-correct `C_Container.*`/
`C_EquipmentSet.*` calls, or piping `grep -o` output through a content
filter that could never match against the truncated output) — logged here
so it's clear those were verification bugs, not code bugs, if this comes
up again.

---

### Live Forever export (2026-09-27) -- a real Forever character, not a stand-in

Dan's Forever Hunter "Zae" (level 21, Night Elf, Alliance, "Levelling" set, phase 1),
exported from SixtyUpgrades with `links.set` / `links.talents` pointing at
`sixtyupgrades.com/forever/...`. This is the first genuinely Forever-sourced
sample and settles several things the SoD stand-in couldn't:

- **Talent schema, finally seen with data:** `{name, id, rank, spellId}` per
  talent -- e.g. Lethal Attacks `{id: 105011, rank: 5, spellId: 19426}`. Keyed by
  unique ID + spellId, never by tab/index, consistent with the C_Traits
  node-based system Dan's `GetRetailTalentRanks()` already reads. Only talents
  with points spent appear to be listed (3 entries here, not the whole tree). Real
  spellIDs are available from this source, unlike wowforevertalents.com.
- **Item enchant schema:** `"enchant": {"name", "id", "spellId"}` per item, e.g.
  Forceful Medium Armor Kit / Enchant Bracer - Minor Agility. Enchants exist
  in Forever (armor kits included); gems still don't (no `gems` key anywhere).
- **New per-item field `"acquired": true`** -- not seen in the SoD sample;
  presumably distinguishes owned gear from wishlist entries in a set.
- **Item IDs are a mix**: some low classic-style IDs (Serpent's Shoulders 5404,
  Blackened Defias Boots 10402, Venomstrike 6469) alongside high fresh-looking
  ones (252504, 277204, 279897, 282283). So Forever appears to reuse classic item IDs for
  classic items and use new ID ranges for its own additions (an inference from
  one small sample, not confirmed) -- this replaces the retracted "all-new IDs"
  guess from earlier, which the data contradicts.
- **Stat block is the flat model, again:** `crit`, `spellCrit`, `rangedCrit`,
  `dodge`, `parry` as plain percentages, plus per-school flat damage stats
  (`arcaneDamage`, `fireDamage`, `frostDamage`, `natureDamage`, `shadowDamage`,
  `holyDamage`), `spellDamage`, and `healing` -- so damage bonuses are tracked
  per school as well as generically. `procparser.lua`'s single
  `TOPFIT_SPELL_DAMAGE_FLAT` bucket may be too coarse if gear itemizes
  school-specific damage; unconfirmed, flagged.
- **Ranged/melee stat split confirmed:** `rangedAttackPower`, `rangedCrit`,
  `rangedSpeed`, `mainHandSpeed` are separate fields.
- **`points` example (Forever, Hunter):** "Hunter EP" = `attackPower 1,
  rangedAttackPower 1, agility 2.79, crit 28.57, hit 21.98, rangedDps 14,
  rangedSpeed 100` -- a community-tuned starting point for Forever Hunter
  weights, and the natural source for rewriting `presets.lua` (see below).
- **Real test case for the talent pipeline:** Zae has Lethal Attacks at 5/5,
  which `talentbonuses.lua` maps to `TOPFIT_CRIT_CHANCE_PHYSICAL` at 1%/rank.
  Running `/topfit talentdebug` on Zae should list "Lethal Attacks" rank 5, and
  a physical-crit cap should drop by 5 in the effective value.

## 5. Talent system fully wired end-to-end; equipment-set save instrumented

2026-09-26: Dan's own repo (real git history, `forever` branch) had already resolved
the biggest open question independently — `TopFit:GetRetailTalentRanks()` in
`core.lua` confirmed via live testing that Forever's talents are read through
`C_ClassTalents.GetActiveConfigID()` + `C_Traits.GetConfigInfo/GetTreeNodes/
GetNodeInfo/GetEntryInfo/GetDefinitionInfo` — the modern node-based trait system,
addressed by spellID/name, not `(tab, index)`. This matches what the SixtyUpgrades
talent export schema hinted at earlier (talents keyed by `id`/`spellId`, never
tab/index) — that was the right signal.

**Correction, logged rather than quietly fixed:** this section originally also
claimed "Forever's class roster includes Evoker, Demon Hunter, and Monk alongside
the classic nine," based on seeing those three (plus Death Knight) added to
`CLASS_ARMOR_TYPE` and `simc_export.lua`'s class-token maps in Dan's repo. That
was wrong — Dan confirmed later the same day that **none of those four classes
exist in WoW: Forever at all**. The entries had been added speculatively, not as
confirmed data, and I reported them as a finding without flagging that distinction.
All four have since been removed from `calculation.lua` (`CLASS_ARMOR_TYPE`, the
dual-wield class check), `core.lua` (the plate-wearer check), `simc_export.lua`
(both class-token tables), and `presets.lua` (Death Knight's entire stale preset
block, ~150 lines of WotLK-rating-based data that would have been wrong twice
over — wrong class, wrong stat model). `talentbonuses.lua`'s trailing note updated
to say these classes don't exist, not "no data yet." Worth being more careful
going forward about distinguishing "this appeared in the code" from "this was
confirmed" — those are different claims and this entry conflated them.

One gap found in Dan's version: `GetRetailTalentRanks()` was wired into the
`DebugTalentCounts` diagnostic but not into the actual scoring pipeline — closed
now:

- **`talentbonuses.lua` fully rewritten**, not just patched. New format keyed by
  `name` (and optional `spellID`, preferred once confirmed) instead of
  `(tab, index)`, crediting `TOPFIT_*` percent pseudo-stats directly instead of
  converting through a rating-per-percent constant into `ITEM_MOD_*_RATING` —
  correct for Forever's flat-percent itemization model (section 8), where the old
  rating-conversion approach was simply wrong, independent of Triumvirate being
  cancelled. All old WotLK/Triumvirate data removed rather than left as a
  "starting guess" — Forever's talents are a real redesign (Stormstrike, Flurry
  rework, etc.), so a WotLK-based number isn't an approximation, it's just wrong.
  Only two entries populated (Shaman: Thundering Strikes → `TOPFIT_CRIT_CHANCE_ALL`,
  Tidal Focus → `TOPFIT_HIT_CHANCE_ALL`, both 1%/rank), sourced from the
  wowforevertalents.com scrape and explicitly marked as NOT yet cross-checked
  against a live `/topfit talentdebug` output. Every other class is intentionally
  empty (a no-op, not an oversight) until real data is gathered the same way.
- **`calculation.lua`'s `GetTalentRatingBonuses()` rewritten** to call
  `GetRetailTalentRanks()` and match entries by `spellID` first, falling back to
  `name`. Confirmed the consuming side (`GetEffectiveCapValue`) is unit-consistent
  with no changes needed — it subtracts `talentBonusStats[stat]` from a cap's
  nominal value generically by stat key, and since both gear (via
  `procparser.lua`'s tooltip scan) and talents now report `TOPFIT_*` stats as
  plain percent, this works correctly with no conversion layer.
- Swept the whole codebase for any other code assuming the old `entry.tab`/
  `entry.index`/`entry.perPoint`/`entry.percentType` shape — none found.

**Equipment set save issue (Dan reported sets not saving) — instrumented, not
guess-fixed.** Without live access, the exact failure point isn't confirmed (
`CanUseEquipmentSets()` returning false, `CreateEquipmentSet` failing silently, or
something else). Wrapped the create/save calls in `pcall` and added explicit
`Print`/`Debug` output at each branch (whether an existing set was found, whether
create/save succeeded, and the specific error if `CanUseEquipmentSets()` returns
false) so the next test run pinpoints the actual cause instead of staying silent.

All touched files re-verified with `luac5.1 -p`, full codebase sweep included.

---

## 6. Consolidated outstanding data-gathering checklist (2026-09-26)

Everything below is real data that has to come from an external source before it
can be filled in — pulled together here from throughout this doc so it's one
list instead of scattered across the session log. Update this section (don't
just append another log entry) as items get closed out.

**From the live client:**
- [ ] `WOW_PROJECT_ID` (`/dump WOW_PROJECT_ID`) -- confirms whether Forever needs
      a SoD-style heuristic detection instead of its own project ID
- [ ] Actual interface/build number (`/dump select(4, GetBuildInfo())`) against
      the TOC's guessed `120105`
- [ ] `GetItemStats()` key names on a few real Forever items
- [x] Whether `GetNumGlyphSockets`/`GetGlyphSocketInfo` return anything real -- RESOLVED 2026-09-26 (Dan confirmed): no Inscription in Forever at all, no glyphs to read. Glyph-export code removed rather than left as a guard.
- [ ] Equipment set save failure -- now instrumented, needs one real test + the
      resulting debug/print output
- [ ] `/topfit talentdebug` output for every class, run with a stat-relevant
      talent actually selected -- this is what turns a scraped talent into a
      confirmed `talentbonuses.lua` entry

**From wowforevertalents.com:**
- [x] Warrior -- DONE 2026-09-26, from a saved wowforevertalents.com page Dan
      provided directly. Higher confidence than Shaman's entries: this page's
      data is sourced from actual beta client trait data via wago.tools (build
      1.60.1.70009), not BlizzCon footage. Added: Deflection (parry%), Cruelty
      (melee crit%), Precision (hit%), Anticipation (flat Defense -- a different
      talent from Shaman's same-named one), Shield Specialization (block%).
      Confirmed no Titan's Grip talent exists anywhere in the tree, matching
      Dan's direct confirmation. New pseudo-stats added along the way:
      TOPFIT_PARRY_CHANCE_ALL, TOPFIT_BLOCK_CHANCE_ALL (registered in core.lua's
      statList and given inferred-but-unconfirmed item-tooltip patterns in
      procparser.lua). Skipped as too complex for this table's model: Toughness
      (Protection) is a multiplicative armor scalar, not an additive stat;
      Weaponmaster (Arms) branches by equipped weapon type; Dual Wield
      Specialization (Fury) grants three simultaneous off-hand-specific effects
      not known to be itemized on gear separately.
- [x] Hunter, Paladin, Rogue, Mage, Priest, Druid, Warlock -- DONE 2026-09-26,
      from a full 8-class data zip Dan provided directly (all client-data-sourced
      via wago.tools, same confidence tier as Warrior). Also used to independently
      re-confirm Shaman's Thundering Strikes/Tidal Focus (matched exactly) and add
      the previously-missed Anticipation (dodge%) entry for Shaman.
      Three new pseudo-stats added: TOPFIT_HIT_CHANCE_SPELL (generic single-bucket
      spell hit, since nearly every caster class has its own school-specific hit
      talent but a given character only has one relevant school),
      TOPFIT_CRIT_CHANCE_PHYSICAL (Hunter/Rogue's "critical strike chance with all
      attacks" phrasing -- distinct from MELEE since Hunter is ranged-primary),
      TOPFIT_DODGE_CHANCE_ALL. All registered in core.lua's statList with
      inferred-but-unconfirmed item-tooltip patterns added to procparser.lua.
      A long list of talents were deliberately excluded (pet-only stats,
      derived/scaling-from-another-stat effects, procs/temporary buffs,
      form-locked Druid talents, single-spell-specific bonuses, weapon-type-
      conditional multi-effects, and damage/healing multipliers) -- see
      talentbonuses.lua's own header comment for the full reasoning, grouped by
      exclusion reason rather than repeated per class.
- [x] ~~Death Knight, Evoker, Demon Hunter, Monk~~ -- RESOLVED 2026-09-26 (Dan
      confirmed): none of these four exist as playable classes in WoW: Forever
      at all. All talent-data checklist items are now closed -- all nine real
      classes are covered above. Stray references to these four classes found
      and removed from `calculation.lua`, `core.lua`, `simc_export.lua`, and
      `presets.lua` (the last of which was also carrying a stale ~150-line
      Death Knight preset that would have been wrong regardless).

**Talent checklist complete.** Every remaining item below is unrelated to
talents.

**From SixtyUpgrades exports:**
- [x] ~~A sample with real gem sockets filled~~ -- MOOT 2026-09-26 (Dan confirmed): no Jewelcrafting in Forever at all, no gems or sockets exist on any item. `gem_ids.lua` cleared (was 2400+ lines of stale WotLK/Triumvirate gem data) and removed from the TOC's load order; gem-reading code left in place where it was already safely inert, simplified to a stub where it was self-contained enough to do so safely.
- [ ] One or two more classes, ideally a caster, to cross-check stat-block
      field-name consistency

**From real item tooltips in-game:**
- [x] `procparser.lua`'s percent-stat phrase templates -- DONE 2026-09-27,
      from 8 real Forever gear screenshots. Confirmed the SoD-sourced
      phrasing was close but not exact (hit/crit are shorter forms on real
      Forever gear); added the combined damage+healing line and per-school
      damage lines, which weren't anticipated at all; fixed the flat
      `Increased X +N` pattern, which was never matching anything due to a
      start-of-line anchor real tooltip text doesn't satisfy. See section 8
      for the full before/after. Parry/block/dodge-chance item phrasing
      (added speculatively alongside the Warrior talent work) remains
      unconfirmed -- none of the 8 screenshots happened to show one.

**Not a data source, a caution:** treat Discord/community "fixes" with the same
skepticism as the SavedVariables true/false-vs-1/0 claim (2026-09-26) --
plausible-sounding folk fixes circulate fast in a new beta community and aren't
always right. Bring anything that sounds like a real client behavior change
here to check against what TopFit actually does before acting on it.

---

## 7. `GetItemInfo` bare global confirmed fully absent on Forever (correction)

2026-09-27, from an in-game crash: `procparser.lua:189: attempt to call a nil
value` in `LookupSimcProcData`, which called the bare global `GetItemInfo(itemLink)`
directly. This corrects an assumption in section 1 above ("Item data →
`GetItemInfo` (kept)") -- that assumption was wrong, or at least doesn't hold on
this client. The bare `GetItemInfo` global is confirmed **completely absent**
(nil, not just async-different) on Forever; only `C_Item.GetItemInfo` exists.

This call site had simply never been touched -- the async-safe wrapper work
earlier only covered `inventory.lua`/`calculation.lua`, not every bare call in
the codebase. Swept and found 4 more in `frame.lua` with the same problem, all
fixed the same way (direct rename to `C_Item.GetItemInfo`, no fallback).
Checked for the same issue on other item-related globals
(`GetItemInfoInstant`, `GetItemIcon`, `GetItemQualityColor`, `IsUsableItem`,
`GetItemSpell`, `GetItemCount`) -- none found as bare calls anywhere in the
codebase, so this appears to have been isolated to `GetItemInfo` specifically.

Lesson for future fixes in this doc: a targeted wrapper in one or two files
doesn't mean a function is fixed everywhere it's called -- worth greping the
whole codebase for a bare global by name once one confirmed-broken instance
turns up, rather than assuming other call sites were already covered.

---

## 8. Real gear tooltips confirmed, equipment-set save rewritten, set-preview bug found

2026-09-27, from 8 in-game screenshots of real Forever gear -- the itemization
phrase-pattern checklist item is now genuinely closed, not just carried
forward. Ran every real `Equip:` line through the actual parser before
touching anything (`/tmp/ptest`, a standalone Lua harness loading
`procparser.lua`'s pattern table directly) rather than eyeballing the regexes.
Baseline: **2 of 10 real lines parsed, 8 missed** -- the Season of Discovery
phrasing this was all built against was close but not exact.

Fixed, each confirmed against a real screenshot:
- **Short-form hit/crit** (Precision Bow, Theramore Spaulders): Forever drops
  "with all spells and attacks" that SoD uses -- gear says "Improves your
  chance to hit by N%." / "...to get a critical strike by N%." directly. This
  was the single biggest miss -- essentially all gear-granted hit/crit was
  going unscored, and worse, being misrouted into the proc-detection path by
  the generic "chance" check.
- **Combined damage+healing, one number** (Enriched Thorium Helm, Stalwart
  Helm): "Increases damage and healing done by magical spells and effects by
  up to N." -- distinct from the existing split healing-X-damage-Y pattern;
  credits the same value to both `TOPFIT_SPELL_DAMAGE_FLAT` and
  `TOPFIT_SPELL_HEALING_FLAT`.
- **Per-school damage** (Filigreed Shadow Circlet, Acolyte's Chain Helm):
  "Increases damage done by Shadow spells and effects by up to N." Six new
  stats added (`TOPFIT_ARCANE/FIRE/FROST/HOLY/NATURE/SHADOW_DAMAGE_FLAT`) --
  tracked per school, not folded into the generic bucket, since a Shadow
  Priest shouldn't be credited for Fire damage gear and Forever's own
  character-stats block (section on the live SixtyUpgrades export above)
  already lists these six separately.
- **Flat `Increased X +N`** was never matching at all -- the pattern was
  anchored to the start of the line (`^increased`), but real tooltip text
  carries the `Equip: ` prefix (Enriched Thorium Helm: "Equip: Increased
  Defense +8."). Un-anchored, and extended to allow multi-word weapon names.
- **Persisted item-cache versioning added** (`core.lua`, `ITEM_CACHE_VERSION`
  = 2): every one of these fixes was invisible to any item the client had
  already scanned before now, since `db.global.itemCache` had no version
  check and just kept serving the old (wrong) result forever. Bumping this
  constant on any future scan-affecting change now wipes the cache once.

## 9. Equipment sets: one real bug found, one rewritten for verifiability, one still open

Dan confirmed sets still weren't saving after the first instrumentation pass,
plus a second symptom: switching TopFit's own set dropdown away and back
"forgets" the original set's contents. Three separate things addressed:

1. **Real bug, `options.lua`'s rename function**: called
   `C_EquipmentSet.RenameEquipmentSet`, which does not exist -- the actual
   modern function is `ModifyEquipmentSet(setID, newName)` (the old
   `RenameEquipmentSet` global was replaced by this in patch 7.2). Any rename
   would have thrown. Fixed.
2. **`TopFit:SaveGearToEquipmentSet` rewritten as a single, testable routine**
   used by both the post-calculation save and a new `/topfit saveset [name]`
   command that tests saving without running a full calculation first. Every
   outcome is unconditionally printed (the old code only used `TopFit:Debug`,
   silent unless debug mode is on -- a save that worked and one that silently
   didn't looked identical). The result is read back with
   `GetEquipmentSetInfo` and reported (items saved, slots ignored) rather than
   trusting the create/save call did what was asked. Per-slot exclusion via
   `IgnoreSlotForSave` is back (an earlier FIXME in this file claimed that
   function might not exist -- it does, confirmed against a documented list
   of all 23 `C_EquipmentSet` functions, so that FIXME was itself wrong). The
   icon is now a numeric fileID read off the player's own gear rather than a
   hardcoded `"Interface\\Icons\\..."` path string, which the API does not
   document as an accepted format for `CreateEquipmentSet`. Every branch
   (create, update, `CanUseEquipmentSets` false, create throwing, create
   silently returning nothing) tested against a mock `C_EquipmentSet` in
   `/tmp/ptest` before shipping.
3. **Still open, but now correctly diagnosed rather than guessed at further**:
   `frame.lua`'s `UnpackLocationSafe` assumed `C_EquipmentSet.UnpackLocation`
   is the modern name for the old `EquipmentManager_UnpackLocation` global.
   That name does not appear in the same documented 23-function list from
   point 2 above -- every historical source describes only the bare global.
   Whether the bare global still exists on 12.1.5 is unconfirmed either way
   (it's exactly the kind of legacy FrameXML global removed elsewhere this
   session -- `GetSpellInfo`, `IsEquippableItem`, `InterfaceOptions_*`). This
   function's only call site rebuilds a saved set's item preview for TopFit's
   own dropdown -- if it silently returns all-nil, that preview comes back
   empty, which matches "forgets the original set" more precisely than a
   coincidence. Two things done about it:
   - A one-time `TopFit:Print` warning if neither the `C_EquipmentSet` nor
     bare-global path is available, so this stops being silent.
   - The set-preview reconstruction rewritten to not depend on it as the
     *only* path: tries the currently-equipped slot first (exact itemID
     match against what the set recorded, full enchant fidelity, no
     UnpackLocation involved at all), then the legacy unpack path, then a
     full bag scan for a matching itemID, then a bare-itemID link as a last
     resort. All four branches tested against a mock in `/tmp/ptest`,
     including confirming a stale/mismatched equipped item is correctly
     rejected rather than used.

   Not claiming this is fixed -- claiming it's now instrumented and
   defended-in-depth rather than resting entirely on one unconfirmed function.
   The `/topfit saveset` command plus the new warning message are what will
   actually answer this on the next test.

**2026-09-27 follow-up, same session:** the warning fired -- neither
`C_EquipmentSet.UnpackLocation` nor `EquipmentManager_UnpackLocation` exist
on this client. Confirmed, not suspected, now. No fix needed beyond what's
already there: the preview-reconstruction rewrite above doesn't depend on
either function as its primary path, so this is expected and handled.

**A second, more serious bug found from the same log**: `/topfit saveset`
reported `Equipment set 'Enhancement (TF)' updated (ID 0)` on what should
have been that set's first-ever save, and Dan reported sets appearing to
save across CHARACTERS rather than staying per-set. `C_EquipmentSet.
GetEquipmentSetID`'s documented contract (warcraft.wiki.gg) is that it
returns `nil`, never `0`, when no set with the given name exists -- but in
Lua, `0` is truthy, so if this beta client actually returns `0` for "not
found" (a plausible beta-client deviation from the documented contract,
not confirmed by name but strongly implied by the symptom), every
`if existingSetID then` check in the codebase would wrongly take the
"update existing set" branch instead of creating a distinct new one --
exactly matching both the "ID 0" log line and the cross-character symptom.
Added `TopFit:GetEquipmentSetIDSafe(setName)`, which treats `0` the same
as `nil`, and routed every `C_EquipmentSet.GetEquipmentSetID` call in the
codebase through it (`core.lua`'s save routine, both `options.lua` rename/
delete call sites, both `frame.lua` set-preview call sites -- 5 call sites
total, all previously calling the raw function directly). Verified against
a mock reproducing the suspected buggy behavior before shipping: the raw
call returns `0` (truthy) for a nonexistent set, the wrapper correctly
returns `nil`. This is a strictly safe change either way -- it's a no-op
if the client actually follows the documented contract, and fixes exactly
this failure mode if it doesn't.

All touched files re-verified with `luac5.1 -p`. The parser and the
save/preview logic changes were additionally tested against Lua mocks
(`/tmp/ptest`) before being written back, not just syntax-checked --
worth doing this for any future fix with real branching logic, not only
ones that happen to raise a suspicion this strong.
