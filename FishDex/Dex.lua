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
    version = 1,
    catches = {},
    known = {},
    scanned = {},
    settings = { sound = true, announce = true, locale = "" }, -- locale "": the client's
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
    fill(db, Dex.DEFAULTS)
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

-- Tabs to show: every data category, plus "found" once there is something in it.
function Dex.categories(db)
    local cats = {}
    for _, c in ipairs(Data.CATEGORIES) do cats[#cats + 1] = c end
    if #Dex.list(db, "found") > 0 then cats[#cats + 1] = "found" end
    return cats
end

-- caught, total for one category (nil: the whole data table, discoveries excluded).
function Dex.progress(db, cat)
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
