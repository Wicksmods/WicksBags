-- Wick's Bags
-- UI.lua: brand chrome adapter. The palette, borders and L-bracket corners
-- come from WickCore.Chrome so every Wick product draws from one source.
-- This file keeps the WB.UI surface the panels were written against and
-- adds the pieces that are specific to bags: quality colors, the dim label
-- tint, the two-part title and coin formatting.

local ADDON, ns = ...
local WB = WicksBags
local Chrome = WickCore.Chrome
local C = Chrome.Colors

WB.UI = {}
local UI = WB.UI

-- Palette tokens are references into Chrome.Colors, not copies. A palette
-- change in WickCore reaches every bag panel without a second edit here.
UI.C_BG          = C.voidBG
UI.C_HEADER_BG   = C.shadow
UI.C_BORDER      = C.border
UI.C_GREEN       = C.fel
UI.C_TEXT_NORMAL = C.text
UI.C_TEXT_DIM    = { 0.42, 0.35, 0.54, 1 }   -- secondary labels, bags only

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
    return Chrome:Texture(parent, layer, c)
end

-- Font strings default to the widget's own color when none is given; the
-- panels set most colors themselves after creation.
function UI:NewText(parent, size, c)
    if c then return Chrome:Text(parent, size or 11, c) end
    local f = parent:CreateFontString(nil, "OVERLAY")
    f:SetFont(Chrome.FONT, size or 11, "")
    return f
end

function UI:AddBorder(frame, c)
    Chrome:AddBorder(frame, c)
end

function UI:AddCornerAccents(frame)
    Chrome:AddBrackets(frame)
end

-- Two-tone "Wick's <Title>" header text. "Wick's" off-white, descriptor green.
function UI:AddTitleText(parent, descriptor, anchor, x, y)
    local left = Chrome:Text(parent, 13, C.text)
    left:SetPoint(anchor or "LEFT", x or 8, y or 0)
    left:SetText("Wick's")

    local right = Chrome:Text(parent, 13, C.fel)
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
