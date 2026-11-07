-- The Options window (renaud, 2026-11-05; was the Sounds window): two tabs under it.
-- "Fishing": every on/off option of FishDex, the old bottom row of the dex window and the
-- fishing options that replace Better Fishing (auto loot, hidden names, louder sounds,
-- double click with its delay and button, the Interact Key, the fishing key). "Sounds": the sound picker
-- (UI/SoundPicker.lua). Opens beside the dex window; built on first open, like it.
local _, ns = ...

local Options = {}
ns.Options = Options

local L, Kit = ns.L, ns.Kit

local WIDTH, HEIGHT = 440, 474
local TABS = { "fishing", "sounds" }
local ROW = 27

local p -- the window, nil until first open
local state = { tab = "fishing" }
local tabs, pages, checks = {}, {}, {}

function Options.raise() if p then p:Raise() end end

local function settings() return ns.Main.db.settings end

local function percent(v) return string.format("%d %%", math.floor(v * 100 + 0.5)) end

local function seconds(v)
    local text = string.format("%.2f s", v):gsub("0 s$", " s")
    if L.CAT_fish == ns.LOCALES.frFR.CAT_fish then text = text:gsub("%.", ",") end
    return text
end

-- What a box changes besides its setting.
local AFTER = {
    share = function(on) if on then ns.Comm.queue("S", true) end end,
    lureButton = function() ns.LureButton.update() end,
    hideNames = function() ns.Session.apply() end,
    loudSounds = function() ns.Session.apply() end,
    useInteractKey = function()
        ns.FishKeyButton.apply()
        ns.Session.apply()
    end,
}

-- The game's tooltip on a row: its label in white, then OPT_TIP_<key> when there is one.
local function tooltip(frame, key)
    frame:HookScript("OnEnter", function(self)
        local tip = L["OPT_TIP_" .. key]
        if type(GameTooltip) ~= "table" or type(tip) ~= "string" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local title = rawget(self, "key") and type(self.Text) == "table" and self.Text:GetText() or L.OPT_FISHKEY
        GameTooltip:AddLine(title, 1, 1, 1)
        GameTooltip:AddLine(tip, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
end

-- One option row: the box, its label, and `x` the indent.
local function addCheck(page, key, y, x)
    local c = Kit.check(page, "", function(on)
        if key == "doubleCast" then
            ns.DoubleCast.setEnabled(on)
        else
            settings()[key] = on
        end
        if AFTER[key] then AFTER[key](on) end
        Options.refresh()
        if ns.Window then ns.Window.refresh() end
    end, Options.raise)
    c:SetPoint("TOPLEFT", page, "TOPLEFT", 16 + (x or 0), y)
    c.key = key
    checks[#checks + 1] = c
    tooltip(c, key)
    return c
end

local function header(page, y)
    local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", page, "TOPLEFT", 18, y)
    return h
end

local function buildFishing(page)
    local y = -34
    page.general = header(page, y)
    y = y - 22
    for _, key in ipairs({ "sound", "announce", "share", "lureButton" }) do
        addCheck(page, key, y)
        y = y - ROW
    end
    y = y - 8
    page.fishing = header(page, y)
    y = y - 22
    addCheck(page, "autoLoot", y)
    y = y - ROW
    addCheck(page, "hideNames", y)
    y = y - ROW
    page.loud = addCheck(page, "loudSounds", y)
    page.volume = Kit.slider(page, 150, 0, 1, 20, percent, function(v)
        settings().loudVolume = v
        ns.Session.apply()
    end)
    page.volume:SetPoint("TOPRIGHT", page, "TOPRIGHT", -54, y)
    y = y - ROW - 8
    -- Cast and reel in: how it works first, then the double click and the fishing key.
    page.castHeader = header(page, y)
    y = y - 20
    page.castHelp = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    page.castHelp:SetPoint("TOPLEFT", page, "TOPLEFT", 20, y)
    page.castHelp:SetWidth(WIDTH - 60)
    page.castHelp:SetJustifyH("LEFT")
    y = y - 30
    page.cast = addCheck(page, "doubleCast", y)
    page.delay = Kit.slider(page, 150, 0.2, 0.8, 12, seconds, function(v)
        settings().castDelay = v
    end)
    page.delay:SetPoint("TOPRIGHT", page, "TOPRIGHT", -54, y)
    y = y - ROW
    -- The mouse button of the double click, kept while it is off.
    page.button = Kit.button(page, 150, 22, "", function()
        ns.DoubleCast.swapButton()
        Options.refresh()
    end, Options.raise)
    page.button:SetPoint("TOPRIGHT", page, "TOPRIGHT", -54, y)
    page.buttonLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.buttonLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 46, y - 5)
    y = y - ROW - 6
    addCheck(page, "useInteractKey", y)
    y = y - ROW
    -- The fishing key (UI/FishKeyButton.lua): click, then press a key; right click clears.
    -- It is saved in the game's own Key Bindings, where it shows under FishDex too.
    page.fishKeyLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.fishKeyLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 46, y - 5)
    page.fishKey = Kit.button(page, 150, 22, "", function(_, button)
        if button == "RightButton" then
            Options.stopCapture()
            if not ns.FishKeyButton.unbind() then ns.Main.say(L.FISHKEY_COMBAT) end
            Options.refresh()
        else
            Options.startCapture()
        end
    end, Options.raise)
    page.fishKey:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    page.fishKey:SetPoint("TOPRIGHT", page, "TOPRIGHT", -54, y)
    tooltip(page.fishKey, "fishKey")
    page.fishKey:SetScript("OnKeyDown", function(_, key) Options.capturePress(key) end)
    page.fishKey:HookScript("OnMouseDown", function(_, button)
        if state.capturing and ns.FishKey.MOUSE[button] then Options.capturePress(ns.FishKey.MOUSE[button]) end
    end)
    page.fishKey:HookScript("OnHide", function() Options.stopCapture() end)
end

-- Waiting for the fishing key: the button takes the keyboard until a key or Escape.
function Options.startCapture()
    if not p then return end
    state.capturing = true
    local b = p.fishKeyButton
    b:EnableKeyboard(true)
    if type(b.SetPropagateKeyboardInput) == "function" then pcall(b.SetPropagateKeyboardInput, b, false) end
    Options.refresh()
end

function Options.stopCapture()
    if not state.capturing then return end
    state.capturing = false
    if p then p.fishKeyButton:EnableKeyboard(false) end
    Options.refresh()
end

function Options.capturePress(key)
    if not state.capturing then return end
    if key == "ESCAPE" then
        Options.stopCapture()
        return
    end
    local chord = ns.FishKey.chord(key, { alt = IsAltKeyDown and IsAltKeyDown(), ctrl = IsControlKeyDown
        and IsControlKeyDown(), shift = IsShiftKeyDown and IsShiftKeyDown() })
    if not chord then return end -- a lone modifier: wait for the key
    Options.stopCapture()
    local ok, before = ns.FishKeyButton.bind(chord)
    if not ok then
        ns.Main.say(L.FISHKEY_COMBAT)
    elseif before then
        local name = _G["BINDING_NAME_" .. before]
        ns.Main.say(string.format(L.FISHKEY_REPLACED, chord, type(name) == "string" and name or before))
    end
    Options.refresh()
end

local function showTab(key)
    state.tab = key
    for k, page in pairs(pages) do page:SetShown(k == key) end
    Options.refresh()
end

local function buildTabs()
    for i, key in ipairs(TABS) do
        -- Named and created with its parent, like the dex window's tabs (PanelTemplates).
        local ok, t = pcall(CreateFrame, "Button", "FishDexOptionsWindowTab" .. i, p, "PanelTabButtonTemplate")
        if not ok or not t then
            t = Kit.frame("Button", p, "UIPanelButtonTemplate", nil, "FishDexOptionsWindowTab" .. i)
        end
        if type(t.SetID) == "function" then t:SetID(i) end
        if i == 1 then
            t:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 11, 2)
        else
            t:SetPoint("LEFT", tabs[i - 1], "RIGHT", -16, 0)
        end
        t.tab = key
        t:SetScript("OnClick", function(self)
            if type(PlaySound) == "function" and type(SOUNDKIT) == "table" and SOUNDKIT.IG_CHARACTER_INFO_TAB then
                pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_TAB)
            end
            showTab(self.tab)
        end)
        t:HookScript("OnMouseDown", Options.raise)
        tabs[i] = t
    end
    p.Tabs = tabs
    if type(PanelTemplates_SetNumTabs) == "function" then pcall(PanelTemplates_SetNumTabs, p, #TABS) end
end

local function build()
    p = CreateFrame("Frame", "FishDexOptionsWindow", nil, "ButtonFrameTemplate")
    p:SetParent(UIParent)
    p:Hide()
    p:SetSize(WIDTH, HEIGHT)
    p:SetFrameStrata("HIGH")
    if type(p.SetToplevel) == "function" then p:SetToplevel(true) end
    p:HookScript("OnShow", function(self) self:Raise() end)
    p:HookScript("OnMouseDown", function(self) self:Raise() end)
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    if type(ButtonFrameTemplate_HideAttic) == "function" then ButtonFrameTemplate_HideAttic(p) end
    if type(ButtonFrameTemplate_HidePortrait) == "function" then ButtonFrameTemplate_HidePortrait(p) end
    if type(ButtonFrameTemplate_HideButtonBar) == "function" then ButtonFrameTemplate_HideButtonBar(p) end
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
    end)
    -- Beside the dex window, at an absolute position (never anchored to it).
    local main = ns.Window.frame()
    local right, top = main and main:GetRight(), main and main:GetTop()
    if type(right) == "number" and type(top) == "number" then
        p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right + 4, top)
    else
        p:SetPoint("CENTER", UIParent, "CENTER", 300, 40)
    end
    table.insert(UISpecialFrames, "FishDexOptionsWindow")

    for _, key in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, p)
        page:SetAllPoints(p)
        pages[key] = page
    end
    buildFishing(pages.fishing)
    p.fishKeyButton = pages.fishing.fishKey
    ns.SoundPicker.build(pages.sounds)
    buildTabs()
    p:HookScript("OnShow", function() showTab(state.tab) end)
end

local function refreshTabs()
    local native = type(PanelTemplates_SetTab) == "function"
    for i, t in ipairs(tabs) do
        t:SetText(L["OPTIONS_TAB_" .. t.tab])
        if type(PanelTemplates_TabResize) == "function" then pcall(PanelTemplates_TabResize, t, 0) end
        if t.tab == state.tab then
            if native then pcall(PanelTemplates_SetTab, p, i) else t:LockHighlight() end
        elseif not native then
            t:UnlockHighlight()
        end
    end
end

function Options.refresh()
    if not p or not p:IsShown() then return end
    if type(p.SetTitle) == "function" then p:SetTitle(L.TITLE .. " - " .. L.OPTIONS_TITLE) end
    refreshTabs()
    if state.tab == "sounds" then
        ns.SoundPicker.refresh()
        return
    end
    local s, page = settings(), pages.fishing
    page.general:SetText(L.OPTIONS_GENERAL)
    page.fishing:SetText(L.OPTIONS_FISHING)
    page.castHeader:SetText(L.OPTIONS_CAST)
    page.castHelp:SetText(L.OPTIONS_CAST_HELP)
    local castOn = ns.DoubleCast.mode() ~= "off"
    for _, c in ipairs(checks) do
        if type(c.Text) == "table" then c.Text:SetText(L["OPT_LONG_" .. c.key]) end
        if c.key == "doubleCast" then c:SetChecked(castOn) else c:SetChecked(s[c.key]) end
    end
    Kit.setSlider(page.volume, s.loudVolume)
    Kit.enableSlider(page.volume, s.loudSounds)
    Kit.setSlider(page.delay, s.castDelay)
    Kit.enableSlider(page.delay, castOn)
    page.buttonLabel:SetText(L.OPT_CAST_BUTTON)
    page.button:SetText(L["CAST_" .. s.castButton])
    local keys = ns.FishKeyButton.keys()
    local shown = {}
    for i, k in ipairs(keys) do shown[i] = type(GetBindingText) == "function" and GetBindingText(k) or k end
    page.fishKeyLabel:SetText(state.capturing and L.OPT_FISHKEY_CANCEL or L.OPT_FISHKEY)
    page.fishKey:SetText(state.capturing and L.OPT_FISHKEY_PRESS
        or (#keys > 0 and table.concat(shown, ", ") or L.OPT_FISHKEY_NONE))
    -- The Interact Key's box names the key it has now.
    local interact = ns.FishKeyButton.interactKeys()
    for i, k in ipairs(interact) do interact[i] = type(GetBindingText) == "function" and GetBindingText(k) or k end
    for _, c in ipairs(checks) do
        if c.key == "useInteractKey" and type(c.Text) == "table" then
            c.Text:SetText(string.format(L.OPT_LONG_useInteractKey,
                #interact > 0 and table.concat(interact, ", ") or L.OPT_INTERACT_NONE))
        end
    end
end

function Options.toggle()
    if not p then build() end
    if p:IsShown() then
        p:Hide()
    else
        p:Show()
        showTab(state.tab)
    end
end

function Options.hide() if p then p:Hide() end end

function Options.isShown() return p ~= nil and p:IsShown() end
