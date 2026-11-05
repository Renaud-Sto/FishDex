-- Double click to fish (renaud, 2026-11-01): with a fishing pole equipped, outside combat
-- and not mounted, a double click on the world (right or left button, or off) casts
-- Fishing. Options (2026-11-05): the double click's window (castDelay), allowed while
-- mounted (castMounted), and while the bobber is out (recast; off, a double click on a
-- bobber that has not bitten does not cast again). Casting is protected, so it goes through a secure button: on the second press
-- the mouse button is bound for a moment to that button (an override binding, the way
-- fishing addons do it), its release casts, and the binding is cleared right after.
-- The press is seen with a hook on WorldFrame's OnMouseDown (HookScript keeps the game's
-- own handler), so a click on a window never counts.
local _, ns = ...

local DoubleCast = {}
ns.DoubleCast = DoubleCast

local Lures = ns.Lures

DoubleCast.NAME = "FishDexCastButton"
DoubleCast.MODES = { "RightButton", "LeftButton", "off" }
DoubleCast.SAFETY = 1 -- seconds: a binding never outlives this, even without a release
local BINDING = { RightButton = "BUTTON2", LeftButton = "BUTTON1" }

local cast, owner
local lastTime, lastButton = nil, nil
local armed = false

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if not ok then return nil end
    if type(issecretvalue) == "function" and issecretvalue(a) then return nil end
    return a
end

local function inCombat() return safe(InCombatLockdown) == true end

function DoubleCast.mode()
    local m = ns.Main.db.settings.doubleCast
    for _, k in ipairs(DoubleCast.MODES) do if k == m then return m end end
    return "RightButton"
end

-- The next mode, saved: right, left, off, right...
function DoubleCast.cycle()
    local m, s = DoubleCast.mode(), ns.Main.db.settings
    for i, k in ipairs(DoubleCast.MODES) do
        if k == m then s.doubleCast = DoubleCast.MODES[i % #DoubleCast.MODES + 1] end
    end
    if s.doubleCast ~= "off" then s.castButton = s.doubleCast end
    return s.doubleCast
end

-- The Options window's box: on uses the chosen button.
function DoubleCast.setEnabled(on)
    local s = ns.Main.db.settings
    s.doubleCast = on and s.castButton or "off"
end

-- The Options window's right/left button: the other button, kept even while off.
function DoubleCast.swapButton()
    local s = ns.Main.db.settings
    s.castButton = s.castButton == "LeftButton" and "RightButton" or "LeftButton"
    if s.doubleCast ~= "off" then s.doubleCast = s.castButton end
    return s.castButton
end

-- The player's own fishing channel is running (the bobber is out).
local function bobberOut()
    if type(UnitChannelInfo) ~= "function" then return false end
    local ok, _, _, _, _, _, _, _, spellID = pcall(UnitChannelInfo, "player")
    if not ok or (type(issecretvalue) == "function" and issecretvalue(spellID)) then return false end
    return ns.Detect.isFishingSpell(spellID)
end

local function clear()
    if not armed or inCombat() then return end
    armed = false
    safe(ClearOverrideBindings, owner)
end

local function create()
    -- Nil parent then SetParent (taint rule of the native UI notes). A 1 px button with
    -- nothing drawn: only the binding clicks it.
    cast = CreateFrame("Button", DoubleCast.NAME, nil, "SecureActionButtonTemplate")
    cast:SetParent(UIParent)
    cast:SetSize(1, 1)
    cast:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    cast:RegisterForClicks("AnyUp", "AnyDown")
    cast:SetAttribute("type", "spell")
    -- The binding is set on the second press: only its release reaches the button, so the
    -- cast happens on release whatever ActionButtonUseKeyDown says.
    cast:SetAttribute("useOnKeyDown", false)
    cast:HookScript("PostClick", function(_, _, down)
        if not down then C_Timer.After(0, clear) end
    end)
    owner = CreateFrame("Frame")
end

-- A press on the world.
function DoubleCast.onWorldDown(button)
    local mode = DoubleCast.mode()
    if mode == "off" or button ~= mode or not ns.Main.ready then
        lastTime = nil
        return
    end
    local s = ns.Main.db.settings
    if inCombat() or (safe(IsMounted) == true and not s.castMounted) or not ns.LureButton.poleEquipped()
        or (not s.recast and bobberOut()) then
        lastTime = nil
        return
    end
    local now = GetTime()
    if not Lures.isDouble(lastTime, lastButton, now, button, s.castDelay) then
        lastTime, lastButton = now, button
        return
    end
    lastTime = nil
    local spell = Lures.fishingSpell(function(id) return safe(IsPlayerSpell, id) end)
    if not spell then return end
    if not cast then create() end
    cast:SetAttribute("spell", spell)
    safe(SetOverrideBindingClick, owner, true, BINDING[button], DoubleCast.NAME)
    armed = true
    C_Timer.After(DoubleCast.SAFETY, clear)
end

if type(WorldFrame) == "table" and type(WorldFrame.HookScript) == "function" then
    WorldFrame:HookScript("OnMouseDown", function(_, button) DoubleCast.onWorldDown(button) end)
end

-- Leaving combat with a binding still set (it could not be cleared in combat).
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", clear)
