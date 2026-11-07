-- Game adapter of the fishing key (renaud, 2026-11-07, FishKey.lua decides): the key the
-- player binds to "FishDex: fishing key" (Key Bindings, Bindings.xml) gets an override
-- binding on our own frame, so the player's keybinds are never written. A press casts
-- through a secure button's macro, reels the bobber in with the game's own Interact Key
-- action (INTERACTTARGET) once the soft-interact target is the bobber, and takes a fished
-- loot window with a plain button (looting is not protected). Bindings change only out of
-- combat; one asked for in combat waits for its end. With nothing to do (no pole, bobber
-- out of reach) the override is off and the key's own binding says why (FishDex_FishKey).
local _, ns = ...

local FishKeyButton = {}
ns.FishKeyButton = FishKeyButton

local FishKey, L = ns.FishKey, ns.L

FishKeyButton.ACTION = "FISHDEX_FISHKEY"
FishKeyButton.CAST = "FishDexKeyCastButton"
FishKeyButton.LOOT = "FishDexKeyLootButton"
FishKeyButton.INTERACT = "INTERACTTARGET"

local owner, castBtn, lootBtn
local channeling, inReach, lootOpen = false, false, false
local softOther = false -- something else than the bobber is the soft-interact target
local applied, appliedKeys = nil, ""
local pending = false

local function secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok or secret(a) then return nil end
    return a
end

local function inCombat() return safe(InCombatLockdown) == true end

-- The keys bound to `action` in the Key Bindings (up to two).
local function keysOf(action)
    if type(GetBindingKey) ~= "function" then return {} end
    local ok, a, b = pcall(GetBindingKey, action)
    local out = {}
    if ok then
        for _, k in ipairs({ a or false, b or false }) do
            if type(k) == "string" and k ~= "" and not secret(k) then out[#out + 1] = k end
        end
    end
    return out
end

-- The fishing key's own keys.
function FishKeyButton.keys() return keysOf(FishKeyButton.ACTION) end

-- The game's Interact Key ("Interact With Target"), used too when the option is on.
function FishKeyButton.interactKeys() return keysOf(FishKeyButton.INTERACT) end

-- Every key that fishes: own = true for the fishing key's own, false for the Interact Key's.
local function allKeys()
    local out, seen = {}, {}
    for _, k in ipairs(FishKeyButton.keys()) do
        out[#out + 1], seen[k] = { key = k, own = true }, true
    end
    if ns.Main.db.settings.useInteractKey then
        for _, k in ipairs(FishKeyButton.interactKeys()) do
            if not seen[k] then out[#out + 1], seen[k] = { key = k, own = false }, true end
        end
    end
    return out
end

-- A key or the double click fishes, and a pole is equipped: Session.lua then adds
-- FishKey.CVARS, so the Interact Key reaches the bobber.
function FishKeyButton.active()
    if ns.Main.ready ~= true or not ns.LureButton.poleEquipped() then return false end
    return #allKeys() > 0 or ns.DoubleCast.mode() ~= "off"
end

-- The bobber is out and the Interact Key reaches it (the double click reels it in then).
function FishKeyButton.bobberInReach() return channeling and inReach end

function FishKeyButton.state()
    return applied
end

local function fishingName()
    local id = ns.Lures.fishingSpell(function(spellID) return safe(IsPlayerSpell, spellID) end)
    if not id then return nil end
    return ns.Detect.spellName(id) or safe(GetSpellInfo, id)
end

local function lootAll()
    local n = safe(GetNumLootItems) or 0
    for slot = n, 1, -1 do safe(LootSlot, slot) end
end

local function ensureFrames()
    if owner then return end
    owner = CreateFrame("Frame")
    -- Nil parent then SetParent (taint rule of the native UI notes); nothing drawn.
    castBtn = CreateFrame("Button", FishKeyButton.CAST, nil, "SecureActionButtonTemplate")
    castBtn:SetParent(UIParent)
    castBtn:SetSize(1, 1)
    castBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    castBtn:RegisterForClicks("AnyDown") -- one cast per press, never on the release
    castBtn:SetAttribute("useOnKeyDown", true)
    castBtn:SetAttribute("type", "macro")
    -- The session (and its soft-target CVars) starts before the bobber lands.
    castBtn:HookScript("PreClick", function() ns.Session.touch() end)
    lootBtn = CreateFrame("Button", FishKeyButton.LOOT)
    lootBtn:RegisterForClicks("AnyDown")
    lootBtn:SetScript("OnClick", lootAll)
end

-- Puts the override bindings where FishKey.want says. Out of combat only.
function FishKeyButton.apply()
    if not ns.Main.ready then return end
    local keys = allKeys()
    local want = FishKey.want({ bound = #keys > 0, pole = ns.LureButton.poleEquipped(), lootOpen = lootOpen,
        channeling = channeling, inReach = inReach })
    local macro = want == "cast" and FishKey.castMacro(fishingName()) or nil
    if want == "cast" and not macro then want = nil end
    -- The Interact Key keeps its own job while an NPC or an object is its target: it casts
    -- only with nothing else to interact with.
    local used = {}
    for _, k in ipairs(keys) do
        if want and (k.own or want ~= "cast" or not softOther) then used[#used + 1] = k.key end
    end
    local joined = table.concat(used, " ")
    if want == applied and joined == appliedKeys and (want ~= "cast" or castBtn:GetAttribute("macrotext") == macro) then
        return
    end
    if inCombat() then
        pending = true
        return
    end
    pending = false
    ensureFrames()
    safe(ClearOverrideBindings, owner)
    if want == "cast" then castBtn:SetAttribute("macrotext", macro) end
    for _, key in ipairs(used) do
        if want == "reel" then
            safe(SetOverrideBinding, owner, true, key, "INTERACTTARGET")
        elseif want == "loot" then
            safe(SetOverrideBindingClick, owner, true, key, FishKeyButton.LOOT, "LeftButton")
        else
            safe(SetOverrideBindingClick, owner, true, key, FishKeyButton.CAST, "LeftButton")
        end
    end
    applied, appliedKeys = want, joined
end

local function setSoft(guid)
    local hidden = secret(guid)
    local bobber = FishKey.isBobber(guid, hidden)
    inReach = channeling and bobber
    softOther = not bobber and (hidden or guid ~= nil)
    FishKeyButton.apply()
end

function FishKeyButton.onEvent(event, a1, a2, a3)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        if a1 ~= "player" or not ns.Detect.isFishingSpell(a3) then return end
        channeling = true
        local ok, guid = pcall(UnitGUID, "softinteract")
        setSoft(ok and guid or nil)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if a1 ~= "player" or not channeling then return end
        if not (secret(a3) or ns.Detect.isFishingSpell(a3)) then return end
        channeling, inReach = false, false
        FishKeyButton.apply()
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        setSoft(a2)
    elseif event == "LOOT_OPENED" then
        if a1 == true then return end -- the game loots and closes the window itself
        if not ns.Detect.isFishingLoot(GetTime()) then return end -- a chest, a corpse
        lootOpen = true
        FishKeyButton.apply()
    elseif event == "LOOT_CLOSED" then
        lootOpen = false
        FishKeyButton.apply()
    elseif event == "UPDATE_BINDINGS" then
        FishKeyButton.apply()
        ns.Session.apply()
        if ns.Options then ns.Options.refresh() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then FishKeyButton.apply() end
    else -- PLAYER_EQUIPMENT_CHANGED, PLAYER_ENTERING_WORLD: the pole
        FishKeyButton.apply()
    end
end

FishKeyButton.EVENTS = { "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "PLAYER_SOFT_INTERACT_CHANGED", "LOOT_OPENED", "LOOT_CLOSED", "UPDATE_BINDINGS",
    "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }

-- Binds `chord` to the fishing key in the player's Key Bindings (the Options window's
-- button), in place of any key it had, and saves them. Out of combat only (SetBinding is
-- protected). Returns true when done, and the action the key had before, if another one.
function FishKeyButton.bind(chord)
    if inCombat() or type(SetBinding) ~= "function" or type(chord) ~= "string" then return false end
    local before = safe(GetBindingAction, chord)
    for _, k in ipairs(FishKeyButton.keys()) do pcall(SetBinding, k) end
    if not pcall(SetBinding, chord, FishKeyButton.ACTION) then return false end
    FishKeyButton.save()
    if type(before) == "string" and before ~= "" and before ~= FishKeyButton.ACTION then return true, before end
    return true
end

-- Takes the fishing key off every key it has.
function FishKeyButton.unbind()
    if inCombat() or type(SetBinding) ~= "function" then return false end
    for _, k in ipairs(FishKeyButton.keys()) do pcall(SetBinding, k) end
    FishKeyButton.save()
    return true
end

function FishKeyButton.save()
    if type(SaveBindings) ~= "function" then return end
    local set = safe(GetCurrentBindingSet)
    pcall(SaveBindings, set or 1)
end

-- The key's own binding: runs only while no override is set, so it says why.
function FishDex_FishKey()
    if not ns.Main.ready then return end
    if not ns.LureButton.poleEquipped() then
        ns.Main.say(L.FISHKEY_NO_POLE)
    elseif channeling then
        ns.Main.say(L.FISHKEY_FAR)
    elseif inCombat() then
        ns.Main.say(L.FISHKEY_COMBAT)
    end
end

-- Key Bindings labels (the client reads these globals when it lists the bindings).
BINDING_HEADER_FISHDEX = "FishDex"
BINDING_NAME_FISHDEX_FISHKEY = L.FISHKEY_BINDING

local events = CreateFrame("Frame")
for _, e in ipairs(FishKeyButton.EVENTS) do pcall(events.RegisterEvent, events, e) end
events:SetScript("OnEvent", function(_, event, ...)
    if ns.Main.ready then FishKeyButton.onEvent(event, ...) end
end)
