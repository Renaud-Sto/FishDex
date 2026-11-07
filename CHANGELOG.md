# Changelog

All notable changes to FishDex. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions: [SemVer](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-11-07

### Added
- Fishing key (Options > Fishing, or Key Bindings > FishDex): one key casts Fishing, reels the bobber in once it is
  within the game's Interact Key reach, then takes the loot. Every press is yours; the key only
  works with a fishing pole equipped, and changes only out of combat. While you fish, the
  Interact Key is turned on for the keyboard with a 30 yd reach, then put back.
- Your Interact Key fishes too (option, on by default), and keeps its own job while an NPC or
  an object is its target.
- The double click reels the bobber in too, without aiming, once it is in the Interact Key's
  reach.
- Options: a "Cast and reel in" section that says how it works, and a tooltip on every
  fishing option.

### Removed
- The "Also while mounted" and "Recast while the bobber is out" options: the double click and
  the keys never cast while mounted or while the bobber is out (a second cast loses the fish).

## [1.0.0] - 2026-11-05

First public release, tested on WoW Forever build 1.60.1.70790 (Interface 16001), English client.

### Added
- A collection window of everything you can fish: fish, quest fish, trophies, wrecks and
  chests, items. Caught entries show where to fish them and the recipes that use them (known,
  unknown, or not scanned yet); the others stay dark with only their zones. Fished items
  missing from the list land in a "Discoveries" tab.
- Only fishing loot counts (never an item bought or looted from a mob). Catches are saved per
  account.
- On-screen announce of a first catch, with a sound you can pick.
- Shiny catches: a cosmetic roll on every fish (rare 2 %, epic 0.5 %, legendary 0.05 %), with
  their own tab, colour, announce and sound.
- Guild ranking tab: total fished and shinies of the guild members who use FishDex, one line per
  account (its characters in the tooltip). Small messages, sent after you stop fishing.
- Lure button while a fishing pole is equipped: click to apply, hover to choose another lure.
- Options window: sound, announce, guild sharing, lure button; auto loot of fishing loot;
  friendly NPC names hidden and louder sounds while fishing (put back 10 s after the last
  cast, at logout, and at the next login after a crash); double-click to cast with its delay,
  mouse button, while mounted, and recast while the bobber is out; a Sounds tab to pick the
  sound of each announce (game sounds, or sounds shared by other addons).
- Minimap button, addon compartment, `/fishdex` (or `/peche`) commands, English and French.

### Known limitations
- The fishing zones come from Classic data: a fish caught somewhere the list does not name still
  counts, the zones list is not updated.

[Unreleased]: https://github.com/Renaud-Sto/FishDex/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Renaud-Sto/FishDex/releases/tag/v1.0.0
