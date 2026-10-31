-- Which game sound plays for each announce: a first catch and each shiny grade. The player
-- picks them in the sound window (UI/SoundPicker.lua). A sound is a SOUNDKIT key, or
-- "file:<id>" for a game sound file of the selection (SoundList.lua); never a file of
-- our own. A SOUNDKIT choice the client does not know falls back to the defaults.
local _, ns = ...

local Sounds = {}
ns.Sounds = Sounds

Sounds.TARGETS = { "new", "rare", "epic", "legendary" }

-- First key this client has wins.
Sounds.DEFAULTS = {
    new = { "UI_EPICLOOT_TOAST", "RAID_WARNING" },
    rare = { "UI_RAID_LOOT_TOAST_LESSER_ITEM_WON", "READY_CHECK" },
    epic = { "UI_GARRISON_TOAST_MISSION_COMPLETE", "ACHIEVEMENT_MENU_OPEN" },
    legendary = { "UI_LEGENDARY_LOOT_TOAST", "UI_EPICLOOT_TOAST" },
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

function Sounds.play(key)
    if not valid(SOUNDKIT, key) then return end
    local id = fileID(key)
    if id then
        if type(PlaySoundFile) == "function" then pcall(PlaySoundFile, id, "Master") end
    elseif type(PlaySound) == "function" then
        pcall(PlaySound, SOUNDKIT[key], "Master")
    end
end

function Sounds.playFor(target)
    Sounds.play(Sounds.keyFor(ns.Main.db, target, SOUNDKIT))
end
