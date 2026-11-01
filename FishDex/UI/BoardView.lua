-- The Guild tab of the dex window: the ranking as a table on the window's background
-- (header buttons sort by their column, the wheel scrolls), this account's row in gold,
-- shiny columns in their grade colour. Built by Window on first open.
local _, ns = ...

local BoardView = {}
ns.BoardView = BoardView

local L, Kit = ns.L, ns.Kit
local GOLD, WHITE, GREY = Kit.GOLD, Kit.WHITE, Kit.GREY
local paint = Kit.paint

local ROW_H, VISIBLE = 18, 18
-- key (sort key; nil: not sortable), width, label key, justify.
local COLUMNS = {
    { width = 40, label = "COL_RANK", justify = "RIGHT" },
    { key = "name", width = 192, label = "COL_NAME", justify = "LEFT" },
    { key = "total", width = 80, label = "COL_TOTAL", justify = "RIGHT" },
    { key = "rare", width = 76, label = "COL_RARE", justify = "RIGHT" },
    { key = "epic", width = 76, label = "COL_EPIC", justify = "RIGHT" },
    { key = "legendary", width = 92, label = "COL_LEGENDARY", justify = "RIGHT" },
    { width = 88, label = "COL_SEEN", justify = "RIGHT" },
}

local v              -- the view, nil until built
local rows = {}      -- rows[i][c] = font string
local headers = {}
local state = { sort = "total", offset = 0 }

local function gradeRGB(key)
    local g = ns.Shiny.grade(key)
    return g and g.color
end

-- Tooltip of a row: the line's name, then every character of that account seen with
-- FishDex, most recent first.
local function showAlts(hit)
    local row = hit.row
    if not row or type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(hit, "ANCHOR_CURSOR")
    GameTooltip:AddLine(row.name, GOLD[1], GOLD[2], GOLD[3])
    GameTooltip:AddLine(L.BOARD_ALTS, GREY[1], GREY[2], GREY[3])
    for _, name in ipairs(row.alts or {}) do GameTooltip:AddLine("  " .. name, WHITE[1], WHITE[2], WHITE[3]) end
    GameTooltip:Show()
end

function BoardView.build(parent, raise)
    v = CreateFrame("Frame", nil, parent)
    v:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, 0)
    v:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 0)
    v:Hide()
    local face = v

    local x = 8
    for c, col in ipairs(COLUMNS) do
        local h
        if col.key and col.key ~= "name" then
            h = Kit.button(face, col.width - 4, 20, L[col.label], function()
                state.sort, state.offset = col.key, 0
                BoardView.refresh()
            end, raise)
        else
            h = face:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h:SetSize(col.width - 4, 20)
            h:SetJustifyH(col.justify)
        end
        h:SetPoint("TOPLEFT", face, "TOPLEFT", x, -8)
        headers[c] = h
        col.x = x
        x = x + col.width
    end
    for i = 1, VISIBLE do
        local r = {}
        for c, col in ipairs(COLUMNS) do
            local fs = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", face, "TOPLEFT", col.x, -34 - (i - 1) * ROW_H)
            fs:SetSize(col.width - 8, ROW_H)
            fs:SetJustifyH(col.justify)
            fs:SetWordWrap(false)
            r[c] = fs
        end
        -- The whole row answers the mouse: highlight, and the account's characters.
        local hit = CreateFrame("Button", nil, face)
        hit:SetPoint("TOPLEFT", face, "TOPLEFT", 4, -34 - (i - 1) * ROW_H)
        hit:SetPoint("RIGHT", face, "RIGHT", -4, 0)
        hit:SetHeight(ROW_H)
        hit:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        hit:SetScript("OnEnter", showAlts)
        hit:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
        r.hit = hit
        rows[i] = r
    end
    v.note = face:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    v.note:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT", 10, 8)
    v.note:SetPoint("RIGHT", face, "RIGHT", -10, 0)
    v.note:SetJustifyH("LEFT")
    v.note:SetWordWrap(false)
    v:EnableMouseWheel(true)
    v:SetScript("OnMouseWheel", function(_, delta)
        state.offset = math.max(0, state.offset - delta * 3)
        BoardView.refresh()
    end)
    return v
end

function BoardView.setShown(on)
    if v then v:SetShown(on) end
end

local function seen(row)
    if row.me then return L.BOARD_NOW end
    return type(row.t) == "number" and date("%d/%m %H:%M", row.t) or "?"
end

-- Header line text for the window ("Guild - 5 anglers with FishDex"), and fills the table.
function BoardView.refresh()
    if not v then return "" end
    local db = ns.Main.db
    for c, col in ipairs(COLUMNS) do
        local h = headers[c]
        h:SetText(L[col.label])
        if col.key and col.key ~= "name" then
            if col.key == state.sort then h:LockHighlight() else h:UnlockHighlight() end
        end
    end
    local guild = ns.Comm.guildKey()
    -- Without a guild the table still shows this account's own line.
    local list = ns.Board.rows(db, guild, ns.Comm.me(), state.sort)
    state.offset = math.min(state.offset, math.max(0, #list - VISIBLE))
    for i, r in ipairs(rows) do
        local row = list[state.offset + i]
        if row then
            local base = row.me and GOLD or WHITE
            local texts = { tostring(state.offset + i), row.me and string.format(L.BOARD_YOU, row.name) or row.name,
                tostring(row.total), tostring(row.rare), tostring(row.epic), tostring(row.legendary), seen(row) }
            for c, fs in ipairs(r) do
                fs:SetText(texts[c])
                local key = COLUMNS[c].key
                local rgb = base
                if key == "rare" or key == "epic" or key == "legendary" then
                    rgb = row[key] > 0 and gradeRGB(key) or GREY
                elseif c == #COLUMNS then
                    rgb = GREY
                end
                paint(fs, rgb)
            end
            r.hit.row = row
            r.hit:Show()
        else
            for _, fs in ipairs(r) do fs:SetText("") end
            r.hit.row = nil
            r.hit:Hide()
        end
    end
    local note = L.BOARD_HINT
    if not guild then
        note = L.BOARD_NO_GUILD
    elseif not db.settings.share then
        note = L.BOARD_SHARE_OFF
    elseif #list <= 1 then
        note = L.BOARD_EMPTY
    end
    v.note:SetText(note)
    return string.format(L.BOARD_COUNT, #list)
end
