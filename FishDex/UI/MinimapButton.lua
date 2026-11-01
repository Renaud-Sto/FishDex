-- The minimap button (renaud, 2026-11-01): left click opens the dex, a left drag moves it
-- around the minimap. Taken from CraftProfit's: the LibDBIcon convention without the
-- library, 31x31, strata MEDIUM, level 8, radius from the minimap's size, square minimaps
-- handled. Never created while hidden (/fishdex minimap); OnUpdate runs only during a drag.
local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

MinimapButton.NAME = "FishDexMinimapButton"
MinimapButton.SIZE = 31
MinimapButton.LEVEL = 8
MinimapButton.DEFAULT_ANGLE = 200
MinimapButton.DEFAULT_WIDTH = 140 -- the default minimap
MinimapButton.ICON = "Interface\\Icons\\Trade_Fishing"
MinimapButton.ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background"
local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"

local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end

-- Pure helpers ---------------------------------------------------------------------

-- Direction from the minimap centre (mx, my) to the cursor (cx, cy), in degrees in
-- [0, 360), 0 to the right, counter-clockwise; nil when a coordinate is not a number.
function MinimapButton.angleFromCursor(cx, cy, mx, my)
    if not (finite(cx) and finite(cy) and finite(mx) and finite(my)) then return nil end
    local angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    if not (angle >= 0 and angle < 360) then return 0 end
    return angle
end

function MinimapButton.radius(minimapWidth)
    if not finite(minimapWidth) or minimapWidth <= 0 then minimapWidth = MinimapButton.DEFAULT_WIDTH end
    return minimapWidth / 2 + 5
end

-- The button's centre relative to the minimap's: on the circle of `radius`, or for a square
-- minimap a circle as wide as its diagonal clamped to the square (as LibDBIcon does).
function MinimapButton.offset(angle, radius, square)
    if not finite(angle) then angle = MinimapButton.DEFAULT_ANGLE end
    if not finite(radius) or radius < 0 then radius = 0 end
    local rad = math.rad(angle % 360)
    local x, y = math.cos(rad), math.sin(rad)
    if not square then return x * radius, y * radius end
    local diag = math.max(0, math.sqrt(2 * radius * radius) - 10)
    return math.max(-radius, math.min(x * diag, radius)), math.max(-radius, math.min(y * diag, radius))
end

-- Widget ----------------------------------------------------------------------------

local button

local function settings() return ns.Main.db.settings.minimap end

local function minimapFrame()
    if type(Minimap) == "table" then return Minimap end
    return nil
end

local function isSquare()
    if type(GetMinimapShape) ~= "function" then return false end
    local ok, shape = pcall(GetMinimapShape)
    return ok and shape == "SQUARE"
end

local function place(angle)
    local map = minimapFrame()
    if not button or not map then return end
    local width = type(map.GetWidth) == "function" and map:GetWidth() or nil
    local x, y = MinimapButton.offset(angle, MinimapButton.radius(width), isSquare())
    button:ClearAllPoints()
    button:SetPoint("CENTER", map, "CENTER", x, y)
end

local function iconPath()
    if type(GetFileIDFromPath) == "function" then
        local ok, id = pcall(GetFileIDFromPath, MinimapButton.ICON)
        if ok and id then return MinimapButton.ICON end
        return MinimapButton.ICON_FALLBACK
    end
    return MinimapButton.ICON
end

local function cursorAngle()
    local map = minimapFrame()
    if not map or type(GetCursorPosition) ~= "function" then return nil end
    local cx, cy = GetCursorPosition()
    local scale = type(map.GetEffectiveScale) == "function" and map:GetEffectiveScale() or 1
    if not finite(scale) or scale <= 0 then scale = 1 end
    local mx, my = map:GetCenter()
    if not finite(cx) or not finite(cy) then return nil end
    return MinimapButton.angleFromCursor(cx / scale, cy / scale, mx, my)
end

local function follow()
    local angle = cursorAngle()
    if angle then
        button.dragAngle = angle
        place(angle)
    end
end

local function stopDrag()
    if button.dragging ~= true then return end
    button.dragging = false
    button:SetScript("OnUpdate", nil)
    if type(button.dragAngle) == "number" then settings().angle = button.dragAngle end
end

local function onUpdate()
    -- A mouse-up that never arrives (alt-tab) must not leave the drag running.
    if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
        follow()
        stopDrag()
        return
    end
    follow()
end

local function showTooltip(self)
    if button.dragging == true or type(GameTooltip) ~= "table" then return end
    local L = ns.L
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.TITLE, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_TIP_LEFT, 0, 1, 0)
    GameTooltip:AddLine(L.MINIMAP_TIP_DRAG, 0, 1, 0)
    GameTooltip:Show()
end

local function hideTooltip()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
end

local function texture(layer, path, width, height)
    local tex = button:CreateTexture(nil, layer)
    tex:SetTexture(path)
    tex:SetSize(width, height)
    return tex
end

-- Makes the button once; nil while it is hidden or without a minimap.
function MinimapButton.create()
    if button then return button end
    if settings().hide then return nil end
    local map = minimapFrame()
    if not map then return nil end
    -- Nil parent then SetParent: the minimap is a Blizzard frame (gamepad CreateFrame hook).
    button = CreateFrame("Button", MinimapButton.NAME, nil)
    button:SetParent(map)
    button:SetSize(MinimapButton.SIZE, MinimapButton.SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(MinimapButton.LEVEL)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(HIGHLIGHT)
    button.dragged, button.dragging, button.dragAngle = false, false, nil

    local background = texture("BACKGROUND", BACKGROUND, 24, 24)
    background:SetPoint("CENTER", button, "CENTER", 0, 1)
    local icon = texture("ARTWORK", iconPath(), 18, 18)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    button.icon = icon
    local border = texture("OVERLAY", BORDER, 50, 50)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    -- The release that ends a drag still fires OnClick: `dragged` stays true from the
    -- start of a drag to the next press.
    button:SetScript("OnMouseDown", function(self) self.dragged = false end)
    button:SetScript("OnClick", function(self)
        if self.dragged == true then return end
        ns.Window.toggle()
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragged, self.dragging, self.dragAngle = true, true, nil
        hideTooltip()
        self:SetScript("OnUpdate", onUpdate)
    end)
    button:SetScript("OnDragStop", stopDrag)
    button:SetScript("OnHide", stopDrag)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)
    return button
end

-- Shows or hides the button as saved, making it on its first show.
function MinimapButton.apply()
    if settings().hide then
        if button then button:Hide() end
        return
    end
    if not MinimapButton.create() then return end
    place(settings().angle)
    button:Show()
end
