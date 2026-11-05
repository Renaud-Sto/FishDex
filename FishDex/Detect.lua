-- Game adapter: tells a fished loot window from any other and hands its items to the dex.
-- Only a loot window opened by fishing counts (renaud's rule: an item bought at the auction
-- house or looted from a mob never fills the dex). Every game call is guarded.
local _, ns = ...

local Detect = {}
ns.Detect = Detect

-- A loot window that opens right after the player's own fishing channel ends is fishing
-- loot even if IsFishingLoot is missing on this client (fishing spells: Lures.lua).
local CHANNEL_GRACE = 3 -- seconds between the end of the channel and the loot window

Detect.lastFishingStop = nil
local handled = false -- one loot window is read once (LOOT_READY then LOOT_OPENED)

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok then return nil end
    if type(issecretvalue) == "function" and issecretvalue(a) then return nil end
    return a
end

function Detect.spellName(id) return safe(C_Spell and C_Spell.GetSpellName, id) end

function Detect.isFishingSpell(id) return ns.Lures.isFishingSpell(id, Detect.spellName) end

function Detect.isFishingLoot(now)
    if safe(IsFishingLoot) == true then return true end
    local stop = Detect.lastFishingStop
    return stop ~= nil and now - stop <= CHANNEL_GRACE
end

-- Item ids of the open loot window (money and currency slots skipped).
function Detect.lootItemIDs()
    local ids = {}
    local n = safe(GetNumLootItems) or 0
    if type(n) ~= "number" then return ids end
    for slot = 1, n do
        local link = safe(GetLootSlotLink, slot)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id then ids[#ids + 1] = id end
    end
    return ids
end

function Detect.zoneName()
    local z = safe(GetRealZoneText) or safe(GetZoneText)
    if type(z) == "string" and z ~= "" then return z end
    return nil
end

-- The shiny roll, in [0, 1). forceNext (a grade key, set by /fishdex shinytest) makes
-- the next eligible catch that grade, to check the announce without fishing for hours.
Detect.roll = function() return math.random() end
Detect.forceNext = nil

-- Grade key or nil, and true when /fishdex shinytest forced it.
local function shinyFor(entry)
    if not ns.Shiny.eligible(entry) then return nil end
    if Detect.forceNext then
        local key = Detect.forceNext
        Detect.forceNext = nil
        return key, true
    end
    return ns.Shiny.fromRoll(Detect.roll())
end

-- Reads the loot window when it is fishing loot. Returns one record per catch worth
-- telling: { id, new = first catch, grade = shiny grade or nil, newGrade = first of it }.
function Detect.onLoot(db, now, clock)
    if handled then return {} end
    if not Detect.isFishingLoot(clock) then return {} end
    handled = true
    local out = {}
    local zone = Detect.zoneName()
    for _, id in ipairs(Detect.lootItemIDs()) do
        local isNew = ns.Dex.record(db, id, now, zone)
        local grade, forced = shinyFor(ns.Dex.entry(id))
        local newGrade = grade and ns.Shiny.record(db, id, grade, now)
        if forced and ns.Board then ns.Board.noteForced(db, grade) end
        if isNew or grade then out[#out + 1] = { id = id, new = isNew, grade = grade, newGrade = newGrade } end
    end
    return out
end

function Detect.onEvent(event, a1, _, a3)
    local db = ns.Main and ns.Main.db
    if not db then return end
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        for _, c in ipairs(Detect.onLoot(db, time(), GetTime())) do
            if c.grade then ns.Announce.shiny(c.id, c.grade, c.newGrade) else ns.Announce.newCatch(c.id) end
        end
        if handled then
            -- Read first, then taken: the auto loot option empties the window afterwards.
            if ns.Session then ns.Session.onFishingLoot(a1) end
            ns.Main.refresh()
            if ns.Comm then ns.Comm.onCatch() end
        end
    elseif event == "LOOT_CLOSED" then
        handled = false
        Detect.lastFishingStop = nil
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if a1 == "player" and Detect.isFishingSpell(a3) then Detect.lastFishingStop = GetTime() end
    end
end

Detect.EVENTS = { "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "UNIT_SPELLCAST_CHANNEL_STOP" }
