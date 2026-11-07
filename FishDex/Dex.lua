-- Pure logic of the dex: saved data shape, catches, categories, progress, recipe state.
-- No game call here: every value the game gives comes in as an argument.
local _, ns = ...

local Dex = {}
ns.Dex = Dex

local Data = ns.Data

-- FishDexDB (account wide). catches[itemID] = { count, first = time(), zone = name }.
-- known[character key][recipe spell id] = true, scanned[character key] = true once that
-- character opened a profession window (before that, "unknown" cannot be told apart).
Dex.DEFAULTS = {
    version = 2,
    catches = {},
    shiny = {}, -- shiny[itemID][grade] = { count, first } (Shiny.lua)
    known = {},
    scanned = {},
    -- Guild ranking (Board.lua): id = this account's, forced[grade] = shinytest shinies,
    -- guilds["Guild-Realm"][id] = the last score heard from that account.
    -- chars[name] = last time this account played that character with FishDex.
    board = { id = "", forced = {}, guilds = {}, chars = {} },
    -- sounds[target] = SOUNDKIT key; locale "": the client's; minimap.angle in degrees.
    settings = { sound = true, announce = true, share = true, locale = "", sounds = {},
        minimap = { hide = false, angle = 200 },
        -- lureButton: the lure button while a pole is equipped; lure.id = the lure it offers
        -- (0: the best in the bags), lure.x/y its place; doubleCast: RightButton, LeftButton
        -- or off.
        lureButton = true, lure = { id = 0 }, doubleCast = "RightButton",
        -- The fishing options (Options window, 2026-11-05): castButton = the button the
        -- double click uses when it is on, castDelay its window in seconds; loudVolume 0..1.
        castButton = "RightButton", castDelay = 0.4,
        autoLoot = false, hideNames = false, loudSounds = false, loudVolume = 1,
        -- useInteractKey: the game's Interact Key fishes too (FishKeyButton.lua, 2026-11-07).
        useInteractKey = true,
        -- doubleReel: the double click reels the bobber in (2026-11-07, its own option).
        doubleReel = true },
    -- saved[cvar] = { was, now }: game settings changed while fishing (Fishing.lua).
    fishing = { saved = {} },
}

local byID = {}
for _, e in ipairs(Data.ENTRIES) do byID[e.id] = e end

-- Fills missing keys of `db` from `defaults`, in place; a value of the wrong type is reset.
local function fill(db, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then db[k] = {} end
            fill(db[k], v)
        elseif type(db[k]) ~= type(v) then
            db[k] = v
        end
    end
end

-- Repairs the saved data in place (WoW keeps a reference to the loaded table).
function Dex.repair(db)
    -- Version 1 named the shiny grades shiny / rare / legendary; version 2 names them
    -- rare / epic / legendary (blue, purple, orange). Rename before the version is filled.
    if db.version == 1 and type(db.shiny) == "table" then
        for _, byGrade in pairs(db.shiny) do
            if type(byGrade) == "table" then
                byGrade.epic, byGrade.rare, byGrade.shiny = byGrade.rare, byGrade.shiny, nil
            end
        end
    end
    db.version = Dex.DEFAULTS.version
    fill(db, Dex.DEFAULTS)
    local s = db.settings
    s.castDelay = math.max(0.2, math.min(0.8, s.castDelay))
    s.loudVolume = math.max(0, math.min(1, s.loudVolume))
    if s.castButton ~= "LeftButton" then s.castButton = "RightButton" end
    for id, byGrade in pairs(db.shiny) do
        if type(id) ~= "number" or type(byGrade) ~= "table" then db.shiny[id] = nil end
    end
    -- Drop catch records the addon could not have written.
    for id, c in pairs(db.catches) do
        if type(id) ~= "number" or type(c) ~= "table" then
            db.catches[id] = nil
        elseif type(c.count) ~= "number" or c.count < 1 then
            c.count = 1
        end
    end
    return db
end

function Dex.entry(itemID) return byID[itemID] end

-- Records one fished item. Returns true the first time this item is caught on the account.
function Dex.record(db, itemID, now, zone)
    if type(itemID) ~= "number" then return false end
    local c = db.catches[itemID]
    if c then
        c.count = c.count + 1
        return false
    end
    db.catches[itemID] = { count = 1, first = now, zone = zone }
    return true
end

function Dex.isCaught(db, itemID) return db.catches[itemID] ~= nil end

-- Entries of a category, in data order. "found" lists fished items missing from the data
-- (fish Forever added or moved), by item id: they help correct the table.
function Dex.list(db, cat)
    if cat == "shiny" then return (ns.Shiny.list(db)) end
    local out = {}
    if cat == "found" then
        for id in pairs(db.catches) do
            if not byID[id] then out[#out + 1] = { id = id, cat = "found", zones = {}, recipes = {} } end
        end
        table.sort(out, function(a, b) return a.id < b.id end)
        return out
    end
    for _, e in ipairs(Data.ENTRIES) do
        if e.cat == cat then out[#out + 1] = e end
    end
    return out
end

-- Tabs to show: every data category, the shiny collection, plus "found" once there is
-- something in it.
function Dex.categories(db)
    local cats = {}
    for _, c in ipairs(Data.CATEGORIES) do cats[#cats + 1] = c end
    cats[#cats + 1] = "shiny"
    if #Dex.list(db, "found") > 0 then cats[#cats + 1] = "found" end
    return cats
end

-- caught, total for one category (nil: the whole data table, discoveries excluded).
-- For "shiny", caught = entries with at least one shiny catch.
function Dex.progress(db, cat)
    if cat == "shiny" then
        local list, done = ns.Shiny.list(db)
        return done, #list
    end
    local caught, total = 0, 0
    for _, e in ipairs(cat and Dex.list(db, cat) or Data.ENTRIES) do
        total = total + 1
        if db.catches[e.id] then caught = caught + 1 end
    end
    return caught, total
end

-- "known", "unknown" or "unscanned" for a recipe on one character. `isPlayerSpell` is the
-- game's own answer when it has one (true means known for sure).
function Dex.recipeState(db, charKey, spellID, isPlayerSpell)
    local known = db.known[charKey]
    if isPlayerSpell == true or (known and known[spellID]) then return "known" end
    if db.scanned[charKey] then return "unknown" end
    return "unscanned"
end

-- Replaces what a character knows of one profession's recipes with a fresh scan.
-- `learned` = list of spell ids the profession window reports as learned.
function Dex.storeScan(db, charKey, learned)
    local known = db.known[charKey]
    if type(known) ~= "table" then
        known = {}
        db.known[charKey] = known
    end
    for _, id in ipairs(learned) do
        if Data.RECIPES[id] then known[id] = true end
    end
    db.scanned[charKey] = true
end
