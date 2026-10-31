-- The dex window: the game's panel (ButtonFrameTemplate), one tab button per category, a
-- grid of item slots (caught: bright icon; not caught: dark, desaturated) and a detail
-- inset for the selected slot. Built on first open, refreshed only while shown.
local _, ns = ...

local Window = {}
ns.Window = Window

local L, Dex = ns.L, ns.Dex

local WIDTH, HEIGHT = 660, 452
local COLS, ROWS, SLOT, GAP = 7, 7, 38, 4
local GRID_W = COLS * (SLOT + GAP) - GAP
local DETAIL_W = WIDTH - GRID_W - 52
local DETAIL_LINES = 16
local BORDER_FILE = "Interface\\Common\\WhiteIconFrame"

local f              -- the window, nil until first open
local state = { cat = "fish", selected = nil }
local slots, tabs, lines = {}, {}, {}
local pending = false

local function color(c, fallback)
    if type(c) == "table" and type(c.GetRGB) == "function" then
        local ok, r, g, b = pcall(c.GetRGB, c)
        if ok then return r, g, b end
    end
    return fallback[1], fallback[2], fallback[3]
end
local GOLD = { color(NORMAL_FONT_COLOR, { 1, 0.82, 0 }) }
local WHITE = { color(HIGHLIGHT_FONT_COLOR, { 1, 1, 1 }) }
local GREY = { color(DISABLED_FONT_COLOR, { 0.5, 0.5, 0.5 }) }
local GREEN = { 0.25, 0.9, 0.25 }
local RED = { 0.9, 0.3, 0.3 }

local function paint(fs, rgb) fs:SetTextColor(rgb[1], rgb[2], rgb[3]) end

local function raiseWindow() if f then f:Raise() end end

local function button(parent, w, h, text, onClick)
    local b = CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
    b:SetParent(parent)
    b:SetSize(w, h)
    local label = type(b.Text) == "table" and b.Text or b:GetFontString()
    if type(label) == "table" then
        label:ClearAllPoints()
        label:SetPoint("LEFT", b, "LEFT", 6, 0)
        label:SetPoint("RIGHT", b, "RIGHT", -6, 0)
        label:SetWordWrap(false)
    end
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    b:HookScript("OnMouseDown", raiseWindow)
    return b
end

local function check(parent, text, key)
    local c = CreateFrame("CheckButton", nil, nil, "UICheckButtonTemplate")
    c:SetParent(parent)
    c:SetSize(24, 24)
    if type(c.Text) == "table" then
        c.Text:SetFontObject("GameFontHighlightSmall")
        c.Text:SetText(text)
        c.Text:ClearAllPoints()
        c.Text:SetPoint("LEFT", c, "RIGHT", 0, 1)
        c:SetHitRectInsets(0, -70, 0, 0)
    end
    c:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        ns.Main.db.settings[key] = on
        if type(PlaySound) == "function" and type(SOUNDKIT) == "table" then
            local id = on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
            if id then pcall(PlaySound, id) end
        end
    end)
    c.key = key
    return c
end

-- Item tooltip for a caught entry; only zones for one not caught yet.
local function showTooltip(slot)
    local e = slot.entry
    if not e or type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    if Dex.isCaught(ns.Main.db, e.id) and type(GameTooltip.SetItemByID) == "function" then
        GameTooltip:SetItemByID(e.id)
    else
        GameTooltip:AddLine(L.UNKNOWN_NAME, GREY[1], GREY[2], GREY[3])
        GameTooltip:AddLine(L.NOT_CAUGHT, WHITE[1], WHITE[2], WHITE[3])
        for i = 1, math.min(#e.zones, 4) do
            GameTooltip:AddLine(ns.Main.zoneName(e.zones[i]), GOLD[1], GOLD[2], GOLD[3])
        end
    end
    GameTooltip:Show()
end

local function newSlot(parent, index)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(SLOT, SLOT)
    local col, row = (index - 1) % COLS, math.floor((index - 1) / COLS)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", col * (SLOT + GAP), -row * (SLOT + GAP))
    local frameTex = s:CreateTexture(nil, "BACKGROUND")
    frameTex:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    frameTex:SetSize(SLOT * 64 / 37, SLOT * 64 / 37)
    frameTex:SetPoint("CENTER", s, "CENTER", 0, 0)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(SLOT - 4, SLOT - 4)
    s.icon:SetPoint("CENTER", s, "CENTER", 0, 0)
    -- Shiny border: the game's item quality frame, tinted with the best shiny grade.
    if type(GetFileIDFromPath) ~= "function" or GetFileIDFromPath(BORDER_FILE) then
        s.border = s:CreateTexture(nil, "OVERLAY", nil, 1)
        s.border:SetTexture(BORDER_FILE)
        s.border:SetAllPoints(s.icon)
        s.border:Hide()
    end
    s.selected = s:CreateTexture(nil, "OVERLAY")
    s.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    s.selected:SetBlendMode("ADD")
    s.selected:SetAllPoints(s.icon)
    s.selected:Hide()
    s:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    s:SetScript("OnClick", function(self)
        state.selected = self.entry and self.entry.id or nil
        Window.refresh()
    end)
    s:HookScript("OnMouseDown", raiseWindow)
    s:SetScript("OnEnter", showTooltip)
    s:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    s:Hide()
    return s
end

local function build()
    f = CreateFrame("Frame", "FishDexWindow", nil, "ButtonFrameTemplate")
    f:SetParent(UIParent)
    f:Hide()
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    if type(f.SetToplevel) == "function" then f:SetToplevel(true) end
    f:HookScript("OnShow", function(self) self:Raise() end)
    f:HookScript("OnMouseDown", function(self) self:Raise() end)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    if type(ButtonFrameTemplate_HideAttic) == "function" then ButtonFrameTemplate_HideAttic(f) end
    if type(ButtonFrameTemplate_HidePortrait) == "function" then ButtonFrameTemplate_HidePortrait(f) end
    if type(ButtonFrameTemplate_HideButtonBar) == "function" then ButtonFrameTemplate_HideButtonBar(f) end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            ns.Main.db.settings.window = { x = left, y = top }
        end
    end)
    local pos = ns.Main.db.settings.window
    if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    f:HookScript("OnShow", function() Window.refresh() end)
    table.insert(UISpecialFrames, "FishDexWindow")

    -- Tabs: a segmented row of buttons, the chosen one locked highlighted.
    f.tabBar = CreateFrame("Frame", nil, f)
    f.tabBar:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -30)
    f.tabBar:SetSize(WIDTH - 28, 22)

    f.progress = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.progress:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -60)
    f.progress:SetJustifyH("LEFT")

    f.grid = CreateFrame("Frame", nil, f)
    f.grid:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -80)
    f.grid:SetSize(GRID_W, ROWS * (SLOT + GAP))
    for i = 1, COLS * ROWS do slots[i] = newSlot(f.grid, i) end

    -- Detail inset; its content sits in a child one level up (InsetFrameTemplate shares
    -- its parent's level).
    f.detail = CreateFrame("Frame", nil, nil, "InsetFrameTemplate")
    f.detail:SetParent(f)
    f.detail:SetPoint("TOPLEFT", f.grid, "TOPRIGHT", 14, 22)
    f.detail:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 40)
    local face = CreateFrame("Frame", nil, f.detail)
    face:SetAllPoints(f.detail)
    face:SetFrameLevel((f.detail:GetFrameLevel() or 1) + 1)
    f.face = face
    f.bigIcon = face:CreateTexture(nil, "ARTWORK")
    f.bigIcon:SetSize(40, 40)
    f.bigIcon:SetPoint("TOPLEFT", face, "TOPLEFT", 10, -10)
    f.name = face:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.name:SetPoint("TOPLEFT", f.bigIcon, "TOPRIGHT", 8, -2)
    f.name:SetPoint("RIGHT", face, "RIGHT", -10, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.status = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
    f.status:SetPoint("RIGHT", face, "RIGHT", -10, 0)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)
    -- First catch on its own line under the icon: beside it, it wrapped onto the zones
    -- header (seen in game 2026-10-31, frFR texts).
    f.first = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.first:SetPoint("TOPLEFT", f.bigIcon, "BOTTOMLEFT", 2, -6)
    f.first:SetPoint("RIGHT", face, "RIGHT", -10, 0)
    f.first:SetJustifyH("LEFT")
    f.first:SetWordWrap(false)
    for i = 1, DETAIL_LINES do
        local fs = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", face, "TOPLEFT", 12, -80 - (i - 1) * 16)
        fs:SetWidth(DETAIL_W - 24)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        lines[i] = fs
    end

    f.sound = check(f, L.OPT_SOUND, "sound")
    f.sound:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 10)
    f.announce = check(f, L.OPT_ANNOUNCE, "announce")
    f.announce:SetPoint("LEFT", f.sound, "RIGHT", 90, 0)
end

local function rebuildTabs()
    local cats = Dex.categories(ns.Main.db)
    local w = math.floor((WIDTH - 28 - (#cats - 1) * 4) / #cats)
    for i, cat in ipairs(cats) do
        local t = tabs[i]
        if not t then
            t = button(f.tabBar, w, 22, "", function(self)
                state.cat, state.selected = self.cat, nil
                Window.refresh()
            end)
            tabs[i] = t
        end
        t:SetWidth(w)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", f.tabBar, "TOPLEFT", (i - 1) * (w + 4), 0)
        t.cat = cat
        t:SetText(L["CAT_" .. cat])
        if cat == state.cat then t:LockHighlight() else t:UnlockHighlight() end
        t:Show()
    end
    for i = #cats + 1, #tabs do tabs[i]:Hide() end
    return cats
end

-- Detail lines: { text, rgb } pairs, cut to DETAIL_LINES.
-- "2 %" / "0,05 %": a grade's chance per catch, in the addon's language.
local function percent(chance)
    local text = string.format("%g %%", chance * 100)
    if L.CAT_fish == ns.LOCALES.frFR.CAT_fish then text = text:gsub("%.", ",") end
    return text
end

local function gradeRGB(key)
    local g = key and ns.Shiny.grade(key)
    return g and g.color or nil
end

local function shinyLines(e)
    local out = {}
    local function add(text, rgb) out[#out + 1] = { text, rgb } end
    add(L.WHERE, GOLD)
    for _, z in ipairs(e.zones) do add("  " .. ns.Main.zoneName(z), WHITE) end
    add(" ", WHITE)
    add(L.SHINY_GRADES, GOLD)
    local byGrade = ns.Main.db.shiny[e.id] or {}
    for _, g in ipairs(ns.Shiny.GRADES) do
        local c, name = byGrade[g.key], L["GRADE_" .. g.key]
        if c then
            local when = type(c.first) == "number" and date("%d/%m/%Y", c.first) or "?"
            add("  " .. string.format(L.SHINY_LINE, name, c.count, when), g.color)
        else
            add("  " .. string.format(L.SHINY_MISSING, name, percent(g.chance)), GREY)
        end
    end
    return out
end

local function detailLines(e, caught)
    local out = {}
    local function add(text, rgb) out[#out + 1] = { text, rgb } end
    add(L.WHERE, GOLD)
    if #e.zones == 0 then add(L.NO_ZONE, GREY) end
    for _, z in ipairs(e.zones) do add("  " .. ns.Main.zoneName(z), WHITE) end
    if not caught then return out end
    add(" ", WHITE)
    add(L.RECIPES, GOLD)
    if #e.recipes == 0 then add("  " .. L.NO_RECIPE, GREY) end
    for _, id in ipairs(e.recipes) do
        local r = ns.Data.RECIPES[id]
        local st = ns.Main.recipeState(id)
        local tag = st == "known" and L.KNOWN or st == "unknown" and L.UNKNOWN_RECIPE or L.UNSCANNED
        -- Cooking is the default; only another profession is named.
        local prof = r and r[1] ~= "cooking" and (L["PROF_" .. r[1]] .. " ") or ""
        add(string.format("  %s (%s%d) - %s", ns.Main.recipeName(id), prof, r and r[2] or 0, tag),
            st == "known" and GREEN or st == "unknown" and RED or GREY)
    end
    return out
end

local function showDetail(entries)
    local e
    for _, x in ipairs(entries) do if x.id == state.selected then e = x end end
    for _, fs in ipairs(lines) do fs:SetText("") end
    f.first:SetText("")
    if not e then
        f.bigIcon:Hide()
        f.name:SetText("")
        f.status:SetText(L.SELECT_HINT)
        paint(f.status, GREY)
        return
    end
    local db = ns.Main.db
    local caught = Dex.isCaught(db, e.id)
    local best = ns.Shiny.best(db, e.id)
    if state.cat == "shiny" then caught = best ~= nil end
    f.bigIcon:SetTexture(ns.Main.itemIcon(e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.bigIcon:SetDesaturated(not caught)
    f.bigIcon:SetVertexColor(caught and 1 or 0.35, caught and 1 or 0.35, caught and 1 or 0.35)
    f.bigIcon:Show()
    local named = Dex.isCaught(db, e.id)
    f.name:SetText(named and (ns.Main.itemName(e.id) or L.UNKNOWN_NAME) or L.UNKNOWN_NAME)
    paint(f.name, gradeRGB(best) or (named and GOLD or GREY))
    if state.cat == "shiny" then
        f.status:SetText(best and L["GRADE_" .. best] or L.SHINY_NONE)
        paint(f.status, gradeRGB(best) or GREY)
        -- What a shiny cost: every catch of this fish, against its shinies of any grade.
        local fished = db.catches[e.id] and db.catches[e.id].count or 0
        f.first:SetText(string.format(L.SHINY_RATIO, fished, ns.Shiny.total(db, e.id)))
        paint(f.first, GREY)
    elseif caught then
        local c = db.catches[e.id]
        local when = type(c.first) == "number" and date("%d/%m/%Y", c.first) or "?"
        local first = string.format(L.FIRST_CATCH, when)
        if type(c.zone) == "string" then first = first .. " " .. string.format(L.FIRST_ZONE, c.zone) end
        f.status:SetText(string.format(L.CAUGHT_COUNT, c.count))
        paint(f.status, WHITE)
        f.first:SetText(first)
        paint(f.first, GREY)
    else
        f.status:SetText(L.NOT_CAUGHT)
        paint(f.status, GREY)
    end
    for i, line in ipairs(state.cat == "shiny" and shinyLines(e) or detailLines(e, caught)) do
        if i > DETAIL_LINES then break end
        lines[i]:SetText(line[1])
        paint(lines[i], line[2])
    end
end

function Window.refresh()
    if not f or not f:IsShown() then return end
    local db = ns.Main.db
    local cats = rebuildTabs()
    local valid = false
    for _, c in ipairs(cats) do if c == state.cat then valid = true end end
    if not valid then state.cat = cats[1] end
    local entries = Dex.list(db, state.cat)
    local caughtN, totalN = Dex.progress(db, state.cat)
    local allC, allT = Dex.progress(db)
    f.progress:SetText(L["CAT_" .. state.cat] .. " - "
        .. string.format(state.cat == "shiny" and L.SHINY_PROGRESS or L.PROGRESS, caughtN, totalN))
    if type(f.SetTitle) == "function" then f:SetTitle(L.TITLE .. " - " .. string.format(L.TOTAL, allC, allT)) end
    for i, s in ipairs(slots) do
        local e = entries[i]
        s.entry = e
        if e then
            local best = ns.Shiny.best(db, e.id)
            local caught = Dex.isCaught(db, e.id)
            if state.cat == "shiny" then caught = best ~= nil end
            if s.border then
                local rgb = gradeRGB(best)
                if rgb then s.border:SetVertexColor(rgb[1], rgb[2], rgb[3]) end
                s.border:SetShown(rgb ~= nil)
            end
            s.icon:SetTexture(ns.Main.itemIcon(e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            s.icon:SetDesaturated(not caught)
            local v = caught and 1 or 0.3
            s.icon:SetVertexColor(v, v, v)
            s.selected:SetShown(e.id == state.selected)
            s:Show()
        else
            s:Hide()
        end
    end
    showDetail(entries)
    for _, c in ipairs({ { f.sound, L.OPT_SOUND }, { f.announce, L.OPT_ANNOUNCE } }) do
        if type(c[1].Text) == "table" then c[1].Text:SetText(c[2]) end
    end
    f.sound:SetChecked(db.settings.sound)
    f.announce:SetChecked(db.settings.announce)
end

-- Item names arrive in bursts (GET_ITEM_INFO_RECEIVED): repaint once, a moment later.
function Window.refreshSoon()
    if pending or not f or not f:IsShown() then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        Window.refresh()
    end)
end

function Window.toggle()
    if not f then build() end
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        Window.refresh() -- OnShow refreshes too; a repeat costs nothing
    end
end

function Window.isShown() return f ~= nil and f:IsShown() end
