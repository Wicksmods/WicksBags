-- Wick's Bags
-- UI.lua: brand chrome helpers (palette, borders, L-bracket corners).
-- Mirrors the helper block in every other Wick addon. Source of truth:
-- memory/reference_wick_brand_style.md.

local ADDON, ns = ...
local WB = WicksBags

WB.UI = {}
local UI = WB.UI

-- Wick brand palette (locked tokens)
UI.C_BG          = { 0.051, 0.039, 0.078, 0.97 }
UI.C_HEADER_BG   = { 0.090, 0.067, 0.141, 1 }
UI.C_BORDER      = { 0.220, 0.188, 0.345, 1 }
UI.C_GREEN       = { 0.310, 0.780, 0.471, 1 }
UI.C_TEXT_DIM    = { 0.42,  0.35,  0.54,  1 }
UI.C_TEXT_NORMAL = { 0.831, 0.784, 0.631, 1 }

-- Item-quality colors. Common and poor are muted so green/blue/purple/orange
-- pop. Higher qualities stay at full saturation.
UI.C_QUALITY = {
    [0] = { 0.45, 0.45, 0.45, 0.55 }, -- poor (muted grey)
    [1] = { 0.70, 0.70, 0.70, 0.45 }, -- common (muted off-white)
    [2] = { 0.12, 1.00, 0.00, 1 },    -- uncommon
    [3] = { 0.00, 0.44, 0.87, 1 },    -- rare
    [4] = { 0.64, 0.21, 0.93, 1 },    -- epic
    [5] = { 1.00, 0.50, 0.00, 1 },    -- legendary
}

function UI:SetRGBA(tex, c)
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

function UI:NewTexture(parent, layer, c)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    if c then self:SetRGBA(t, c) end
    return t
end

function UI:NewText(parent, size, c)
    local f = parent:CreateFontString(nil, "OVERLAY")
    f:SetFont("Fonts\\FRIZQT__.TTF", size or 11, "")
    if c then f:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    return f
end

function UI:AddBorder(frame, c)
    c = c or self.C_BORDER
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT",    "TOPRIGHT",    nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT",    "BOTTOMLEFT",  1,   nil)
    edge("TOPRIGHT",   "BOTTOMRIGHT", 1,   nil)
end

function UI:AddCornerAccents(frame, arm, thick)
    arm = arm or 10
    thick = thick or 2
    local g = self.C_GREEN
    local function brk(anchor)
        local h = frame:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(g[1], g[2], g[3], 1)
        h:SetPoint(anchor); h:SetSize(arm, thick)
        local v = frame:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(g[1], g[2], g[3], 1)
        v:SetPoint(anchor); v:SetSize(thick, arm)
    end
    brk("TOPLEFT"); brk("TOPRIGHT"); brk("BOTTOMLEFT"); brk("BOTTOMRIGHT")
end

-- Two-tone "Wick's <Title>" header text. "Wick's" off-white, descriptor green.
function UI:AddTitleText(parent, descriptor, anchor, x, y)
    local off = self.C_TEXT_NORMAL
    local g   = self.C_GREEN
    local left = parent:CreateFontString(nil, "OVERLAY")
    left:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    left:SetTextColor(off[1], off[2], off[3], 1)
    left:SetPoint(anchor or "LEFT", x or 8, y or 0)
    left:SetText("Wick's")

    local right = parent:CreateFontString(nil, "OVERLAY")
    right:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    right:SetTextColor(g[1], g[2], g[3], 1)
    right:SetPoint("LEFT", left, "RIGHT", 4, 0)
    right:SetText(descriptor or "Bags")

    return left, right
end

-- Format gold from copper count: "12g 34s 56c" with metal-colored suffixes.
-- Color codes follow Blizzard's standard chat-color convention (|cAARRGGBB...|r).
local GOLD_TAG   = "|cffffd700g|r"   -- gold #ffd700
local SILVER_TAG = "|cffc7c7cfs|r"   -- silver #c7c7cf
local COPPER_TAG = "|cffeda55fc|r"   -- copper #eda55f

function UI:FormatMoney(copper)
    copper = copper or 0
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string.format("%d%s %d%s %d%s", g, GOLD_TAG, s, SILVER_TAG, c, COPPER_TAG)
    elseif s > 0 then
        return string.format("%d%s %d%s", s, SILVER_TAG, c, COPPER_TAG)
    else
        return string.format("%d%s", c, COPPER_TAG)
    end
end
