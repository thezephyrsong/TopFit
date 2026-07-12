-- Auto-extracted from simc-335-1's sc_unique_gear.cpp (get_equip_encoding / get_hidden_encoding /
-- get_use_encoding). Keyed by TopFit:Slugify(itemName) to match simc's own item-name convention.
--
-- IMPORTANT: item NAMES match Triumvirate's items (same items reused), but the numeric AMOUNT in
-- these encoded strings reflects retail Wrath values, which Triumvirate may have retuned for its
-- level-60 cap. Only the *structure* here (trigger type, proc chance/PPM, duration, cooldown,
-- stacking behavior) should be trusted -- always prefer a tooltip-parsed amount when one is found.
--
-- Encoded string grammar (tokens separated by "_"):
--   [Trigger]_<amount><StatOrSchool>_[chance%|PPM|Stack]_[durDur]_[cdCd]_[tickTick]_[reverse]
-- Trigger e.g. OnAttackHit/OnAttackCrit/OnSpellCast/OnSpellCastHit/OnSpellCastMiss/OnSpellCrit/
-- OnSpellDirectHit/OnSpellDirectCrit/OnSpellDamage/OnSpellTickDamage/OnDamage. Absent for get_use_
-- encoding's simple activated trinkets (no proc trigger -- it's player-activated on its own Cd).
-- "normal"/"heroic" hold separate strings only where Triumvirate might have distinct heroic loot;
-- if only "normal" is present, the same string applies regardless of item quality variant.
TopFit.SimcProcData = {
	["equip"] = {
		["abyssal_rune"] = { normal = "OnSpellCast_590SP_25%_10Dur_45Cd" },
		["ashen_band_of_endless_destruction"] = { normal = "OnSpellCastHit_285SP_10%_10Dur_60Cd" },
		["ashen_band_of_endless_might"] = { normal = "OnAttackHit_480AP_1PPM_10Dur_60Cd" },
		["ashen_band_of_endless_vengeance"] = { normal = "OnAttackHit_480AP_1PPM_10Dur_60Cd" },
		["ashen_band_of_unmatched_destruction"] = { normal = "OnSpellCastHit_285SP_10%_10Dur_60Cd" },
		["ashen_band_of_unmatched_might"] = { normal = "OnAttackHit_480AP_1PPM_10Dur_60Cd" },
		["ashen_band_of_unmatched_vengeance"] = { normal = "OnAttackHit_480AP_1PPM_10Dur_60Cd" },
		["anvil_of_titans"] = { normal = "OnAttackHit_1000AP_10%_10Dur_50Cd" },  -- UNVERIFIED: retail placeholder, not yet confirmed against a Triumvirate tooltip
		["atiesh_greatstaff_of_the_guardian"] = { normal = "OnSpellCast_250SP_15%_20Dur_45Cd" },  -- real proc also grants +135 spell crit rating simultaneously; engine's grammar only supports one stat per proc, crit component omitted
		["bandits_insignia"] = { normal = "OnAttackHit_1880Arcane_15%_45Cd" },
		["blade_of_wizardry"] = { normal = "OnSpellCast_280Haste_10%_6Dur" },  -- UNVERIFIED: retail placeholder, proc chance/ICD not stated on retail tooltip either, assumed 10%/no ICD
		["crusaders_locket"] = { normal = "OnAttackHit_258Expertise_15%_10Dur_45Cd" },  -- UNVERIFIED: retail placeholder
		["dmc_berserker"] = { normal = "OnSpellHit_35Crit_3Stack_50%_12Dur" },  -- UNVERIFIED: retail placeholder; retail trigger is on dealing OR taking a spell hit, engine only supports "dealt" side
		["dmc_death"] = { normal = "OnSpellHit_2000Shadow_15%_45Cd" },  -- UNVERIFIED: retail placeholder, value = midpoint of retail 1750-2250 range
		["dragonmaw"] = { normal = "OnAttackHit_127Haste_10%_10Dur" },  -- CONFIRMED via Triumvirate tooltip
		["dragonstrike"] = { normal = "OnAttackHit_127Haste_10%_10Dur" },  -- CONFIRMED via Triumvirate tooltip + in-game screenshot
		["drakefist_hammer"] = { normal = "OnAttackHit_127Haste_10%_10Dur" },  -- UNVERIFIED: assumed same as dragonmaw/dragonstrike (same weapon family), not yet found in an item scan
		["banner_of_victory"] = { normal = "OnAttackHit_1008AP_20%_10Dur_50Cd" },
		["black_magic"] = { normal = "OnSpellDirectHit_250Haste_35%_10Dur_35Cd" },
		["blood_of_the_old_god"] = { normal = "OnAttackCrit_1284AP_10%_10Dur_50Cd" },
		["bryntroll_the_bone_arbiter"] = { normal = "OnAttackHit_2250Drain_11%", heroic = "OnAttackHit_2538Drain_11%" },
		["charred_twilight_scale"] = { normal = "OnSpellCast_763SP_10%_15Dur_45Cd", heroic = "OnSpellCast_861SP_10%_15Dur_45Cd" },
		["chuchus_tiny_box_of_horrors"] = { normal = "OnAttackHit_258Crit_15%_10Dur_45Cd" },
		["comets_trail"] = { normal = "OnAttackHit_726Haste_10%_10Dur_45Cd" },
		["corens_chromium_coaster"] = { normal = "OnAttackCrit_1000AP_10%_10Dur_50Cd" },
		["dark_matter"] = { normal = "OnAttackHit_612Crit_15%_10Dur_45Cd" },
		["darkglow_embroidery"] = { normal = "OnSpellCast_400Mana_35%_60Cd" },
		["darkmoon_card_crusade"] = { normal = "OnDamage_8SP_10Stack_10Dur" },
		["dislodged_foreign_object"] = { normal = "OnSpellCast_105SP_10Stack_10%_20Dur_45Cd_2Tick", heroic = "OnSpellCast_121SP_10Stack_10%_20Dur_45Cd_2Tick" },
		["dying_curse"] = { normal = "OnSpellCast_765SP_15%_10Dur_45Cd" },
		["elemental_focus_stone"] = { normal = "OnSpellCast_522Haste_10%_10Dur_45Cd" },
		["embrace_of_the_spider"] = { normal = "OnSpellCast_505Haste_10%_10Dur_45Cd" },
		["extract_of_necromantic_power"] = { normal = "OnSpellTickDamage_1050Shadow_10%_15Cd" },
		["eye_of_magtheridon"] = { normal = "OnSpellCastMiss_170SP_10Dur" },
		["eye_of_the_broodmother"] = { normal = "OnSpellDamage_25SP_5Stack_10Dur" },
		["flare_of_the_heavens"] = { normal = "OnSpellCast_850SP_10%_10Dur_45Cd" },
		["flow_of_knowledge"] = { normal = "OnSpellCast_590SP_10%_10Dur_50Cd" },  -- UNVERIFIED: retail placeholder
		["forge_ember"] = { normal = "OnSpellCastHit_115SP_10%_10Dur_45Cd", heroic = "OnSpellCastHit_172SP_10%_10Dur_45Cd" },  -- CONFIRMED via Triumvirate tooltip (mirror file was stale at retail 512)
		["frostforged_champion"] = { normal = "OnAttackHit_480AP_1PPM_10Dur_60Cd" },  -- UNVERIFIED: retail placeholder (PvP resilience trinket)
		["frostforged_sage"] = { normal = "OnSpellHit_285SP_10%_10Dur_60Cd" },  -- UNVERIFIED: retail placeholder (PvP resilience trinket)
		["fury_of_the_five_flights"] = { normal = "OnAttackHit_16AP_20Stack_10Dur" },
		["grim_toll"] = { normal = "OnAttackHit_612ArPen_15%_10Dur_45Cd" },
		["herkuml_war_token"] = { normal = "OnAttackHit_17AP_20Stack_10Dur" },
		["horn_of_agent_fury"] = { normal = "OnAttackHit_1280Holy_15%_45Cd" },  -- UNVERIFIED: retail placeholder, value = midpoint of retail 1024-1536 range
		["jetzes_bell"] = { normal = "OnSpellCast_125MP5_10%_15Dur_50Cd" },  -- UNVERIFIED: retail placeholder
		["jousters_fury_alliance"] = { normal = "OnAttackHit_328Crit_10%_10Dur_50Cd" },  -- UNVERIFIED: retail placeholder
		["jousters_fury_horde"] = { normal = "OnAttackHit_328Crit_10%_10Dur_50Cd" },  -- UNVERIFIED: retail placeholder
		["illustration_of_the_dragon_soul"] = { normal = "OnSpellCast_20SP_10Stack_10Dur" },
		["lightning_capacitor"] = { normal = "OnSpellDirectCrit_750Nature_3Stack_2.5Cd" },
		["lightweave"] = { normal = "OnSpellCast_295SP_35%_15Dur_60Cd" },
		["lightweave_embroidery"] = { normal = "OnSpellCast_295SP_35%_15Dur_60Cd" },
		["lionheart_executioner"] = { normal = "OnAttackHit_70Str_10%_10Dur" },  -- CONFIRMED via Triumvirate tooltip; flat +8% Fear resist is a separate base "Equip:" stat, not part of this proc
		["madness_of_the_betrayer"] = { normal = "OnAttackHit_300ArPen_10%_10Dur" },  -- UNVERIFIED: retail placeholder
		["mark_of_defiance"] = { normal = "OnSpellCastHit_150Mana_15%_15Cd" },
		["meteorite_whetstone"] = { normal = "OnAttackHit_170Haste_15%_10Dur_45Cd", heroic = "OnAttackHit_177Haste_15%_10Dur_45Cd" },  -- CONFIRMED via Triumvirate tooltip, both tiers; flat crit rating (18/25) is base item stat, not a proc
		["mirror_of_truth"] = { normal = "OnAttackCrit_1000AP_10%_10Dur_50Cd" },
		["mithril_pocketwatch"] = { normal = "OnSpellCast_590SP_10%_10Dur_45Cd" },
		["mjolnir_runestone"] = { normal = "OnAttackHit_665ArPen_15%_10Dur_45Cd" },
		["muradins_spyglass"] = { normal = "OnSpellDamage_18SP_10Stack_10Dur", heroic = "OnSpellDamage_20SP_10Stack_10Dur" },
		["needleencrusted_scorpion"] = { normal = "OnAttackCrit_678ArPen_10%_10Dur_50Cd" },
		["pandoras_plea"] = { normal = "OnSpellCast_751SP_10%_10Dur_45Cd" },
		["pendulum_of_telluric_currents"] = { normal = "OnSpellHit_673Shadow_15%_45Cd", heroic = "OnSpellHit_700Shadow_15%_45Cd" },  -- CONFIRMED via Triumvirate tooltip, both tiers
		["phylactery_of_the_nameless_lich"] = { normal = "OnSpellTickDamage_1073SP_30%_20Dur_100Cd", heroic = "OnSpellTickDamage_1206SP_30%_20Dur_100Cd" },
		["purified_lunar_dust"] = { normal = "OnSpellCast_304MP5_10%_15Dur_45Cd" },
		["pyrite_infuser"] = { normal = "OnAttackCrit_1234AP_10%_10Dur_50Cd" },
		["quagmirrans_eye"] = { normal = "OnSpellCast_192Haste_10%_6Dur_45Cd", heroic = "OnSpellCast_215Haste_10%_6Dur_45Cd" },  -- CONFIRMED via Triumvirate tooltip, both tiers (mirror file was stale at retail 320)
		["reign_of_the_dead"] = { normal = "OnSpellDirectCrit_1882Fire_3Stack_2.0Cd", heroic = "OnSpellDirectCrit_2117Fire_3Stack_2.0Cd" },
		["reign_of_the_unliving"] = { normal = "OnSpellDirectCrit_1882Fire_3Stack_2.0Cd", heroic = "OnSpellDirectCrit_2117Fire_3Stack_2.0Cd" },
		["robe_of_the_elder_scribes"] = { normal = "OnSpellCast_130SP_10%_10Dur" },  -- CONFIRMED via wowsims tooltip text; proc chance/ICD not stated on tooltip either, assumed 10%/no ICD
		["rune_of_razorice"] = { normal = "custom" },
		["rune_of_the_fallen_crusader"] = { normal = "custom" },
		["sextant_of_unstable_currents"] = { normal = "OnSpellCrit_190SP_20%_15Dur_45Cd" },
		["shard_of_contempt"] = { normal = "OnAttackHit_165AP_10%_20Dur", heroic = "OnAttackHit_174AP_10%_20Dur" },  -- CONFIRMED via Triumvirate tooltip (was using retail 230 as placeholder); flat +25/+27 expertise rating is base item stat, not a proc; proc % still unstated, assumed 10%
		["sharpened_twilight_scale"] = { normal = "OnAttackHit_1304AP_35%_15Dur_45Cd", heroic = "OnAttackHit_1472AP_35%_15Dur_45Cd" },
		["shiffars_nexus_horn"] = { normal = "OnSpellCrit_135SP_20%_10Dur_45Cd" },  -- CONFIRMED via Triumvirate tooltip (mirror file was stale at 225)
		["show_of_faith"] = { normal = "OnSpellCast_272MP5_10%_15Dur_50Cd" },  -- UNVERIFIED: retail placeholder
		["signet_of_edward_the_odd"] = { normal = "OnAttackHit_62Haste_15%_13Dur_45Cd" },  -- CONFIRMED via Triumvirate tooltip + in-game screenshot (was using retail 125 as placeholder); flat +21 AP, +8 haste rating are base "Equip:" stats, not part of this proc
		["sifs_remembrance"] = { normal = "OnSpellCast_220MP5_10%_15Dur_50Cd" },  -- UNVERIFIED: retail placeholder
		["solace_of_the_defeated"] = { normal = "OnSpellCast_16MP5_8Stack_10Dur", heroic = "OnSpellCast_18MP5_8Stack_10Dur" },
		["solace_of_the_fallen"] = { normal = "OnSpellCast_16MP5_8Stack_10Dur", heroic = "OnSpellCast_18MP5_8Stack_10Dur" },
		["sonic_booster"] = { normal = "OnAttackHit_215AP_35%_10Dur_60Cd" },  -- Triumvirate: 215 (down from retail 430); cooldown per tooltip text ("once every minute"), retail code uses 50s ICD
		["soul_of_the_dead"] = { normal = "OnSpellCrit_900Mana_25%_45Cd" },  -- UNVERIFIED: retail placeholder - mana battery on spell crit
		["spark_of_life"] = { normal = "OnSpellCast_105MP5_10%_15Dur_50Cd", heroic = "OnSpellCast_109MP5_10%_15Dur_50Cd" },  -- CONFIRMED via Triumvirate tooltip, both tiers
		["sundial_of_the_exiled"] = { normal = "OnSpellCast_168SP_10%_10Dur_45Cd" },  -- CONFIRMED via Triumvirate tooltip (mirror file was stale at retail 590)
		["swordguard_embroidery"] = { normal = "OnAttackHit_400AP_25%_60Cd" },
		["the_night_blade"] = { normal = "OnAttackHit_62ArPen_3Stack_10%_10Dur" },  -- CONFIRMED via Triumvirate tooltip (was using retail-derived 435 as placeholder, way off)
		["thunder_capacitor"] = { normal = "OnSpellDirectCrit_1276Nature_4Stack_2.5Cd" },
		["timbals_focusing_crystal"] = { normal = "OnSpellTickDamage_283Shadow_10%_45Cd", heroic = "OnSpellTickDamage_297Shadow_10%_45Cd" },  -- FIXED: was slugged "timbals_crystal", which never matches the real item name "Timbal's Focusing Crystal" -- dead code. Values now match tooltip midpoints; school not stated on tooltip, Shadow assumed
		["vestige_of_haldor"] = { normal = "OnAttackHit_656Fire_15%_45Cd" },  -- Triumvirate: 656 (down from retail avg 1280); value = midpoint of tooltip's 550-762 range
		["whispering_fanged_skull"] = { normal = "OnAttackHit_1110AP_35%_15Dur_45Cd", heroic = "OnAttackHit_1250AP_35%_15Dur_45Cd" },
		["wrath_of_cenarius"] = { normal = "OnSpellCastHit_132SP_5%_10Dur" },
	},
	["hidden"] = {
		["darkglow_embroidery"] = { normal = "1spi" },
		["lightweave"] = { normal = "1spi" },
		["lightweave_embroidery"] = { normal = "1spi" },
	},
	["use"] = {
		["binding_light"] = { normal = "OnSpellCast_66SP_8Stack_20Dur_120Cd", heroic = "OnSpellCast_74SP_8Stack_20Dur_120Cd" },  -- UNVERIFIED: retail placeholder, part of same Ulduar hardmode reward chain as fetish/vengeance below
		["binding_stone"] = { normal = "OnSpellCast_66SP_8Stack_20Dur_120Cd", heroic = "OnSpellCast_74SP_8Stack_20Dur_120Cd" },  -- UNVERIFIED: retail placeholder
		["death_knights_anguish"] = { normal = "OnAttackHit_15Crit_10Stack_10%_20Dur_45Cd" },  -- UNVERIFIED: retail placeholder
		["energy_siphon"] = { normal = "408SP_20Dur_120Cd" },
		["ephemeral_snowflake"] = { normal = "464Haste_20Dur_120Cd" },
		["fetish_of_volatile_power"] = { normal = "OnSpellCast_57Haste_8Stack_20Dur_120Cd", heroic = "OnSpellCast_64Haste_8Stack_20Dur_120Cd" },
		["goblin_rocket_launcher"] = { normal = "1200Fire_120Cd" },  -- CONFIRMED via Triumvirate tooltip: 960-1440 dmg range (avg used), 2min CD; 3s stun not modeled (no CC in DPS sim)
		["hand_mounted_pyro_rocket"] = { normal = "1837Fire_45Cd" },
		["hyperspeed_accelerators"] = { normal = "340Haste_12Dur_60Cd" },
		["living_flame"] = { normal = "505SP_20Dur_120Cd" },
		["maghias_misguided_quill"] = { normal = "716SP_20Dur_120Cd" },
		["mark_of_norgannon"] = { normal = "491Haste_20Dur_120Cd" },
		["mark_of_supremacy"] = { normal = "1024AP_20Dur_120Cd" },
		["nevermelting_ice_crystal"] = { normal = "OnSpellDirectCrit_73Crit_5Stack_20Dur_180Cd_reverse" },  -- CONFIRMED via Triumvirate tooltip: 73 per stack, 5 stacks = 365 total (was 184, didn't match tooltip math)
		["platinum_disks_of_battle"] = { normal = "752AP_20Dur_120Cd" },
		["platinum_disks_of_sorcery"] = { normal = "440SP_20Dur_120Cd" },
		["platinum_disks_of_swiftness"] = { normal = "375Haste_20Dur_120Cd" },
		["pyrorocket"] = { normal = "1837Fire_45Cd" },
		["scale_of_fates"] = { normal = "432Haste_20Dur_120Cd" },
		["shard_of_the_crystal_heart"] = { normal = "512Haste_20Dur_120Cd" },
		["sliver_of_pure_ice"] = { normal = "1625Mana_120Cd" },
		["spirit_world_glass"] = { normal = "336Spi_20Dur_120Cd" },
		["talisman_of_resurgence"] = { normal = "599SP_20Dur_120Cd" },
		["talisman_of_volatile_power"] = { normal = "OnSpellCast_57Haste_8Stack_20Dur_120Cd", heroic = "OnSpellCast_64Haste_8Stack_20Dur_120Cd" },
		["the_decapitator"] = { normal = "393Physical_180Cd" },  -- CONFIRMED via Triumvirate tooltip: 373-412 dmg range (avg used), 3min CD; flat +19 crit rating is base item stat, not part of this on-use effect
		["vengeance_of_the_forsaken"] = { normal = "OnAttackHit_215AP_5Stack_20Dur_120Cd", heroic = "OnAttackHit_250AP_5Stack_20Dur_120Cd" },
		["victors_call"] = { normal = "OnAttackHit_215AP_5Stack_20Dur_120Cd", heroic = "OnAttackHit_250AP_5Stack_20Dur_120Cd" },
		["wrathstone"] = { normal = "856AP_20Dur_120Cd" },
	},
}
