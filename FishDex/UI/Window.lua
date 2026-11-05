-- The dex window, laid out like the game's Collections journal (Toy Box): portrait panel,
-- warm collections background, three tabs under the window (Collection, Shiny, Guild),
-- the categories as side tabs on the right edge (as Forever's profession window), a
-- progress bar in the top strip, two sections with CraftProfit's carved wood headers:
-- pages of item buttons with their names, and the detail of the selected entry. Built on
-- first open, refreshed only while shown. renaud, 2026-11-01: one row of eight tabs was
-- too many, the dark insets too cold; then side tabs, 6 rows (7 ran over the top), wood.
local _, ns = ...

local Window = {}
ns.Window = Window

local L, Dex = ns.L, ns.Dex

local WIDTH, HEIGHT = 703, 560
local COLS, ROWS = 2, 6
local PER_PAGE = COLS * ROWS
local CELL_W, CELL_H = 205, 58
local SPLIT = 432                          -- the grid section ends here, the detail starts
local DETAIL_LINES = 16
local SIDE_W, SIDE_H, SIDE_GAP = 43, 55, 2 -- Forever's LargeSideTabButtonTemplate
local BORDER_FILE = "Interface\\Common\\WhiteIconFrame"
local SLOT_FILE = "Interface\\Buttons\\UI-Quickslot2"
local TABS = { "dex", "shiny", "board" }

local f              -- the window, nil until first open
local state = { tab = "dex", cat = "fish", selected = nil, page = 1 }
local slots, catButtons, lines, tabs = {}, {}, {}, {}
local pending = false

local Kit = ns.Kit
local GOLD, WHITE, GREY = Kit.GOLD, Kit.WHITE, Kit.GREY
local GREEN = { 0.25, 0.9, 0.25 }
local RED = { 0.9, 0.3, 0.3 }
local paint = Kit.paint

local function raiseWindow() if f then f:Raise() end end

local function button(parent, w, h, text, onClick)
    return Kit.button(parent, w, h, text, onClick, raiseWindow)
end

local function sound(key)
    if type(PlaySound) == "function" and type(SOUNDKIT) == "table" and SOUNDKIT[key] then
        pcall(PlaySound, SOUNDKIT[key])
    end
end

-- What the grid lists on the current tab.
local function listCat() return state.tab == "shiny" and "shiny" or state.cat end

local function caughtHere(db, e)
    if state.tab == "shiny" then return ns.Shiny.best(db, e.id) ~= nil end
    return Dex.isCaught(db, e.id)
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

local function hideTooltip() if type(GameTooltip) == "table" then GameTooltip:Hide() end end

-- One collection button: the Toy Box's slot (icon in the collected or uncollected
-- border, name on the right), plus a border tinted with the best shiny grade.
local function newSlot(parent, index)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(50, 50)
    local col, row = (index - 1) % COLS, math.floor((index - 1) / COLS)
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", col * CELL_W, -row * CELL_H)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(42, 42)
    s.icon:SetPoint("CENTER", s, "CENTER", 0, 1)
    s.icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    s.frameOn = s:CreateTexture(nil, "OVERLAY", nil, 1)
    s.frameOn:SetPoint("CENTER", s, "CENTER", 0, 0)
    Kit.art(s.frameOn, "collections-itemborder-collected", 56, 56, SLOT_FILE)
    s.frameOff = s:CreateTexture(nil, "OVERLAY", nil, 1)
    s.frameOff:SetPoint("CENTER", s, "CENTER", 0, 2)
    Kit.art(s.frameOff, "collections-itemborder-uncollected", 50, 50, SLOT_FILE)
    if type(GetFileIDFromPath) ~= "function" or GetFileIDFromPath(BORDER_FILE) then
        s.border = s:CreateTexture(nil, "OVERLAY", nil, 2)
        s.border:SetTexture(BORDER_FILE)
        s.border:SetAllPoints(s.icon)
        s.border:Hide()
    end
    s.selected = s:CreateTexture(nil, "OVERLAY", nil, 3)
    s.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    s.selected:SetBlendMode("ADD")
    s.selected:SetAllPoints(s.icon)
    s.selected:Hide()
    s:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    s.name = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s.name:SetPoint("LEFT", s, "RIGHT", 9, 3)
    s.name:SetWidth(CELL_W - 64)
    s.name:SetJustifyH("LEFT")
    if type(s.name.SetMaxLines) == "function" then s.name:SetMaxLines(2) end
    s:SetScript("OnClick", function(self)
        state.selected = self.entry and self.entry.id or nil
        Window.refresh()
    end)
    s:HookScript("OnMouseDown", raiseWindow)
    s:SetScript("OnEnter", showTooltip)
    s:SetScript("OnLeave", hideTooltip)
    s:Hide()
    return s
end

-- A category side tab on the right edge, drawn like Forever's LargeSideTabButtonTemplate
-- (its atlases, built here rather than inherited: the template's mixin sets atlases on
-- its icon). The icon is the category's first entry; the tooltip names the category.
local function newCatButton(index)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(SIDE_W, SIDE_H)
    b:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -60 - (index - 1) * (SIDE_H + SIDE_GAP))
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("CENTER", b, "CENTER", 0, 0)
    Kit.art(bg, "common-sidetab", SIDE_W, SIDE_H, SLOT_FILE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(34, 34)
    b.icon:SetPoint("CENTER", b, "CENTER", -2, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.lit = b:CreateTexture(nil, "OVERLAY")
    b.lit:SetPoint("CENTER", b, "CENTER", 0, 0)
    if not Kit.art(b.lit, "common-sidetab-selected", SIDE_W, SIDE_H) then
        b.lit:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b.lit:SetBlendMode("ADD")
        b.lit:SetAllPoints(b.icon)
    end
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("CENTER", b, "CENTER", 0, 0)
    if not Kit.art(hover, "common-sidetab-hover", SIDE_W, SIDE_H) then
        hover:Show()
        hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hover:SetBlendMode("ADD")
        hover:SetAllPoints(b.icon)
    end
    b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", self, "CENTER", -1, -1) end)
    b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", self, "CENTER", -2, 0) end)
    b:SetScript("OnClick", function(self)
        state.cat, state.selected, state.page = self.cat, nil, 1
        sound("IG_CHARACTER_INFO_TAB")
        Window.refresh()
    end)
    b:HookScript("OnMouseDown", raiseWindow)
    b:SetScript("OnEnter", function(self)
        if type(GameTooltip) ~= "table" then return end
        local caught, total = Dex.progress(ns.Main.db, self.cat)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -4, -4)
        GameTooltip:AddLine(L["CAT_" .. self.cat], WHITE[1], WHITE[2], WHITE[3])
        GameTooltip:AddLine(string.format(L.PROGRESS, caught, total), GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", hideTooltip)
    return b
end

-- The Collections progress bar, built from the files its template uses.
local function progressBar()
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetSize(196, 13)
    bar:SetPoint("TOP", f, "TOP", 0, -36)
    bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
    bar:SetStatusBarColor(0.03125, 0.85, 0)
    bar:SetMinMaxValues(0, 1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0, 0, 0, 0.6)
    local border = bar:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder")
    border:SetSize(205, 29)
    border:SetPoint("LEFT", bar, "LEFT", -5, 0)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 1)
    return bar
end

-- The tabs under the window (PanelTabButtonTemplate, named so PanelTemplates finds them).
local function buildTabs()
    for i, key in ipairs(TABS) do
        -- Created with its parent: the tab's OnShow reads GetParent() for its padding.
        local ok, t = pcall(CreateFrame, "Button", "FishDexWindowTab" .. i, f, "PanelTabButtonTemplate")
        if not ok or not t then t = Kit.frame("Button", f, "UIPanelButtonTemplate", nil, "FishDexWindowTab" .. i) end
        if type(t.SetID) == "function" then t:SetID(i) end
        if i == 1 then
            t:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
        else
            t:SetPoint("LEFT", tabs[i - 1], "RIGHT", -16, 0)
        end
        t.tab = key
        t:SetScript("OnClick", function(self)
            state.tab, state.selected, state.page = self.tab, nil, 1
            sound("IG_CHARACTER_INFO_TAB")
            Window.refresh()
        end)
        t:HookScript("OnMouseDown", raiseWindow)
        tabs[i] = t
    end
    f.Tabs = tabs
    if type(PanelTemplates_SetNumTabs) == "function" then pcall(PanelTemplates_SetNumTabs, f, #TABS) end
end

local function build()
    f = Kit.frame("Frame", UIParent, "PortraitFrameTemplate", "ButtonFrameTemplate", "FishDexWindow")
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
    if type(f.SetPortraitToAsset) == "function" then
        pcall(f.SetPortraitToAsset, f, "Interface\\Icons\\Trade_Fishing")
    end
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

    -- Background: the Collections tile (an inset sharing the window's level); content one
    -- level up.
    local bg = Kit.frame("Frame", f, "CollectionsBackgroundTemplate", "InsetFrameTemplate")
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -60)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 5)
    local content = CreateFrame("Frame", nil, bg)
    content:SetAllPoints(bg)
    content:SetFrameLevel((f:GetFrameLevel() or 1) + 2)
    f.content = content

    -- The whole top of the window, title bar included, in the same carved wood as the
    -- headers (renaud, 2026-11-01): a texture of the window itself, so the border, the
    -- portrait and the title (child frames) draw over it.
    f.topWood = f:CreateTexture(nil, "BORDER")
    f.topWood:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -1)
    f.topWood:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -2, -60)
    if Kit.art(f.topWood, "questlog-reward-header-top") then f.topWood:SetTexCoord(0, 1, 0.2, 0.97) end

    -- Top strip: the progress bar (Collection and Shiny tabs).
    f.progress = progressBar()

    -- Sections with CraftProfit's carved wood headers: the grid, the detail, the ranking.
    f.list = Kit.panel(content)
    -- One wood header across both columns (two strips left a gap that cut the colour):
    -- the category and its count over the grid, "Details" over the detail column.
    f.list.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
    f.list.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 40)
    f.list.right:ClearAllPoints()
    f.list.right:SetPoint("RIGHT", f.list.head, "LEFT", SPLIT - 14, 0)
    f.infoTitle = f.list.head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.infoTitle:SetPoint("LEFT", f.list.head, "LEFT", SPLIT + 8, 0)
    f.grid = CreateFrame("Frame", nil, f.list.body)
    f.grid:SetPoint("TOPLEFT", f.list.body, "TOPLEFT", 16, -8)
    f.grid:SetSize(COLS * CELL_W, ROWS * CELL_H)
    for i = 1, PER_PAGE do slots[i] = newSlot(f.grid, i) end

    -- Pages, as in the Toy Box: "Page 1/3" and the spellbook arrows.
    f.paging = CreateFrame("Frame", nil, f.list.body)
    f.paging:SetSize(70, 32)
    f.paging:SetPoint("BOTTOMRIGHT", f.list.body, "BOTTOMLEFT", SPLIT - 10, 2)
    f.prev = CreateFrame("Button", nil, f.paging)
    f.prev:SetSize(32, 32)
    f.prev:SetPoint("LEFT", f.paging, "LEFT", 0, 0)
    f.next = CreateFrame("Button", nil, f.paging)
    f.next:SetSize(32, 32)
    f.next:SetPoint("LEFT", f.prev, "RIGHT", 3, 0)
    for _, p in ipairs({ { f.prev, "Prev", -1 }, { f.next, "Next", 1 } }) do
        local b, kind, step = p[1], p[2], p[3]
        b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Down")
        b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnClick", function()
            state.page = state.page + step
            sound("IG_ABILITY_PAGE_TURN")
            Window.refresh()
        end)
        b:HookScript("OnMouseDown", raiseWindow)
    end
    f.pageText = f.paging:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    f.pageText:SetPoint("RIGHT", f.paging, "LEFT", -11, 0)
    f.pageText:SetJustifyH("RIGHT")
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta)
        if state.tab == "board" then return end
        state.page = state.page - delta
        Window.refresh()
    end)

    f.detail = CreateFrame("Frame", nil, f.list.body)
    f.detail:SetPoint("TOPLEFT", f.list.body, "TOPLEFT", SPLIT + 2, 0)
    f.detail:SetPoint("BOTTOMRIGHT", f.list.body, "BOTTOMRIGHT", 0, 0)
    local face = f.detail
    f.bigIcon = face:CreateTexture(nil, "ARTWORK")
    f.bigIcon:SetSize(40, 40)
    f.bigIcon:SetPoint("TOPLEFT", face, "TOPLEFT", 8, -6)
    f.name = face:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.name:SetPoint("TOPLEFT", f.bigIcon, "TOPRIGHT", 8, -2)
    f.name:SetPoint("RIGHT", face, "RIGHT", -6, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.status = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
    f.status:SetPoint("RIGHT", face, "RIGHT", -6, 0)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)
    -- First catch on its own line under the icon: beside it, it wrapped onto the zones
    -- header (seen in game 2026-10-31, frFR texts).
    f.first = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.first:SetPoint("TOPLEFT", f.bigIcon, "BOTTOMLEFT", 2, -6)
    f.first:SetPoint("RIGHT", face, "RIGHT", -6, 0)
    f.first:SetJustifyH("LEFT")
    f.first:SetWordWrap(false)
    f.divider = face:CreateTexture(nil, "ARTWORK")
    f.divider:SetPoint("TOPLEFT", face, "TOPLEFT", 4, -70)
    f.divider:SetPoint("RIGHT", face, "RIGHT", -4, 0)
    f.divider:SetHeight(3)
    Kit.art(f.divider, "perks-divider-short", nil, nil)
    for i = 1, DETAIL_LINES do
        local fs = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", face, "TOPLEFT", 10, -82 - (i - 1) * 16)
        fs:SetPoint("RIGHT", face, "RIGHT", -6, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        lines[i] = fs
    end

    f.ranking = Kit.panel(content)
    f.ranking.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
    f.ranking.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 40)
    f.board = ns.BoardView.build(f.ranking.body, raiseWindow)

    -- Every option is in the Options window (2026-11-05).
    f.optionsButton = button(content, 110, 22, L.OPTIONS_BUTTON, function() ns.Options.toggle() end)
    f.optionsButton:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -12, 10)

    buildTabs()
end

-- PanelTemplates draws the chosen tab raised; without it (fallback buttons) the chosen
-- one stays highlighted.
local function refreshTabs()
    local native = type(PanelTemplates_SetTab) == "function"
    for i, t in ipairs(tabs) do
        t:SetText(L["TAB_" .. t.tab])
        if type(PanelTemplates_TabResize) == "function" then pcall(PanelTemplates_TabResize, t, 0) end
        if t.tab == state.tab then
            if native then pcall(PanelTemplates_SetTab, f, i) else t:LockHighlight() end
        elseif not native then
            t:UnlockHighlight()
        end
    end
end

-- Category buttons of the Collection tab; the shiny collection has its own tab.
local function refreshCats(db)
    local cats = {}
    for _, c in ipairs(Dex.categories(db)) do
        if c ~= "shiny" then cats[#cats + 1] = c end
    end
    local valid = false
    for _, c in ipairs(cats) do if c == state.cat then valid = true end end
    if not valid then state.cat = cats[1] end
    local onDex = state.tab == "dex"
    for i, cat in ipairs(cats) do
        local b = catButtons[i] or newCatButton(i)
        catButtons[i] = b
        b.cat = cat
        local first = Dex.list(db, cat)[1]
        b.icon:SetTexture(first and ns.Main.itemIcon(first.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
        b.lit:SetShown(cat == state.cat)
        b:SetShown(onDex)
    end
    for i = #cats + 1, #catButtons do catButtons[i]:Hide() end
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
        f.divider:Hide()
        f.name:SetText("")
        f.status:SetText(L.SELECT_HINT)
        paint(f.status, GREY)
        return
    end
    local db = ns.Main.db
    local caught = caughtHere(db, e)
    local best = ns.Shiny.best(db, e.id)
    f.bigIcon:SetTexture(ns.Main.itemIcon(e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.bigIcon:SetDesaturated(not caught)
    f.bigIcon:SetVertexColor(caught and 1 or 0.35, caught and 1 or 0.35, caught and 1 or 0.35)
    f.bigIcon:Show()
    f.divider:Show()
    local named = Dex.isCaught(db, e.id)
    f.name:SetText(named and (ns.Main.itemName(e.id) or L.UNKNOWN_NAME) or L.UNKNOWN_NAME)
    paint(f.name, gradeRGB(best) or (named and GOLD or GREY))
    if state.tab == "shiny" then
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
    for i, line in ipairs(state.tab == "shiny" and shinyLines(e) or detailLines(e, caught)) do
        if i > DETAIL_LINES then break end
        lines[i]:SetText(line[1])
        paint(lines[i], line[2])
    end
end

local function refreshSlots(db, entries)
    local pages = math.max(1, math.ceil(#entries / PER_PAGE))
    state.page = math.max(1, math.min(state.page, pages))
    local base = (state.page - 1) * PER_PAGE
    for i, s in ipairs(slots) do
        local e = entries[base + i]
        s.entry = e
        if e then
            local best = ns.Shiny.best(db, e.id)
            local caught = caughtHere(db, e)
            if s.border then
                local rgb = gradeRGB(best)
                if rgb then s.border:SetVertexColor(rgb[1], rgb[2], rgb[3]) end
                s.border:SetShown(rgb ~= nil)
            end
            s.icon:SetTexture(ns.Main.itemIcon(e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            s.icon:SetDesaturated(not caught)
            s.icon:SetAlpha(caught and 1 or 0.35)
            s.frameOn:SetShown(caught)
            s.frameOff:SetShown(not caught)
            s.name:SetText(Dex.isCaught(db, e.id) and (ns.Main.itemName(e.id) or L.UNKNOWN_NAME) or L.UNKNOWN_NAME)
            paint(s.name, caught and (gradeRGB(best) or GOLD) or GREY)
            s.selected:SetShown(e.id == state.selected)
            s:Show()
        else
            s:Hide()
        end
    end
    f.pageText:SetText(string.format(L.PAGE, state.page, pages))
    f.prev:SetEnabled(state.page > 1)
    f.next:SetEnabled(state.page < pages)
end

function Window.refresh()
    if not f or not f:IsShown() then return end
    local db = ns.Main.db
    if type(f.SetTitle) == "function" then f:SetTitle(L.TITLE) end
    refreshTabs()
    refreshCats(db)
    Window.refreshChecks()
    local onBoard = state.tab == "board"
    f.list.frame:SetShown(not onBoard)
    f.ranking.frame:SetShown(onBoard)
    ns.BoardView.setShown(onBoard)
    -- The bar: the whole dex (or every shiny), like a profession's skill bar.
    local barC, barT = Dex.progress(db, state.tab == "shiny" and "shiny" or nil)
    f.progress:SetValue(barT > 0 and barC / barT or 0)
    f.progress.text:SetText(string.format(state.tab == "shiny" and L.SHINY_PROGRESS or L.TOTAL, barC, barT))
    f.progress:SetShown(not onBoard)
    if onBoard then
        f.ranking.title:SetText(L.BOARD_TITLE)
        f.ranking.right:SetText(ns.BoardView.refresh())
        return
    end
    local cat = listCat()
    local caughtN, totalN = Dex.progress(db, cat)
    f.list.title:SetText(L["CAT_" .. cat])
    f.list.right:SetText(string.format("%d / %d", caughtN, totalN))
    f.infoTitle:SetText(L.DETAIL_HEAD)
    local entries = Dex.list(db, cat)
    refreshSlots(db, entries)
    showDetail(entries)
end

-- The bottom row: the Options button in the addon's language.
function Window.refreshChecks()
    f.optionsButton:SetText(L.OPTIONS_BUTTON)
    if ns.Options then ns.Options.refresh() end
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

function Window.frame() return f end
