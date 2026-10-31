-- Which game sound plays for each announce: a first catch and each shiny grade. The player
-- picks them in the sound window (UI/SoundPicker.lua). A sound is a SOUNDKIT key,
-- "file:<id>" for a game sound file of the selection (SoundList.lua), or "lsm:<name>"
-- for a sound another installed addon shares through LibSharedMedia (played from that
-- addon's folder, never copied). We ship no sound file of our own.
local _, ns = ...

local Sounds = {}
ns.Sounds = Sounds

Sounds.TARGETS = { "new", "rare", "epic", "legendary" }

-- Picked by renaud in game (2026-10-31), then fallbacks (see Sounds.play for their limit).
Sounds.DEFAULTS = {
    new = { "file:1067169", "UI_EPICLOOT_TOAST", "RAID_WARNING" }, -- chest unlocked
    rare = { "file:569143", "READY_CHECK" }, -- achievement
    epic = { "file:1489461", "file:569143", "UI_EPICLOOT_TOAST" }, -- legendary item
    legendary = { "file:775180", "file:567408", "UI_EPICLOOT_TOAST" }, -- brawl won, PvP victory
}

local function fileID(key)
    return type(key) == "string" and tonumber(key:match("^file:(%d+)$")) or nil
end

local byFile = {}
for _, s in ipairs(ns.SoundList) do byFile[s[1]] = s end

-- LibSharedMedia, when another addon brought it; nil otherwise.
local function lsm()
    if type(LibStub) ~= "table" and type(LibStub) ~= "function" then return nil end
    local ok, lib = pcall(LibStub, "LibSharedMedia-3.0", true)
    return ok and type(lib) == "table" and lib or nil
end

local function sharedName(key)
    return type(key) == "string" and key:match("^lsm:(.+)$") or nil
end

-- The path or file id a shared sound plays from, or nil when no addon shares it now.
local function sharedPath(name)
    local lib = lsm()
    if not lib or type(lib.Fetch) ~= "function" then return nil end
    local ok, path = pcall(lib.Fetch, lib, "sound", name, true)
    if ok and (type(path) == "string" or type(path) == "number") and path ~= "" then return path end
    return nil
end

-- A file of the selection is always offered (the client cannot tell whether it has it);
-- a shared sound while an addon shares it; a SOUNDKIT key when this client defines it.
local function valid(soundkit, key)
    local id = fileID(key)
    if id then return byFile[id] ~= nil end
    local name = sharedName(key)
    if name then return sharedPath(name) ~= nil end
    return type(key) == "string" and type(soundkit) == "table" and type(soundkit[key]) == "number"
end

-- Sound key that plays for `target`, or nil when the client has none of them.
function Sounds.keyFor(db, target, soundkit)
    local chosen = db.settings.sounds[target]
    if valid(soundkit, chosen) then return chosen end
    for _, key in ipairs(Sounds.DEFAULTS[target] or {}) do
        if valid(soundkit, key) then return key end
    end
    return nil
end

local function trimmed(text)
    if type(text) ~= "string" then return nil end
    text = text:match("^%s*(.-)%s*$")
    return text ~= "" and text or nil
end

-- Every SOUNDKIT key containing `text` (any case), sorted; all of them when text is empty.
function Sounds.filter(soundkit, text)
    local out = {}
    if type(soundkit) ~= "table" then return out end
    local word = trimmed(text)
    word = word and word:upper()
    for key, id in pairs(soundkit) do
        if type(key) == "string" and type(id) == "number" and (not word or key:find(word, 1, true)) then
            out[#out + 1] = key
        end
    end
    table.sort(out)
    return out
end

-- The selection's sounds whose label contains `text` (any case), in list order.
function Sounds.selection(text)
    local out = {}
    local word = trimmed(text)
    word = word and word:lower()
    for _, s in ipairs(ns.SoundList) do
        local key = "file:" .. s[1]
        if not word or Sounds.label(key):lower():find(word, 1, true) then out[#out + 1] = key end
    end
    return out
end

-- Sounds other addons share (LibSharedMedia), whose name contains `text`, sorted.
-- "None" is LibSharedMedia's silent entry: left out.
function Sounds.shared(text)
    local out = {}
    local lib = lsm()
    if not lib or type(lib.List) ~= "function" then return out end
    local ok, names = pcall(lib.List, lib, "sound")
    if not ok or type(names) ~= "table" then return out end
    local word = trimmed(text)
    word = word and word:lower()
    for _, name in ipairs(names) do
        if type(name) == "string" and name ~= "None" and (not word or name:lower():find(word, 1, true)) then
            out[#out + 1] = "lsm:" .. name
        end
    end
    table.sort(out)
    return out
end

-- "UI_LEGENDARY_LOOT_TOAST" -> "Legendary loot toast"; a file -> "Group: its name";
-- a shared sound -> its name as the sharing addon gave it.
function Sounds.label(key)
    local shared = sharedName(key)
    if shared then return shared end
    local id = fileID(key)
    if id then
        local s = byFile[id]
        if not s then return key end
        local L = ns.L
        local name = L.CAT_fish == ns.LOCALES.frFR.CAT_fish and s[3] or s[2]
        return string.format(L.SOUND_GROUP_FORMAT, L["SOUND_GROUP_" .. s[4]] or s[4], name)
    end
    local text = key:gsub("^UI_", ""):gsub("_", " "):lower()
    return text:sub(1, 1):upper() .. text:sub(2)
end

-- Plays a sound; returns the client's willPlay. Measured on Retail 12.1.5 (2026-10-31):
-- PlaySoundFile(1) answered true, so a missing file is NOT caught here; only a choice
-- that is no longer valid (a SOUNDKIT key this client lacks, an uninstalled addon's
-- sound) or a muted call falls through to the next default.
function Sounds.play(key)
    if not valid(SOUNDKIT, key) then return false end
    local id = fileID(key)
    local ok, willPlay
    local name = sharedName(key)
    if name then
        if type(PlaySoundFile) ~= "function" then return false end
        ok, willPlay = pcall(PlaySoundFile, sharedPath(name), "Master")
    elseif id then
        if type(PlaySoundFile) ~= "function" then return false end
        ok, willPlay = pcall(PlaySoundFile, id, "Master")
    else
        if type(PlaySound) ~= "function" then return false end
        ok, willPlay = pcall(PlaySound, SOUNDKIT[key], "Master")
    end
    return ok and willPlay ~= false
end

-- The player's choice, else the defaults in order, until one plays.
function Sounds.playFor(target)
    local tried = {}
    local chosen = ns.Main.db.settings.sounds[target]
    if chosen then
        tried[chosen] = true
        if Sounds.play(chosen) then return chosen end
    end
    for _, key in ipairs(Sounds.DEFAULTS[target] or {}) do
        if not tried[key] then
            tried[key] = true
            if Sounds.play(key) then return key end
        end
    end
    return nil
end
