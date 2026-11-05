-- Sounds tab of the Options window (UI/Options.lua): pick, by ear, the game sound of a
-- first catch and of each shiny grade. A click on a sound plays it; "Use this sound"
-- keeps it for the chosen announce. Built into the tab's frame on the window's first open.
local _, ns = ...

local SoundPicker = {}
ns.SoundPicker = SoundPicker

local L, Kit, Sounds = ns.L, ns.Kit, ns.Sounds

local WIDTH = 440
local ROWS, ROW_H = 15, 20
local p -- the tab's frame, nil until the window's first open
local state = { target = "new", mode = "selection", keys = {}, offset = 0, picked = nil }
local rows, targets, modes = {}, {}, {}

-- The list for the current mode and search text.
local function relist()
    local text = p.search:GetText()
    if state.mode == "all" then
        state.keys = Sounds.filter(SOUNDKIT, text)
    elseif state.mode == "addons" then
        state.keys = Sounds.shared(text)
    else
        state.keys = Sounds.selection(text)
    end
    state.offset = 0
end

local function raise() ns.Options.raise() end

local function targetRGB(target)
    local g = ns.Shiny.grade(target)
    return g and g.color or Kit.GOLD
end

-- Fills `parent` (the tab, the size of the window; offsets count from its top left).
function SoundPicker.build(parent)
    p = parent

    -- Which announce is being set: a segmented row, the chosen one locked highlighted.
    local w = math.floor((WIDTH - 28 - 3 * 4) / 4)
    for i, target in ipairs(Sounds.TARGETS) do
        local b = Kit.button(p, w, 22, "", function(self)
            state.target, state.picked = self.target, nil
            SoundPicker.refresh()
        end, raise)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", 14 + (i - 1) * (w + 4), -30)
        b.target = target
        targets[i] = b
    end

    p.current = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.current:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -64)
    p.current:SetPoint("RIGHT", p, "RIGHT", -110, 0)
    p.current:SetJustifyH("LEFT")
    p.current:SetWordWrap(false)
    p.listen = Kit.button(p, 86, 22, "", function() Sounds.playFor(state.target) end, raise)
    p.listen:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -58)

    -- Where the sounds come from: the selection (named game files), every SOUNDKIT sound,
    -- or the sounds other addons share (LibSharedMedia). Segmented buttons, own row.
    local mw = math.floor((WIDTH - 28 - 2 * 4) / 3)
    for i, mode in ipairs({ "selection", "all", "addons" }) do
        local b = Kit.button(p, mw, 22, "", function(self)
            state.mode = self.mode
            relist()
            SoundPicker.refresh()
        end, raise)
        b.mode = mode
        b:SetPoint("TOPLEFT", p, "TOPLEFT", 14 + (i - 1) * (mw + 4), -90)
        modes[i] = b
    end

    p.searchLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.searchLabel:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -126)
    p.search = CreateFrame("EditBox", nil, nil, "InputBoxTemplate")
    p.search:SetParent(p)
    p.search:SetSize(200, 22)
    p.search:SetAutoFocus(false)
    p.search:SetPoint("LEFT", p.searchLabel, "RIGHT", 12, 0)
    p.search:SetScript("OnEnterPressed", p.search.ClearFocus)
    p.search:HookScript("OnEscapePressed", p.search.ClearFocus)
    p.search:SetScript("OnTextChanged", function()
        relist()
        SoundPicker.refresh()
    end)

    -- The list: an inset with ROWS recycled rows; the mouse wheel scrolls it.
    p.inset = CreateFrame("Frame", nil, nil, "InsetFrameTemplate")
    p.inset:SetParent(p)
    p.inset:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -150)
    p.inset:SetSize(WIDTH - 24, ROWS * ROW_H + 8)
    local list = CreateFrame("Frame", nil, p.inset)
    list:SetAllPoints(p.inset)
    list:SetFrameLevel((p.inset:GetFrameLevel() or 1) + 1)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, #state.keys - ROWS)
        state.offset = math.min(max, math.max(0, state.offset - delta * 3))
        SoundPicker.refresh()
    end)
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, list)
        r:SetSize(WIDTH - 40, ROW_H)
        r:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -4 - (i - 1) * ROW_H)
        r.selected = r:CreateTexture(nil, "BACKGROUND")
        r.selected:SetAllPoints(r)
        r.selected:SetColorTexture(Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3], 0.16)
        r.selected:Hide()
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r, "LEFT", 4, 0)
        r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
            state.picked = self.key
            Sounds.play(self.key)
            SoundPicker.refresh()
        end)
        r:HookScript("OnMouseDown", raise)
        rows[i] = r
    end

    p.position = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.position:SetPoint("TOPLEFT", p.inset, "BOTTOMLEFT", 6, -8)
    p.use = Kit.button(p, 150, 22, "", function()
        if state.picked then
            ns.Main.db.settings.sounds[state.target] = state.picked
            SoundPicker.refresh()
        end
    end, raise)
    p.use:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -14, 10)
    p.reset = Kit.button(p, 100, 22, "", function()
        ns.Main.db.settings.sounds[state.target] = nil
        SoundPicker.refresh()
    end, raise)
    p.reset:SetPoint("RIGHT", p.use, "LEFT", -6, 0)
    -- Cut before the buttons: the long English text ran under "Default" (seen 2026-10-31).
    p.position:SetWidth(WIDTH - 24 - 6 - (150 + 6 + 100 + 14 + 8))
    p.position:SetJustifyH("LEFT")
    p.position:SetWordWrap(false)
    p:HookScript("OnShow", function() SoundPicker.refresh() end)

    relist()
end

function SoundPicker.refresh()
    if not p or not p:IsShown() then return end
    for _, b in ipairs(targets) do
        b:SetText(L["TARGET_" .. b.target])
        if b.target == state.target then b:LockHighlight() else b:UnlockHighlight() end
    end
    local key = Sounds.keyFor(ns.Main.db, state.target, SOUNDKIT)
    local chosen = ns.Main.db.settings.sounds[state.target] ~= nil
    p.current:SetText(string.format(chosen and L.SOUND_CURRENT or L.SOUND_DEFAULT,
        key and Sounds.label(key) or L.SOUND_NONE))
    Kit.paint(p.current, targetRGB(state.target))
    p.listen:SetText(L.SOUND_LISTEN)
    p.searchLabel:SetText(L.SOUND_SEARCH)
    for _, b in ipairs(modes) do
        b:SetText(L["SOUND_MODE_" .. b.mode])
        if b.mode == state.mode then b:LockHighlight() else b:UnlockHighlight() end
    end
    for i, r in ipairs(rows) do
        local k = state.keys[state.offset + i]
        r.key = k
        if k then
            r.text:SetText(Sounds.label(k))
            Kit.paint(r.text, k == key and targetRGB(state.target) or Kit.WHITE)
            r.selected:SetShown(k == state.picked)
            r:Show()
        else
            r:Hide()
        end
    end
    local n = #state.keys
    local empty = state.mode == "addons" and L.SOUND_EMPTY_ADDONS or L.SOUND_EMPTY
    p.position:SetText(n == 0 and empty or string.format(L.SOUND_POSITION,
        state.offset + 1, math.min(n, state.offset + ROWS), n))
    p.use:SetText(L.SOUND_USE)
    p.use:SetEnabled(state.picked ~= nil)
    p.reset:SetText(L.SOUND_RESET)
    p.reset:SetEnabled(chosen)
end
