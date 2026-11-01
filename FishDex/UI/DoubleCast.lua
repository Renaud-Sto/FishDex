-- Double click to fish (renaud, 2026-11-01): with a fishing pole equipped, outside combat
-- and not mounted, a double click on the world (right or left button, or off) casts
-- Fishing. Casting is protected, so it goes through a secure button: on the second press
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
    return s.doubleCast
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
    if inCombat() or safe(IsMounted) == true or not ns.LureButton.poleEquipped() then
        lastTime = nil
        return
    end
    local now = GetTime()
    if not Lures.isDouble(lastTime, lastButton, now, button) then
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
