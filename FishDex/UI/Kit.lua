-- Shared pieces of the native look: game colours and the panel button.
local _, ns = ...

local Kit = {}
ns.Kit = Kit

local function color(c, fallback)
    if type(c) == "table" and type(c.GetRGB) == "function" then
        local ok, r, g, b = pcall(c.GetRGB, c)
        if ok then return { r, g, b } end
    end
    return fallback
end
Kit.GOLD = color(NORMAL_FONT_COLOR, { 1, 0.82, 0 })
Kit.WHITE = color(HIGHLIGHT_FONT_COLOR, { 1, 1, 1 })
Kit.GREY = color(DISABLED_FONT_COLOR, { 0.5, 0.5, 0.5 })

function Kit.paint(fs, rgb) fs:SetTextColor(rgb[1], rgb[2], rgb[3]) end

-- UIPanelButtonTemplate, nil parent then SetParent; the label stays inside the caps.
-- `raise` (optional) brings the owning window to the front on press.
function Kit.button(parent, w, h, text, onClick, raise)
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
    if raise then b:HookScript("OnMouseDown", raise) end
    return b
end
