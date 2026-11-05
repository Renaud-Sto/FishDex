# FishDex

A fishing collection for WoW Forever: every fish, rare fish, trophy, wreck and item you can fish, in a collection window like the game's own. Caught entries show their zones and the recipes that use them; the others stay dark with only where to fish them. A first catch is announced on screen, with an optional sound.

- `/fishdex` (or `/peche`): open or close the window. `/fishdex son`, `/fishdex annonce`: toggle the sound and the announce.
- The "Options..." button opens the options: a Fishing tab (sound, announce, guild sharing, lure button; auto loot of fishing loot, friendly NPC names hidden and louder sounds while fishing, double-click to cast with its delay, while mounted, recast) and a Sounds tab (the sound of each announce). Game settings changed while fishing go back 10 s after the last cast, at logout, and at the next login after a crash.
- Only fishing loot counts (the loot window must be fishing loot); catches are saved per account in `FishDexDB`.
- Data: `tools/build_data.py` builds `FishDex/Data.lua` from Wowhead Classic (zone "Fishing" tabs, item "Reagent for" tabs), cached in `.cache/`. Fished items missing from the data land in the "Discoveries" tab.
- Checks: `sh tests/check.sh` (LuaJIT tests + luacheck, zero warnings).

- Release notes: `CHANGELOG.md`; CurseForge texts and checklist: `docs/curseforge/`; zip: `python tools/build_zip.py` (dist/FishDex-<version>.zip). MIT license.
