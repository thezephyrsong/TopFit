# TopFit developer tools

Scripts that regenerate TopFit's data files from a clone of the WoWSims Forever project. They are not part of the
addon: `.pkgmeta` leaves `tools/` and `update_data.bat` out of release packages.

## Update the data

```
cd <Addons>/TopFit
python tools/update_data.py               # procdata.lua, setdata.lua, talentdata.lua and the sim presets in presets.lua
python tools/update_data.py --only procs  # or: sets, presets, talents
python tools/update_data.py --pull        # git pull the Forever clone first
```

The clone is expected at `<Addons>/Forever`; use `--repo <path>` or the `FOREVER_REPO` environment variable otherwise.
`setdata.lua` needs `tools/database/wowsims.db` in that clone (built with `make db`, see below) or `--db <file>`.

Building `wowsims.db`, from the Forever clone, for your own installed game build:

```
go run ./tools/db2tool -s tools/database/generator-settings.json --output tools/database/wowsims.db --basedir "<WoW folder>"
```

The sim's own `make db` also regenerates `spells_auto_gen.go` and `db.json` from the same build; that needs the
protobuf Go files generated first (`protoc` + `protoc-gen-go`, see that project's `docs/installation.md`).

## Using WoWSims data responsibly

This is a checklist, not legal advice. The WoWSims Forever project is MIT licensed; check its `LICENSE` and README
again whenever you pull, in case the terms change.

1. **Keep the notices.** `THIRD_PARTY_NOTICES.md` (it holds the MIT text and copyright line) ships with the addon.
   Don't remove it, and keep the header that the generators put at the top of each generated file.
2. **Keep the link back.** The authors ask for a user-visible link to <https://github.com/wowsims/forever>. It is in
   `readme.txt` and in the `X-Credits` line of `TopFit.toc`, which the in-game About panel displays. If you add a
   new data source, add it to the same places and to the table in `THIRD_PARTY_NOTICES.md`.
3. **Regenerate, don't copy.** Take data through the scripts, so every file has a documented source and can be
   rebuilt. Don't paste files, tables or code from the WoWSims repositories into TopFit by hand.
4. **Check the license before using any other repository.** `wowsims/gamedata` had no license file when this was
   written, which means no permission to reuse its files. TopFit does not use it; it was only read to compare against.
   Use a data source only if it has a license that allows it, or you have asked the owners.
5. **Don't commit game or client files.** Keep `wowsims.db`, `DBCache.bin`, extracted DB2 files and downloaded CDN
   data out of this repository (the Forever clone already ignores `wowsims.db`). Commit only the generated Lua.
6. **Don't imply endorsement.** Credit the project, but don't present TopFit as made by, affiliated with or endorsed
   by WoWSims or Blizzard Entertainment.
7. **Keep generated data to facts.** IDs, numbers and stat keys. Don't copy item descriptions, flavor text, icons
   or other art from the game or from the sim into the addon.
8. **Record where a build came from.** Generated headers include the Forever clone's commit when it is a git checkout;
   mention the game build (for example 1.60.1.70450) in your commit message when you regenerate.
