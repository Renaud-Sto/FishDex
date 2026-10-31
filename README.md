# FishDex

A fishing collection for WoW Forever: every fish, rare fish, trophy, wreck and item you can fish, in a window laid out like a pokédex. Caught entries show their zones and the recipes that use them; the others stay dark with only where to fish them. A first catch is announced on screen, with an optional sound.

- `/fishdex` (or `/peche`): open or close the window. `/fishdex son`, `/fishdex annonce`: toggle the sound and the announce.
- Only fishing loot counts (the loot window must be fishing loot); catches are saved per account in `FishDexDB`.
- Data: `tools/build_data.py` builds `FishDex/Data.lua` from Wowhead Classic (zone "Fishing" tabs, item "Reagent for" tabs), cached in `.cache/`. Fished items missing from the data land in the "Discoveries" tab.
- Checks: `sh tests/check.sh` (LuaJIT tests + luacheck, zero warnings).
