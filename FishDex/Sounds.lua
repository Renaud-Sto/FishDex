-- Which game sound plays for each announce: a first catch and each shiny grade. The player
-- picks them in the sound window (UI/SoundPicker.lua); a choice the client does not know
-- falls back to the defaults. Sounds are SOUNDKIT keys, never sound files of our own.
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

-- Words of the sounds listed when the search box is empty: the ones that sound like a reward.
Sounds.REWARD_WORDS = { "TOAST", "FANFARE", "ACHIEVEMENT", "REWARD", "LOOT", "LEVEL", "COMPLETE",
    "CHEER", "LEGENDARY", "EPIC", "TREASURE", "UNLOCK", "COLLECTION", "SPARKLE", "CHIME" }

local function valid(soundkit, key)
    return type(key) == "string" and type(soundkit) == "table" and type(soundkit[key]) == "number"
end

-- SOUNDKIT key that plays for `target`, or nil when the client has none of them.
function Sounds.keyFor(db, target, soundkit)
    local chosen = db.settings.sounds[target]
    if valid(soundkit, chosen) then return chosen end
    for _, key in ipairs(Sounds.DEFAULTS[target] or {}) do
        if valid(soundkit, key) then return key end
    end
    return nil
end

-- Sorted SOUNDKIT keys containing `text` (any case); reward-like keys when text is empty.
function Sounds.filter(soundkit, text)
    local out = {}
    if type(soundkit) ~= "table" then return out end
    local words = Sounds.REWARD_WORDS
    if type(text) == "string" and text:match("%S") then words = { text:upper():match("^%s*(.-)%s*$") } end
    for key, id in pairs(soundkit) do
        if type(key) == "string" and type(id) == "number" then
            for _, w in ipairs(words) do
                if key:find(w, 1, true) then
                    out[#out + 1] = key
                    break
                end
            end
        end
    end
    table.sort(out)
    return out
end

-- "UI_LEGENDARY_LOOT_TOAST" -> "Legendary loot toast": readable, still unique enough.
function Sounds.label(key)
    local text = key:gsub("^UI_", ""):gsub("_", " "):lower()
    return text:sub(1, 1):upper() .. text:sub(2)
end

function Sounds.play(key)
    if type(PlaySound) ~= "function" or not valid(SOUNDKIT, key) then return end
    pcall(PlaySound, SOUNDKIT[key], "Master")
end

function Sounds.playFor(target)
    Sounds.play(Sounds.keyFor(ns.Main.db, target, SOUNDKIT))
end
