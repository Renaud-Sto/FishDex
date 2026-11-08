-- The lure button (renaud, 2026-11-01): shown only while a fishing pole is equipped,
-- movable (Shift + drag). It shows the offered lure, how many the bags hold and the time
-- left on the applied one; a click puts that lure on the pole. Hovering lists the other
-- lures of the bags; clicking one makes it the offered lure.
-- Putting a lure on the pole is a protected action: the button is a
-- SecureActionButtonTemplate ("item" on inventory slot 16, the way the game's own
-- buttons target an item). Protected frames cannot be shown, hidden, moved or changed in
-- combat: an update asked for in combat waits for PLAYER_REGEN_ENABLED.
local _, ns = ...

local LureButton = {}
ns.LureButton = LureButton

local L, Lures, Kit = ns.L, ns.Lures, ns.Kit
local WHITE = Kit.WHITE

LureButton.NAME = "FishDexLureButton"
LureButton.SIZE = 40
LureButton.FLYOUT_SIZE = 34
LureButton.FLYOUT_MAX = 10
local POLE_SLOT = 16
local SLOT_FILE = "Interface\\Buttons\\UI-Quickslot2"
local NONE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local main            -- the secure button, nil until the first update outside combat
local flyout = {}
local pending = false -- an update asked for in combat
local timer, watch    -- tickers: the lure's time left, the hover list's closing
local lastMs, endAt   -- the last time left the client reported, and the end it gives
local applying        -- { id, at }: the lure this button just put on the pole
local offeredID       -- the lure the button offers from the bags, nil with none

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    if type(issecretvalue) == "function" and (issecretvalue(a) or issecretvalue(b)) then return nil end
    return a, b
end

local function inCombat() return safe(InCombatLockdown) == true end

local function settings() return ns.Main.db.settings.lure end

-- Test mode (/fishdex poletest, this session only): Retail has no equippable fishing
-- pole any more (renaud, 2026-11-01), so the button and the double click act as if one
-- were equipped. Putting a lure on slot 16 may then do nothing on Retail.
LureButton.testPole = false

function LureButton.poleEquipped()
    if LureButton.testPole then return true end
    local id = safe(GetInventoryItemID, "player", POLE_SLOT)
    local info = type(C_Item) == "table" and C_Item.GetItemInfoInstant
    if type(id) ~= "number" or type(info) ~= "function" then return false end
    local ok, _, _, _, _, _, classID, subclassID = pcall(info, id)
    return ok and Lures.isPole(classID, subclassID)
end

function LureButton.bagLures()
    local count = type(C_Item) == "table" and C_Item.GetItemCount
    return Lures.inBags(function(id) return safe(count, id) end)
end

local function icon(id) return id and ns.Main.itemIcon(id) or NONE_ICON end

local function hideTooltip() if type(GameTooltip) == "table" then GameTooltip:Hide() end end

-- The lure on the pole: has one, time left (ms), enchant id. Secret values count as none.
local function poleEnchant()
    if type(GetWeaponEnchantInfo) ~= "function" then return false end
    local ok, has, ms, _, enchantID = pcall(GetWeaponEnchantInfo)
    if not ok then return false end
    if type(issecretvalue) == "function" and (issecretvalue(has) or issecretvalue(ms) or issecretvalue(enchantID)) then
        return false
    end
    return has == true, ms, enchantID
end

-- The item of the lure on the pole, when known: the one this button applied, remembered
-- by its enchant id (settings().enchants), so a lure put on from the bags is known too
-- once the button has applied it before.
local function activeLure(has, enchantID)
    if not has then return nil end
    local s = settings()
    if type(s.enchants) ~= "table" then s.enchants = {} end
    if applying and GetTime() - applying.at < 10 and type(enchantID) == "number" then
        s.enchants[enchantID] = applying.id
        applying = nil
    end
    return type(enchantID) == "number" and s.enchants[enchantID] or nil
end

-- Time left on the lure of the pole, counted down every second; with no lure in the bags,
-- the button shows the applied one instead of the question mark.
local function refreshTimer()
    if not main then return end
    local has, ms, enchantID = poleEnchant()
    local now = GetTime()
    endAt = has and Lures.endTime(ms, lastMs, endAt, now) or nil
    lastMs = has and ms or nil
    main.timer:SetText(endAt and Lures.timeLeft((endAt - now) * 1000) or "")
    if offeredID == nil then
        main.activeID = activeLure(has, enchantID)
        main.icon:SetTexture(icon(main.activeID))
        main.icon:SetDesaturated(main.activeID == nil)
    else
        activeLure(has, enchantID)
    end
end

local function runTimer(on)
    if on and not timer then
        timer = C_Timer.NewTicker(1, refreshTimer)
    elseif not on and timer then
        timer:Cancel()
        timer = nil
    end
end

local function hideFlyout()
    for _, b in ipairs(flyout) do b:Hide() end
    if watch then watch:Cancel() end
    watch = nil
end

local function overAny()
    if main:IsMouseOver() then return true end
    for _, b in ipairs(flyout) do
        if b:IsShown() and b:IsMouseOver() then return true end
    end
    return false
end

local function showTooltip(self)
    if type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = self.lureID or self.activeID
    if shown and type(GameTooltip.SetItemByID) == "function" then
        GameTooltip:SetItemByID(shown)
        if not self.lureID then GameTooltip:AddLine(L.LURE_NONE, WHITE[1], WHITE[2], WHITE[3]) end
    else
        GameTooltip:AddLine(L.LURE_NONE, WHITE[1], WHITE[2], WHITE[3])
    end
    if self == main then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.LURE_TIP_CLICK, 0, 1, 0)
        GameTooltip:AddLine(L.LURE_TIP_HOVER, 0, 1, 0)
        GameTooltip:AddLine(L.LURE_TIP_MOVE, 0, 1, 0)
    else
        GameTooltip:AddLine(L.LURE_TIP_CHOOSE, 0, 1, 0)
    end
    GameTooltip:Show()
end

-- The hover list: the other lures of the bags, stacked above the button.
local function showFlyout()
    for _, b in ipairs(flyout) do if b.lureID then b:Show() end end
    if watch then return end
    watch = C_Timer.NewTicker(0.25, function()
        if not overAny() then hideFlyout() end
    end)
end

local function newFlyoutButton(index)
    local b = CreateFrame("Button", nil, UIParent)
    b:SetSize(LureButton.FLYOUT_SIZE, LureButton.FLYOUT_SIZE)
    b:SetFrameStrata("DIALOG")
    b:SetPoint("BOTTOM", main, "TOP", 0, 6 + (index - 1) * (LureButton.FLYOUT_SIZE + 4))
    local slot = b:CreateTexture(nil, "BACKGROUND")
    slot:SetTexture(SLOT_FILE)
    slot:SetSize(LureButton.FLYOUT_SIZE * 64 / 37, LureButton.FLYOUT_SIZE * 64 / 37)
    slot:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", showTooltip)
    b:SetScript("OnLeave", hideTooltip)
    b:SetScript("OnClick", function(self)
        if inCombat() then
            ns.Main.say(L.LURE_COMBAT)
            return
        end
        settings().id = self.lureID
        hideFlyout()
        hideTooltip()
        LureButton.update()
    end)
    b:Hide()
    return b
end

local function savePosition()
    local left, top = main:GetLeft(), main:GetTop()
    if left and top then
        main:ClearAllPoints()
        main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        settings().x, settings().y = left, top
    end
end

local function create()
    -- Nil parent then SetParent (taint rule of the native UI notes).
    main = CreateFrame("Button", LureButton.NAME, nil, "SecureActionButtonTemplate")
    main:SetParent(UIParent)
    main:SetSize(LureButton.SIZE, LureButton.SIZE)
    main:SetFrameStrata("MEDIUM")
    main:SetClampedToScreen(true)
    main:SetMovable(true)
    main:RegisterForClicks("AnyUp", "AnyDown")
    main:RegisterForDrag("LeftButton")
    main:SetAttribute("type", "item")
    main:SetAttribute("target-slot", POLE_SLOT)
    -- Shift + click only moves the button: no action for a shifted click.
    main:SetAttribute("shift-type1", "none")
    local s = settings()
    if type(s.x) == "number" and type(s.y) == "number" then
        main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.x, s.y)
    else
        main:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
    local slot = main:CreateTexture(nil, "BACKGROUND")
    slot:SetTexture(SLOT_FILE)
    slot:SetSize(LureButton.SIZE * 64 / 37, LureButton.SIZE * 64 / 37)
    slot:SetPoint("CENTER", main, "CENTER", 0, 0)
    main.icon = main:CreateTexture(nil, "ARTWORK")
    main.icon:SetAllPoints(main)
    main.count = main:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    main.count:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -2, 2)
    main.timer = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    main.timer:SetPoint("TOP", main, "BOTTOM", 0, -3)
    main:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    main:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    main:SetScript("OnEnter", function(self)
        showTooltip(self)
        showFlyout()
    end)
    main:SetScript("OnLeave", hideTooltip)
    main:SetScript("OnDragStart", function(self)
        if safe(IsShiftKeyDown) and not inCombat() then self:StartMoving() end
    end)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    -- A frame is created shown, so OnShow does not run then: update() starts the ticker too.
    main:HookScript("OnShow", function()
        refreshTimer()
        runTimer(true)
    end)
    main:HookScript("OnHide", function()
        runTimer(false)
        hideFlyout()
    end)
    main:HookScript("PreClick", function()
        if offeredID then applying = { id = offeredID, at = GetTime() } end
    end)
    for i = 1, LureButton.FLYOUT_MAX do flyout[i] = newFlyoutButton(i) end
end

-- Shows the button while a pole is equipped (and the option is on) and fills it from the
-- bags. In combat it waits.
function LureButton.update()
    if not ns.Main.ready then return end
    if inCombat() then
        pending = true
        return
    end
    pending = false
    local wanted = ns.Main.db.settings.lureButton and LureButton.poleEquipped()
    if not main then
        if not wanted then return end
        create()
    end
    local list = LureButton.bagLures()
    local offered = Lures.pick(list, settings().id)
    offeredID = offered and offered.id or nil
    main.lureID = offeredID
    main:SetAttribute("item", offered and ("item:" .. offered.id) or nil)
    main.icon:SetTexture(icon(main.lureID))
    main.icon:SetDesaturated(offered == nil)
    main.count:SetText(offered and offered.count or "")
    local i = 0
    for _, l in ipairs(list) do
        if l ~= offered and i < #flyout then
            i = i + 1
            local b = flyout[i]
            b.lureID = l.id
            b.icon:SetTexture(icon(l.id))
            b.count:SetText(l.count)
        end
    end
    for k = i + 1, #flyout do
        flyout[k].lureID = nil
        flyout[k]:Hide()
    end
    main:SetShown(wanted)
    runTimer(wanted)
    refreshTimer()
end

function LureButton.toggle()
    local s = ns.Main.db.settings
    s.lureButton = not s.lureButton
    LureButton.update()
    return s.lureButton
end

function LureButton.frame() return main end

function LureButton.onEvent(event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then LureButton.update() end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if unit == "player" then refreshTimer() end
    else
        LureButton.update()
    end
end

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
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED",
    "UNIT_INVENTORY_CHANGED" }) do
    register(events, e)
end
events:SetScript("OnEvent", function(_, event, ...) LureButton.onEvent(event, ...) end)
