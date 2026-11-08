-- Game adapter of the fishing options (renaud, 2026-11-05): a fishing session starts with
-- the player's fishing cast and ends Fishing.IDLE seconds (10, renaud 2026-11-05) after the last cast or catch.
-- While it lasts, the "hide names" and "louder sounds" options change game settings
-- (Fishing.lua decides which); they go back at its end, at logout, and at the next login
-- after a crash (the saved values live in FishDexDB.fishing.saved). The auto loot option
-- takes a fished loot window once FishDex has read it (Detect.lua calls onFishingLoot).
-- Some CVars cannot change in combat: a change asked for in combat waits for its end.
local _, ns = ...

local Session = {}
ns.Session = Session

local Fishing = ns.Fishing

local last         -- GetTime() of the last fishing cast or catch, nil outside a session
local ticker
local pending = false -- an apply asked for in combat
local looted = false  -- this loot window was taken already
local channeling = false -- the bobber is out (a whole cast can outlast Fishing.IDLE)

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok then return nil end
    if type(issecretvalue) == "function" and issecretvalue(a) then return nil end
    return a
end

local function getCVar(name)
    local v = safe(C_CVar and C_CVar.GetCVar or GetCVar, name)
    return type(v) == "string" and v or nil
end

local function setCVar(name, value)
    safe(C_CVar and C_CVar.SetCVar or SetCVar, name, value)
end

local function inCombat() return safe(InCombatLockdown) == true end

local function saved() return ns.Main.db.fishing.saved end

function Session.active() return last ~= nil and (channeling or Fishing.active(last, GetTime())) end

-- Puts the game where the options want it: changed while fishing, back otherwise.
function Session.apply()
    if not ns.Main.ready then return end
    if inCombat() then
        pending = true
        return
    end
    pending = false
    local key = ns.FishKeyButton ~= nil and ns.FishKeyButton.active()
    local wanted = Session.active() and Fishing.wanted(ns.Main.db.settings, key) or {}
    Fishing.apply(saved(), wanted, getCVar, setCVar)
end

local function stop()
    last, channeling = nil, false
    if ticker then ticker:Cancel() end
    ticker = nil
    Session.apply()
end

-- A fishing cast or catch: starts the session or keeps it going.
function Session.touch()
    local starting = last == nil
    last = GetTime()
    if starting then
        Session.apply()
        ticker = C_Timer.NewTicker(1, function()
            if not Session.active() then stop() end
        end)
    end
end

-- A fished loot window, read already: take it all when the option is on and the game
-- does not loot by itself (`autoLoot` is the LOOT_READY flag).
function Session.onFishingLoot(autoLoot)
    Session.touch()
    if looted or autoLoot == true or not ns.Main.db.settings.autoLoot then return end
    looted = true
    local n = safe(GetNumLootItems) or 0
    for slot = n, 1, -1 do safe(LootSlot, slot) end
end

function Session.onEvent(event, unit, _, spellID)
    if event == "PLAYER_LOGIN" then
        -- A crash left settings changed: put them back.
        if not inCombat() then Fishing.restore(saved(), getCVar, setCVar) else pending = true end
    elseif event == "PLAYER_LOGOUT" then
        Fishing.restore(saved(), getCVar, setCVar)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then Session.apply() end
    elseif event == "LOOT_CLOSED" then
        looted = false
        if last then Session.touch() end
    elseif unit == "player" and ns.Detect.isFishingSpell(spellID) then
        channeling = event == "UNIT_SPELLCAST_CHANNEL_START"
        Session.touch()
    end
end

Session.EVENTS = { "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_REGEN_ENABLED", "LOOT_CLOSED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }

-- UNIT_ events only for the player (a channel or an inventory change of every unit around
-- would wake the handler for nothing); the plain registration where that is missing.
local function register(frame, event)
    if event:match("^UNIT_") then
        pcall(frame.RegisterUnitEvent, frame, event, "player")
        if frame:IsEventRegistered(event) then return end
    end
    pcall(frame.RegisterEvent, frame, event)
end

local events = CreateFrame("Frame")
for _, e in ipairs(Session.EVENTS) do register(events, e) end
events:SetScript("OnEvent", function(_, event, ...)
    if ns.Main.ready then Session.onEvent(event, ...) end
end)
