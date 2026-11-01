-- Pure logic of the fishing comfort tools (renaud, 2026-11-01): which lures exist, which
-- are in the bags, which one the lure button offers, the fishing pole and spell checks,
-- the time left on the applied lure. Game values come in as arguments.
local _, ns = ...

local Lures = {}
ns.Lures = Lures

-- Lures applied to the fishing pole: item id -> fishing bonus. Classic first; later ones
-- the Retail client still has. A lure Forever adds goes here once its id is known.
Lures.ITEMS = {
    [6529] = 25,   -- Shiny Bauble
    [6530] = 50,   -- Nightcrawlers
    [6811] = 50,   -- Aquadynamic Fish Lens
    [6532] = 75,   -- Bright Baubles
    [7307] = 75,   -- Flesh Eating Worm
    [6533] = 100,  -- Aquadynamic Fish Attractor
    [34861] = 100, -- Sharpened Fish Hook
    [46006] = 100, -- Glow Worm
    [62673] = 100, -- Feathered Lure
    [68049] = 150, -- Heat-Treated Spinning Lure
}

-- Fishing: the Classic ranks, then the Retail spell (12.1.5 casts 131474, measured
-- 2026-10-31). The first one the player knows is cast.
Lures.FISHING_SPELLS = { 131474, 18248, 7732, 7731, 7620 }

-- Item class / subclass of a fishing pole (Enum.ItemClass.Weapon, ItemWeaponSubclass
-- Fishingpole).
Lures.POLE_CLASS, Lures.POLE_SUBCLASS = 2, 20

function Lures.isPole(classID, subclassID)
    return classID == Lures.POLE_CLASS and subclassID == Lures.POLE_SUBCLASS
end

-- The lures in the bags: { id, count, bonus }, best bonus first (ties: lower id).
-- `countOf(id)` gives how many the bags hold.
function Lures.inBags(countOf)
    local out = {}
    for id, bonus in pairs(Lures.ITEMS) do
        local n = countOf(id)
        if type(n) == "number" and n > 0 then out[#out + 1] = { id = id, count = n, bonus = bonus } end
    end
    table.sort(out, function(a, b)
        if a.bonus ~= b.bonus then return a.bonus > b.bonus end
        return a.id < b.id
    end)
    return out
end

-- The lure the button offers: the chosen one while the bags hold it, else the best one;
-- nil with no lure at all.
function Lures.pick(list, chosen)
    for _, l in ipairs(list) do
        if l.id == chosen then return l end
    end
    return list[1]
end

-- The list with the offered lure first (the hover list shows it at the button's side).
function Lures.ordered(list, chosen)
    local first = Lures.pick(list, chosen)
    local out = { first }
    for _, l in ipairs(list) do
        if l ~= first then out[#out + 1] = l end
    end
    return first and out or {}
end

-- The first fishing spell `knows(spellID)` answers true for, or nil.
function Lures.fishingSpell(knows)
    for _, id in ipairs(Lures.FISHING_SPELLS) do
        if knows(id) == true then return id end
    end
    return nil
end

-- "10:00" / "59 s": the time left on the applied lure, from milliseconds; nil when none.
function Lures.timeLeft(ms)
    if type(ms) ~= "number" or ms <= 0 then return nil end
    local s = math.floor(ms / 1000)
    if s < 60 then return s .. " s" end
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- A double click: two presses of the same button within `window` seconds.
Lures.DOUBLE_CLICK = 0.4
function Lures.isDouble(lastTime, lastButton, now, button, window)
    return lastTime ~= nil and lastButton == button and now - lastTime <= (window or Lures.DOUBLE_CLICK)
end
