# TopFit Rewrite Plan — WoW: Forever (client version 1.60.01, interface 16001)

Reorganized 2026-09-27 — previously a flat chronological log (1450 lines);
restructured into a current-state reference up front, since that's what's
actually useful day to day, with the detailed session history compressed
into a dated appendix at the end rather than dropped. Nothing substantive
was removed in the reorganization, only condensed — see the appendix if
something here seems to be missing context on *why*.

## Guiding rule

No compatibility layer, no `local F = C_Container or _G`, no version
detection. Every function call in the codebase is the one that's correct
for this client and nothing else — a clean break, not a shim. If Forever's
client ever lacks a function this assumes, that's a bug to fix when found,
not a case to defensively code around in advance.

---

## 1. Confirmed facts about this client

- **Interface 16001, version 1.60.01** — Forever has its own separate
  version-numbering scheme, not retail's (confirmed from two independent
  sources: Dan's own TOC, and wowforevertalents.com's "build 1.60.1.70009"
  data attribution on the Warrior talent page).
- **Playable classes: the original nine only.** Death Knight, Evoker, Demon
  Hunter, and Monk do **not** exist in Forever at all (Dan confirmed
  directly) — not "unconfirmed," genuinely absent. Any reference to these
  four anywhere in the codebase is a bug, not a gap to fill in.
- **No Jewelcrafting** — no gems, no sockets, on any item.
- **No Inscription** — no glyphs.
- **No Titan's Grip, for any class.** Not gated, not reworked — the
  mechanic doesn't exist.
- **No Shaman dual-wield at all** — not baseline, not talent-gated, simply
  absent (consistent with Forever's Vanilla-rooted design: Shaman
  dual-wield was a TBC-era addition to begin with). Warriors, Rogues,
  Hunters get ordinary 1H dual-wield unconditionally, no talent required.
- **Itemization is flat percent/flat-number, not WotLK-style rating
  stats.** Confirmed extensively, independently, many times over: real
  item tooltips, talent tooltips, and SixtyUpgrades' own character-stat
  schema all agree on this. Gear says "Improves your chance to hit by
  N%," never "+N Hit Rating."
- **Item IDs appear to be a mix** — low, classic-style IDs for items that
  are also in Classic (e.g. Blackened Defias Boots, 10402) alongside
  higher, fresher-looking ranges for Forever's own new items. Inference
  from one real character's gear list, not independently confirmed at
  scale.
- **Enchants exist** (including armor kits); confirmed from a real
  Forever character's gear.
- **Talents are 51 points, 3 trees, 5-points-per-row gating** — the
  classic *shape* — but **read through the modern node-based
  `C_ClassTalents`/`C_Traits` API**, addressed by spellID/name, never by
  `(tab, index)`. Confirmed via live testing (`TopFit:GetRetailTalentRanks`
  actually works), not inferred.

---

## 2. Confirmed API surface — what to use, what's gone

Every item below was independently confirmed on this client, either by
direct testing or by hitting the actual failure in-game. Where something
below contradicts what you'd expect from general WoW addon knowledge,
trust this list over intuition — several entries here were genuine
surprises.

**Use these:**

| Purpose | Function |
|---|---|
| Bags/containers | `C_Container.GetContainerItemLink/GetContainerNumSlots/PickupContainerItem` |
| Item info | `C_Item.GetItemInfo` (the bare global **does not exist at all** — confirmed via an in-game crash, not just "changed shape") |
| Item gems | `C_Item.GetItemGem` (harmless no-op everywhere — no gems exist) |
| Equippable check | `C_Item.IsEquippableItem` (bare global removed in patch 10.2.6) |
| Glyph spell info | `C_Spell.GetSpellInfo(id)` → one table (bare `GetSpellInfo` removed in patch 11.0.0) |
| Equipment sets | `C_EquipmentSet.*` — see the dedicated note below, several gotchas here |
| Talents | `C_ClassTalents.GetActiveConfigID()` + `C_Traits.GetConfigInfo/GetTreeNodes/GetNodeInfo/GetEntryInfo/GetDefinitionInfo` |
| Options panel | `Settings.RegisterCanvasLayoutCategory` + `Settings.RegisterAddOnCategory` + `Settings.OpenToCategory` |

**Confirmed gone, don't reach for these even out of habit:** `GetSpellInfo`
(bare), `IsEquippableItem` (bare), `GetItemInfo` (bare), `InterfaceOptions_
AddCategory`, `InterfaceOptionsFrame_OpenToCategory`,
`InterfaceOptionsFramePanelContainer` (as a frame parent),
`RenameEquipmentSet`, `GetEquipmentSetInfoByName`, `C_EquipmentSet.
UnpackLocation`, and the old bare `EquipmentManager_UnpackLocation` — none
of these exist on this client.

**`CreateFrame` needs an explicit `"BackdropTemplate"` inherit** for
`:SetBackdrop()`/backdrop methods to exist on the resulting frame at all —
confirmed from Dan's own frame-creation fixes (ProgressFrame, the virtual-
items scroll frame). Backdrop methods were removed from the base Frame
type on modern clients; any new `CreateFrame("Frame", ...)` call that
will use `:SetBackdrop()` needs `"BackdropTemplate"` as its template
argument.

**StaticPopup dialog frames use PascalCase field names**, not the old
lowercase convention — `self.EditBox`, not `self.editBox` (confirmed via
an in-game crash in the SimC export/Pawn import dialogs). Part of the same
UI modernization as the Settings namespace and the BackdropTemplate
requirement above. If a custom StaticPopup dialog ever errors with
"attempt to index field 'X' (a nil value)" from inside an OnShow/OnAccept
handler, check the field's capitalization first.

### Equipment sets — the gotchas

`C_EquipmentSet` has 23 real documented functions (confirmed against an
authoritative list); the module everything routes through is
`TopFit:SaveGearToEquipmentSet` (`core.lua`), also reachable directly via
`/topfit saveset [name]` for testing without a full calculation.

- **`GetEquipmentSetID` can legitimately return `0` as a real, valid set
  ID** — this is *not* a "not found" sentinel on this client (the
  documented contract elsewhere says it should return `nil`, but this
  client hands out `0` as a genuine first ID). Don't special-case `0` as
  "doesn't exist" — this was tried, caused real failures, and was
  reverted. `TopFit:GetEquipmentSetIDSafe` is now a plain passthrough,
  kept only so this reasoning stays documented in one place.
- **`IgnoreSlotForSave`/`ClearIgnoredSlotsForSave` do exist** — an early
  FIXME in this codebase doubted this; it was wrong. Per-slot exclusion
  from a saved set works as expected.
- **`CreateEquipmentSet`'s icon argument wants a numeric fileID**, not a
  `"Interface\\Icons\\..."` path string — `GetDefaultEquipmentSetIcon()`
  reads one off the player's own gear.
- **`UnpackLocation` doesn't exist**, confirmed, neither the
  `C_EquipmentSet` nor the old bare-global form. The set-preview
  reconstruction (`frame.lua`) doesn't depend on it as a primary path —
  it tries the currently-equipped slot (exact itemID match, full enchant
  fidelity), then the legacy unpack (a safe no-op), then a full bag scan,
  then a bare-itemID link as a last resort.
- **Equipment sets are confirmed working end-to-end** as of 2026-09-27 —
  both the original save failure and the "forgets contents when switching
  sets" symptom have real, tested fixes behind them, not just
  instrumentation. `PrintAllSets` (part of the same module) auto-dumps
  every set on the character if a create ever silently fails again.

---

## 3. Stat key taxonomy

TopFit's internal stat keys fall into three groups. When adding anything
new, match the right group rather than guessing.

**Real Blizzard `GetItemStats()` keys, still in use** (ratings were
removed where Forever doesn't use them — see below):
`ITEM_MOD_STRENGTH/AGILITY/INTELLECT/SPIRIT/STAMINA_SHORT`,
`ITEM_MOD_ATTACK_POWER_SHORT`, `ITEM_MOD_RANGED_ATTACK_POWER_SHORT`,
`ITEM_MOD_FERAL_ATTACK_POWER_SHORT`, `ITEM_MOD_SPELL_PENETRATION_SHORT`,
`ITEM_MOD_MANA_REGENERATION_SHORT`, `ITEM_MOD_HEALTH/MANA_SHORT`,
`ITEM_MOD_HEALTH_REGENERATION_SHORT`, `ITEM_MOD_BLOCK_VALUE_SHORT` (a flat
amount, not a chance stat — kept), `RESISTANCE0-6_NAME`,
`ITEM_MOD_DAMAGE_PER_SECOND_SHORT`. **Not independently confirmed that the
exact key names match on real Forever gear** — expected to, based on
these being basic numeric stats, but no `GetItemStats()` dump against a
real item has been done yet.

**`ITEM_MOD_*_RATING_SHORT`/similar removed entirely** (Dan: "convert
ratings to percentages except weapon/defense skill"), since Forever
doesn't itemize these as ratings at all: `HIT_RATING`, `CRIT_RATING`,
`EXPERTISE_RATING`, `BLOCK_RATING`, `DODGE_RATING`, `PARRY_RATING`,
`DEFENSE_SKILL_RATING` (→ `TOPFIT_DEFENSE_FLAT`, per the weapon/defense
skill exception), `ARMOR_PENETRATION_RATING`, `RESILIENCE_RATING`,
`HASTE_RATING`, `SPELL_POWER` (unified rating, replaced by the split
damage/healing flat stats below). `import.lua`'s Pawn-import path drops
all of these on import too (no valid rating→percent conversion exists for
this client) — **except Defense Rating**, which has a real, documented,
*unimplemented* conversion sitting in `presets.lua`
(`DEFENSE_RATING_TO_SKILL = 1.5` at level 60) if anyone wants to wire it
up later.

**TopFit's own `TOPFIT_*` pseudo-stats** (no Blizzard itemMod key exists
for these — extracted from tooltip text by `procparser.lua`):

| Key | Source confidence |
|---|---|
| `TOPFIT_HIT_CHANCE_ALL`, `TOPFIT_CRIT_CHANCE_ALL` | Confirmed on real gear |
| `TOPFIT_DODGE_PARRY_REDUCTION` | Confirmed on real gear |
| `TOPFIT_SPELL_DAMAGE_FLAT`, `TOPFIT_SPELL_HEALING_FLAT` | Confirmed on real gear (both split and combined-line forms) |
| `TOPFIT_ARCANE/FIRE/FROST/HOLY/NATURE/SHADOW_DAMAGE_FLAT` | Confirmed on real gear, per-school |
| `TOPFIT_DEFENSE_FLAT`, `TOPFIT_WEAPON_SKILL_<TYPE>` | Confirmed on real gear (flat `Increased X +N` form) |
| `TOPFIT_WEAPON_SPEED` | Pre-existing, stable |
| `TOPFIT_CRIT_CHANCE_MELEE/RANGED/SPELL`, `TOPFIT_HIT_CHANCE_SPELL`, `TOPFIT_CRIT_CHANCE_PHYSICAL`, `TOPFIT_DODGE_CHANCE_ALL` | Confirmed via real **talent** text, not yet seen on an item |
| `TOPFIT_PARRY_CHANCE_ALL`, `TOPFIT_DODGE_CHANCE_ALL`, `TOPFIT_BLOCK_CHANCE_ALL` | **Confirmed on real gear 2026-10-10**: "Increases your chance to Parry an attack by N%." / "...to Dodge an attack by N%." / "...to Block attacks with a shield by N%." (Stronghold Gauntlets, Arena Grand Master, Quillord Mail Leggings). The older talent-derived patterns ("increases your parry chance by") never matched an item and are kept as fallbacks only |
| `TOPFIT_HASTE_PERCENT` | **Confirmed on real gear 2026-10-10**, one combined line: "Increases your attack speed and casting speed by N%." (Dawnstalker Belt). No split melee/spell variants seen yet |
| `ITEM_MOD_BLOCK_VALUE_SHORT` (item text) | "Increases the Block Value of your shield by N." (Bonepile Gaze) is now parsed from text too, by assignment, so it can't double up with `GetItemStats()`. The shield's base "N Block" line is not matched |
| `TOPFIT_ARMOR_PENETRATION_PERCENT`, `TOPFIT_RESILIENCE_PERCENT` | **No confirmed source at all**, neither item nor talent — exist so a weight can be assigned once real phrasing turns up, nothing populates them yet. `/topfit unrecognized` logs any unknown `GetItemStats()` key or unmatched `Equip:` line seen during scans, so the first real ArP/resilience item will surface there |

---

## 4. Talent system

Two separate tables in `talentbonuses.lua`, both consumed automatically
during scoring:

- **`TopFit.talentRatingBonuses`** — flat/percent stat bonuses a talent
  grants directly. **All nine real classes covered.** Every entry traces
  to a specific source (wowforevertalents.com, mostly client-data-sourced
  via wago.tools — high confidence; Shaman's original two entries were
  footage-sourced but independently re-confirmed later). No numeric
  spellIDs from the scraped sources — name-match only — except Hunter's
  Lethal Attacks, which got a real spellID (19426) from Dan's own live
  character export. Consumed by `TopFit:GetTalentRatingBonuses`
  (`calculation.lua`), which feeds `GetEffectiveCapValue`.
- **`TopFit.talentStatConversions`** — talents that make one stat partly
  count as a *different* stat (Hunter/Enhancement Shaman's Intellect
  becoming Attack Power is the prompting example). Five real entries:
  Hunter's Careful Aim, Shaman's Mental Dexterity and Mental Quickness,
  Paladin's Champion of the Light, Priest's Spiritual Guidance. Supports
  both evenly-scaling (`percentPerRank`) and non-uniform
  (`ranks = {[rank] = percent}`) progressions — Priest's Spiritual
  Guidance damage component genuinely does not scale evenly (1/3/5/6/8%
  across 5 ranks), confirmed by checking every rank individually rather
  than assuming from rank 1. Consumed by `TopFit:GetEffectiveWeights`
  (`calculation.lua`), wired into `inventory.lua`'s `CalculateItemScore`.

**Deliberately excluded from both tables**, with reasons kept in each
file's own comments rather than silently dropped: pet-only stats,
procs/temporary buffs, Druid's form-locked talents, single-named-spell
bonuses, weapon-type-conditional multi-effects, damage/healing
multipliers, and stats that multiply themselves rather than converting
into something else (Priest's Mental Strength) or convert into something
this addon doesn't score (Mage's Arcane Resilience → Armor).

**Still open**: the "talent config may not be loaded" warning has been
observed firing on every calculation, not just the expected one-time case
before the Talent panel's first opened this session. Not yet
investigated — worth checking whether it clears up after confirming the
Talent panel has actually been opened; if it persists, that's a real bug
in `GetRetailTalentRanks`/`GetActiveConfigID()` worth its own look.

---

## 5. EP presets and sim export targets

- **Triumvirate (the old `simc-triumvirate` project) is cancelled
  entirely.**
- **One real preset exists**: Hunter, in `presets.lua`, built from Dan's
  own live SixtyUpgrades export (`sixtyupgrades.com/forever/...`). Two
  mapping judgment calls flagged in its own comment: `crit` mapped to
  `TOPFIT_CRIT_CHANCE_PHYSICAL` rather than independently re-confirmed,
  and `rangedSpeed: 100` kept at face value despite being an order of
  magnitude larger than every other number in the same export — possibly
  a different internal scale on SixtyUpgrades' side. No caps included —
  Forever's real cap target percentages aren't confirmed, and a guessed
  number would be worse than none.
- **Remaining 8 classes are paused, not actively being gathered.** Dan is
  waiting for the WowSims Forever branch to go public and will pull
  preset weights from there instead of continuing manual per-character
  SixtyUpgrades exports — those would be properly simulated per spec.
  **Check periodically**: the exporter addon is
  [github.com/wowsims/exporter](https://github.com/wowsims/exporter) (the
  real upstream, not a fork — confirmed 2026-09-27). Checked directly:
  still only `Conditional_Vanilla/TBC/Wrath/Cata/Mists.lua`, no Forever
  file, and none of the 6 open issues mention Forever either. This is the
  same repo whose `ExportStructures/ItemSpec.lua` schema was already
  examined (section 5) — once a Forever branch lands here, it'll be in
  the same already-documented shape.
- **The rest of `presets.lua`** (everything except the one Hunter entry)
  is still 100% old WotLK/Triumvirate rating-based data — wrong class
  model and wrong stat model both. Not rewritten yet; same
  blocked-on-WowSims status as the EP gathering above.
- **Sim export target: community WowSims** (wowsims.com, Go-based), once
  its Forever branch exists — not a custom TopFit-hosted sim. Confirmed
  from reading the actual WowSimsExporter companion addon: plain JSON,
  item schema versioned by an `elseif` chain with no Forever branch yet.
  **SixtyUpgrades already has live Forever support** (confirmed from
  Dan's real export, which has `sixtyupgrades.com/forever/...` links) —
  an earlier note in this doc claiming otherwise was based on a stand-in
  Season of Discovery sample and was wrong; corrected.
- **Real Forever SixtyUpgrades export schema, confirmed**: items as
  `{name, id, slot, enchant: {name, id, spellId}, acquired}`; talents as
  `{name, id, rank, spellId}`; EP weights as `{name, stats: {...}}`; a
  flat-percent stats block with per-school damage fields. One or two more
  class exports (ideally a caster) would be useful to cross-check field-
  name consistency, but this is now lower priority given the WowSims-first
  pivot for actual preset weights.

---

## 6. Outstanding items

Genuinely open, pulled together in one place:

- [ ] `WOW_PROJECT_ID` (`/dump WOW_PROJECT_ID`) — low priority now that
      the interface number is confirmed via the TOC directly and nothing
      currently depends on this value
- [ ] `GetItemStats()` key names on a few real Forever items — expected
      to match, not independently confirmed
- [x] Item-tooltip phrasing for parry/block/dodge chance and haste —
      confirmed from real gear and implemented 2026-10-10 (section 3)
- [ ] Item-tooltip phrasing for armor penetration/resilience — still no
      source; no such item seen yet. Run `/topfit unrecognized` after a
      full scan; `/topfit itemdump <link>` shows one item's raw stats
- [x] **`GetItemStats()` DOES return rating keys on Forever gear**
      (Stronghold Gauntlets: `ITEM_MOD_PARRY_RATING_SHORT = 15`,
      `ITEM_MOD_CRIT_RATING_SHORT = 14`, alongside the parsed 1% lines) —
      resolved 2026-10-10 (Dan: everything on Forever is handled as
      percent numbers, no ratings). `TopFit:StripRatingStats` removes every
      `ITEM_MOD_*_RATING_SHORT` key at scan time, after the discovery log
      has recorded it. Consequence: saved set weights on old rating keys
      now score 0 and must be re-entered on the percent keys (cache
      version 4)
- [ ] "Talent config may not be loaded" warning firing every calculation,
      not just once per session — not yet investigated (section 4)
- [ ] `enchant_ids.lua` — extensively references the now-removed
      `ITEM_MOD_SPELL_POWER_SHORT` and looks like it has the same
      staleness problem `gem_ids.lua` had before its own cleanup (likely
      WotLK-era enchant data that may not match Forever's real enchants)
- [ ] `presets.lua` beyond the one Hunter entry — still fully
      WotLK-rating-based; blocked on the WowSims Forever branch per
      section 5, not an active task right now
- [ ] WowSims Forever branch going public — blocks both the sim-export
      format work and further EP preset gathering; check periodically

**Caution, not a data source**: treat Discord/community "fixes" with the
same skepticism applied to the SavedVariables true/false-vs-1/0 claim
(investigated, found to not match how SavedVariables actually works,
declined). Plausible-sounding folk fixes circulate fast in a new beta
community and aren't always right — bring anything that sounds like a
real client behavior change here to check against what TopFit actually
does before acting on it.

---

## 7. UI: the TopFit tab on the character frame

2026-09-28 (Dan, with screenshots): TopFit's character-pane toggle button
(`TopFit_toggleProgressFrameButton`, anchored next to the native
PaperDoll sidebar tabs) was overlapping the Pet tab. Confirmed via an
in-game Frame Stack dump: the anchor logic only checked
`PaperDollSidebarTab1-3`, hardcoded, and this client has a 4th tab
("Pet") it didn't know existed -- not a positioning math bug, a missing
tab. Fixed by probing `PaperDollSidebarTab1` through `10` for whichever
is the highest-numbered currently-shown one, instead of a hardcoded
count -- won't silently break again if a 5th/6th tab is ever added.

**Implemented, 2026-09-28 — and the shipped version is Dan's, not
mine.** Dan found and supplied the real source (Gethe/wow-ui-source's
`forever` branch: `Interface/AddOns/Blizzard_UIPanels_Game/Camelot/
CharacterFrame.xml` and `.lua` — "Camelot" is Blizzard's internal
codename for this UI, confirmed not Forever-specific via a real retail
bug report hitting the same path). Reading it resolved the original
"no docs, tainting risk" caution:
- `CharacterFrameModeTabs.Tabs` is a plain Lua array (the 6 native tabs
  come from XML `parentArray`); `CHARACTER_MODE_TAB_FRAMES` and
  `CHARACTER_MODE_TAB_ICONS` are hardcoded 6-entry tables, and
  `SetupModeTabs()` (called once, from `OnLoad`) sets each array entry's
  `frameName`/icon from them by index. There is no registration API.
- `CharacterFrameMixin:OnModeTabClicked(tab)` has a dedicated branch for a
  tab with no `frameName`: it just re-checks tabs and returns, never
  calling Blizzard's `ToggleCharacter` dispatcher.

My first attempt appended a 7th tab to that array and hooked
`OnModeTabClicked`. **Dan tested in-game and replaced it** with a simpler
design, now in `TopFit:SetupCharacterModeTab` (`core.lua`, called from
`OnEnable`): a `Button` created from `CharacterFrameModeSideTabTemplate`,
anchored `TOPLEFT` below the last native tab, with its own `OnClick`/
`OnEnter`/`OnLeave`, and **not** inserted into Blizzard's array. That is
the safer design: Blizzard's `SetupModeTabs` (which would blank the icon of
any array entry past index 6), `UpdateTabLayout`, and the gamepad tab
indicators never see it. (The reason it needs to be a `Button` rather than
a `Frame`, as the template is declared in XML, is that `OnClick` isn't
available on plain frames.)

**Possible cosmetic quirk, unconfirmed:** the template's mixin `OnLoad`
wires a left-click handler calling `CharacterFrame:OnModeTabClicked(self)`
on every tab built from it, including this one. For a tab with no
`frameName` that unchecks all six native tabs and sets `selectedTab = 0`
(without changing the pane shown). The only other reader of `selectedTab`
is a gamepad enchanting check, so nothing functional depends on it, but the
active native tab may lose its highlight after clicking TopFit's tab. If
seen, the likely fix is swapping the default handler via the mixin's
`SetCustomOnMouseUpHandler` (unverified whether that replaces or appends —
`SidePanelTabButtonMixin` hasn't been read).

**A regression caught while merging Dan's file:** his version had lost the
three calls that followed the old mode-tab block in `OnInitialize` —
`CreateStatsPlugin()`, `CreateVirtualItemsPlugin()`, and the initial
`collectItems()` — whose only call sites were there. Without them the
Weights & Caps panel and virtual-items plugin are never built. Restored,
and verified by diffing comment-stripped copies: the merged file differs
from Dan's by exactly those three lines. Dan's other changes (leaked
globals `allDone`/`slotItemLink` made local, an unused `itemTable` local
removed) were kept. His file also had its comments stripped wholesale
(12 comment lines vs 224); the merge kept the commented version, since
those comments carry the API lessons — easy to swap back if intended.

---

## Appendix: condensed session history

For provenance only — the sections above are the actual reference.
Dated, one entry per real finding or fix, compressed from the original
play-by-play.

- **09-16**: `C_Container`/`C_Item` rewritten directly, no fallback.
  Async-safe item info handling added. `procparser.lua`'s proc-vs-passive
  misclassification fixed. Built a duplicate Pawn-import module by
  mistake before noticing `import.lua` already had one — removed the
  duplicate, extended the real one instead. `C_EquipmentSet` rewrite
  done. TOC interface bumped `30300` → `120105` (later corrected, see
  09-27 below).
- **09-17**: Read BujuArena/AutoGear and generalwrex/wowsimsexporter (two
  real addons) for reference, confirming the pre-MoP talent-tab model and
  anything MoP-onward are genuinely unrelated systems with no shim between
  them. Dan confirmed Titan's Grip and Shaman dual-wield don't exist in
  Forever — removed the dead talent-coordinate lookups and the two
  override checkboxes that existed only because of the old talent gating.
  Crash-hardened every talent call site with safe wrappers ahead of beta
  (later superseded once the real `C_ClassTalents`/`C_Traits` path was
  confirmed working, section 4).
- **09-18**: Four separate load-time crashes found and fixed via in-game
  error reports in one session: a load-order bug in `core.lua` (my own
  mistake — a block referenced `TopFit` before it existed), the same
  `InterfaceOptions_*` problem in a bundled third-party library
  (`tekKonfig`) that earlier sweeps had skipped, `IsEquippableItem`
  (removed in patch 10.2.6, not previously flagged anywhere), and a
  bundling defect in `tekKonfig.xml`'s own `LibStub.lua` reference.
- **09-26**: Dan's own repo had independently solved the talent-API
  question (confirmed `C_ClassTalents`/`C_Traits` works) and added Evoker/
  Demon Hunter/Monk entries that turned out to be wrong — removed once
  Dan confirmed those classes don't exist. Full 9-class talent data
  gathered (Warrior from a client-data-sourced page, the other 8 from a
  zip Dan provided). Confirmed no Jewelcrafting/Inscription exist —
  `gem_ids.lua` cleared, glyph-reading code removed. `talentbonuses.lua`
  fully rewritten for the new spellID/name-keyed, percent-based model.
- **09-27**: Extremely active day — in order: bare `GetItemInfo` found
  completely absent (crash-confirmed); real gear screenshots closed out
  the itemization phrase-pattern checklist item and added per-school
  damage stats; equipment-set saving rewritten into one verifiable
  routine with a test command; the "forgets contents on set switch" bug
  traced to `UnpackLocation` not existing at all, fixed with an
  independent fallback chain; a suspected `GetEquipmentSetID`-returns-0
  bug was tried, found to be wrong (0 is a real valid ID on this client),
  and reverted — logged as a lesson rather than erased; stat list
  condensed per Dan's request (ratings → percentages except weapon/
  defense skill, removing ~10 dead rating stats and fixing the Pawn-
  import paths to match); stat-conversion talents (Int→AP etc.)
  implemented as a new mechanism; the first real EP preset (Hunter)
  built from a live export; a sandbox filesystem reset required restoring
  the working directory and reinstalling the Lua syntax checker (uploads
  survive this, confirmed, the working directory does not); repo resynced
  against Dan's actual upload (new CI/CD packaging infra adopted, doc
  merge-kept this session's newer copy); interface number corrected from
  an initial misreading (`160001`) to the real value (`16001`) after
  Dan's correction. EP-preset gathering strategy pivoted to wait for the
  WowSims Forever branch rather than continue manual per-spec gathering.
- **09-28**: Character-pane button overlapped the native "Pet" tab
  (anchor logic only knew about 3 sidebar tabs, not 4) — fixed, then
  superseded by a real tab built from Blizzard's own `CharacterFrame`
  source, which Dan located; the version Dan tested in-game is what's
  shipped (section 7). Merging his file caught three dropped
  `OnInitialize` calls (plugin construction and initial item collection),
  restored. StaticPopup dialogs found to use PascalCase fields
  (`self.EditBox`), fixed in `import.lua`. Checked the upstream
  wowsims/exporter repo again: still no Forever branch. Plan doc reorganized
  from a 1450-line chronological log into a current-state reference.
- **10-10**: Item-side parry/dodge/block chance, combined haste and shield block value patterns added from real tooltips (previously unscored); item cache version 2→3 so existing scans refresh; `/topfit unrecognized` discovery log and `/topfit itemdump` added. Found `GetItemStats()` still returns rating keys (see section 6).
- **10-10 (later)**: Rating keys from `GetItemStats()` stripped at scan time; cache version 3→4.
