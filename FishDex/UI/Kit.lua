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

-- Sets `atlas` on `tex` at the given size when the client has it; else `file` (a texture
-- path the client always has), or false when neither is given. One atlas per texture.
function Kit.art(tex, atlas, w, h, file)
    local info = type(C_Texture) == "table" and type(C_Texture.GetAtlasInfo) == "function"
        and C_Texture.GetAtlasInfo(atlas)
    if info and type(tex.SetAtlas) == "function" then
        tex:SetAtlas(atlas)
    elseif file then
        tex:SetTexture(file)
    else
        tex:Hide()
        return false
    end
    if w then tex:SetSize(w, h) end
    return true
end

-- A frame from a Blizzard template, or from `fallback` when this client lacks it.
-- Nil parent then SetParent (taint rule of the native UI notes).
function Kit.frame(kind, parent, template, fallback, name)
    local ok, fr = pcall(CreateFrame, kind, name, nil, template)
    if not ok or not fr then fr = CreateFrame(kind, name, nil, fallback) end
    fr:SetParent(parent)
    return fr
end

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
