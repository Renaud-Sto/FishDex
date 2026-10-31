-- Which game sound plays for each announce: a first catch and each shiny grade. The player
-- picks them in the sound window (UI/SoundPicker.lua). A sound is a SOUNDKIT key, or
-- "file:<id>" for a game sound file of the selection (SoundList.lua); never a file of
-- our own. A SOUNDKIT choice the client does not know falls back to the defaults.
local _, ns = ...

local Sounds = {}
ns.Sounds = Sounds

Sounds.TARGETS = { "new", "rare", "epic", "legendary" }

-- Picked by renaud in game (2026-10-31), then fallbacks: the first one that plays wins
-- (a file this client lacks does not play, see Sounds.playFor).
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

-- A file of the selection is always offered (the client cannot tell whether it has it);
-- a SOUNDKIT key only when this client defines it.
local function valid(soundkit, key)
    local id = fileID(key)
    if id then return byFile[id] ~= nil end
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

-- "UI_LEGENDARY_LOOT_TOAST" -> "Legendary loot toast"; a file -> "Group: its name".
function Sounds.label(key)
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

-- Plays a sound; returns true when the client says it will play (PlaySound and
-- PlaySoundFile answer willPlay: false for a file this client does not have).
function Sounds.play(key)
    if not valid(SOUNDKIT, key) then return false end
    local id = fileID(key)
    local ok, willPlay
    if id then
        if type(PlaySoundFile) ~= "function" then return false end
        ok, willPlay = pcall(PlaySoundFile, id, "Master")
    else
        if type(PlaySound) ~= "function" then return false end
        ok, willPlay = pcall(PlaySound, SOUNDKIT[key], "Master")
    end
    return ok and willPlay ~= false
end

-- The player's choice, else the defaults in order, until one plays: an announce is never
-- silent because a sound is missing from this client (Forever may lack recent files).
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
