-- Pure logic of shiny catches, an addon-only layer (the game has no shiny fish): each
-- fished entry of an eligible category rolls once; the best grade whose chance the roll
-- falls under wins. The item in the bags stays a normal fish.
local _, ns = ...

local Shiny = {}
ns.Shiny = Shiny

-- Grades named after the game's item qualities (renaud, 2026-10-31): rare (blue), epic
-- (purple), legendary (orange). Best grade first. chance = probability per catch
-- (cumulative ranges, so the total shiny chance is the sum). color = the quality colour.
Shiny.GRADES = {
    { key = "legendary", chance = 0.0005, color = { 1, 0.5, 0 } },
    { key = "epic", chance = 0.005, color = { 0.64, 0.21, 0.93 } },
    { key = "rare", chance = 0.02, color = { 0, 0.44, 0.87 } },
}
-- Fish only (renaud, 2026-11-01): a quest item is fished once for its quest, a shiny
-- roll on it would mean nothing.
Shiny.ELIGIBLE = { fish = true }

local rank = {}
for i, g in ipairs(Shiny.GRADES) do rank[g.key] = i end

function Shiny.grade(key)
    return Shiny.GRADES[rank[key] or 0]
end

-- Grade key for a roll in [0, 1), or nil for a normal catch.
function Shiny.fromRoll(roll)
    local edge = 0
    for _, g in ipairs(Shiny.GRADES) do
        edge = edge + g.chance
        if roll < edge then return g.key end
    end
    return nil
end

function Shiny.eligible(entry) return entry ~= nil and Shiny.ELIGIBLE[entry.cat] == true end

-- Records a shiny catch: db.shiny[itemID][grade] = { count, first }. Returns true the
-- first time this item reaches this grade.
function Shiny.record(db, itemID, key, now)
    local byGrade = db.shiny[itemID]
    if type(byGrade) ~= "table" then
        byGrade = {}
        db.shiny[itemID] = byGrade
    end
    local c = byGrade[key]
    if c then
        c.count = c.count + 1
        return false
    end
    byGrade[key] = { count = 1, first = now }
    return true
end

-- Best grade key this item reached, or nil.
function Shiny.best(db, itemID)
    local byGrade = db.shiny[itemID]
    if type(byGrade) ~= "table" then return nil end
    for _, g in ipairs(Shiny.GRADES) do
        if byGrade[g.key] then return g.key end
    end
    return nil
end

-- Shiny catches of an item, every grade together.
function Shiny.total(db, itemID)
    local n = 0
    for _, c in pairs(db.shiny[itemID] or {}) do
        if type(c) == "table" and type(c.count) == "number" then n = n + c.count end
    end
    return n
end

-- Eligible entries in data order, and how many have at least one shiny.
function Shiny.list(db)
    local out, done = {}, 0
    for _, e in ipairs(ns.Data.ENTRIES) do
        if Shiny.eligible(e) then
            out[#out + 1] = e
            if Shiny.best(db, e.id) then done = done + 1 end
        end
    end
    return out, done
end
