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

-- The carved wood header of CraftProfit's panels (its look "a"): the quest log reward
-- strip, cropped to its wood (about 20 % dark rim above, 3 % below, measured for
-- CraftProfit), 22 px tall, 4 px in from the sides and 2 px from the top, a divider
-- under it. Returns { frame, head, title, right, body }; body starts under the header.
Kit.HEAD_H = 22
function Kit.panel(parent)
    local p = {}
    local f = CreateFrame("Frame", nil, parent)
    p.frame = f
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -2)
    head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -2)
    head:SetHeight(Kit.HEAD_H)
    p.head = head
    local wood = head:CreateTexture(nil, "BACKGROUND")
    wood:SetAllPoints(head)
    if Kit.art(wood, "questlog-reward-header-top") then
        wood:SetTexCoord(0, 1, 0.2, 0.97)
    else
        wood:Show()
        wood:SetColorTexture(Kit.GOLD[1], Kit.GOLD[2], Kit.GOLD[3], 0.15)
    end
    local divider = head:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("LEFT", head, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("RIGHT", head, "BOTTOMRIGHT", 0, 0)
    divider:SetHeight(3)
    Kit.art(divider, "perks-divider-short")
    p.right = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.right:SetPoint("RIGHT", head, "RIGHT", -8, 0)
    p.right:SetWordWrap(false)
    p.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("LEFT", head, "LEFT", 8, 0)
    p.title:SetPoint("RIGHT", p.right, "LEFT", -8, 0)
    p.title:SetJustifyH("LEFT")
    p.title:SetWordWrap(false)
    p.body = CreateFrame("Frame", nil, f)
    p.body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    p.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 2)
    return p
end

-- A frame from a Blizzard template, or from `fallback` when this client lacks it.
-- Nil parent then SetParent (taint rule of the native UI notes).
function Kit.frame(kind, parent, template, fallback, name)
    local ok, fr = pcall(CreateFrame, kind, name, nil, template)
    if not ok or not fr then fr = CreateFrame(kind, name, nil, fallback) end
    fr:SetParent(parent)
    return fr
end

-- UICheckButtonTemplate with its label on the right (clickable too), the game's click
-- sounds; onClick(on) gets the new state.
function Kit.check(parent, text, onClick, raise)
    local c = CreateFrame("CheckButton", nil, nil, "UICheckButtonTemplate")
    c:SetParent(parent)
    c:SetSize(24, 24)
    if type(c.Text) == "table" then
        c.Text:SetFontObject("GameFontHighlightSmall")
        c.Text:SetText(text)
        c.Text:ClearAllPoints()
        c.Text:SetPoint("LEFT", c, "RIGHT", 2, 1)
        c:SetHitRectInsets(0, -190, 0, 0)
    end
    c:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if type(PlaySound) == "function" and type(SOUNDKIT) == "table" then
            local key = on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF"
            if SOUNDKIT[key] then pcall(PlaySound, SOUNDKIT[key]) end
        end
        onClick(on)
    end)
    if raise then c:HookScript("OnMouseDown", raise) end
    return c
end

-- The game options' slider (MinimalSliderWithSteppersTemplate: bar, arrows, value on the
-- right), from min to max in `steps` steps; onChange(value) on every move. `format(value)`
-- writes the value. Returns the frame; Kit.setSlider moves it without calling onChange.
function Kit.slider(parent, width, min, max, steps, format, onChange)
    local ok, s = pcall(CreateFrame, "Frame", nil, nil, "MinimalSliderWithSteppersTemplate")
    if not ok or not s then s = CreateFrame("Frame") end
    s:SetParent(parent)
    s:SetSize(width, 24)
    s.format, s.range = format, { min, max, steps }
    local mixin = type(MinimalSliderWithSteppersMixin) == "table" and MinimalSliderWithSteppersMixin
    s.native = type(s.Init) == "function" and type(s.RegisterCallback) == "function" and mixin
        and type(mixin.Event) == "table" and type(mixin.Label) == "table"
    if s.native then
        s.formatters = { [mixin.Label.Right] = format }
        s:Init(min, min, max, steps, s.formatters)
        s:RegisterCallback(mixin.Event.OnValueChanged, function(_, value)
            if not s.quiet then onChange(value) end
        end, s)
    else
        s.value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.value:SetPoint("LEFT", s, "RIGHT", 6, 0)
    end
    return s
end

function Kit.setSlider(s, value)
    if s.native then
        s.quiet = true
        s:Init(value, s.range[1], s.range[2], s.range[3], s.formatters)
        s.quiet = false
    else
        s.value:SetText(s.format(value))
    end
end

function Kit.enableSlider(s, on)
    if s.native and type(s.SetEnabled) == "function" then s:SetEnabled(on) end
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
