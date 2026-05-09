-- Wick's Bags
-- Options.lua: small modal panel with toggles for v0.2 features.
-- Opened via the cog icon in the main header.

local ADDON, ns = ...
local WB = WicksBags
local UI = WB.UI

WB.Options = {}
local OP = WB.Options

local PANEL_W, PANEL_H = 480, 360
local ROW_H = 22
local COL_GAP = 8

-- ============================================================
-- Toggle row helper
-- ============================================================
local function makeCheckbox(parent, label, getter, setter)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    local cb = CreateFrame("Button", nil, row)
    cb:SetSize(14, 14)
    cb:SetPoint("LEFT", 0, 0)
    UI:NewTexture(cb, "BACKGROUND", { 0, 0, 0, 0.6 }):SetAllPoints(cb)
    UI:AddBorder(cb, UI.C_BORDER)
    local mark = UI:NewTexture(cb, "OVERLAY", UI.C_GREEN)
    mark:SetPoint("TOPLEFT", 2, -2); mark:SetPoint("BOTTOMRIGHT", -2, 2)
    cb._mark = mark

    local function refresh() mark:SetShown(getter() and true or false) end
    refresh()

    cb:SetScript("OnClick", function()
        setter(not getter())
        refresh()
        if WB.Bag and WB.Bag.ApplyOptionsUI then WB.Bag:ApplyOptionsUI() end
        if WB.Bag and WB.Bag.Refresh then WB.Bag:Refresh() end
    end)

    local txt = UI:NewText(row, 11, UI.C_TEXT_NORMAL)
    txt:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    txt:SetText(label)

    -- Click on label also toggles
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function() cb:Click() end)
    return row
end

-- A cycling button. Click advances through `options` ({value, text} pairs).
local function makeCycleButton(parent, label, options, getter, setter)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(220, ROW_H)
    UI:NewTexture(b, "BACKGROUND", { 0, 0, 0, 0.6 }):SetAllPoints(b)
    UI:AddBorder(b, UI.C_BORDER)
    local txt = UI:NewText(b, 11, UI.C_TEXT_NORMAL)
    txt:SetPoint("LEFT", 6, 0)
    local function refresh()
        local v = getter()
        for _, opt in ipairs(options) do
            if opt.value == v then
                txt:SetText(label .. ": |cff4FC778" .. opt.text .. "|r")
                return
            end
        end
        txt:SetText(label .. ": ?")
    end
    refresh()
    b:SetScript("OnClick", function()
        local v = getter()
        local idx = 1
        for i, opt in ipairs(options) do
            if opt.value == v then idx = i break end
        end
        idx = (idx % #options) + 1
        setter(options[idx].value)
        refresh()
        if WB.Bag and WB.Bag.ApplyOptionsUI then WB.Bag:ApplyOptionsUI() end
        if WB.Bag and WB.Bag.Refresh then WB.Bag:Refresh() end
    end)
    return b
end

-- A horizontal slider with brand chrome. Shows current value as a percentage
-- in the label. Drags continuously; commits on every value change.
local function makeSlider(parent, label, minV, maxV, step, getter, setter)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H + 8)

    local txt = UI:NewText(row, 11, UI.C_TEXT_NORMAL)
    txt:SetPoint("TOPLEFT", 0, 0)

    local function fmt(v) return string.format("%s: |cff4FC778%d%%|r", label, math.floor(v * 100 + 0.5)) end
    txt:SetText(fmt(getter()))

    local trackH = 6
    local track = CreateFrame("Frame", nil, row)
    track:SetHeight(trackH)
    track:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 4)
    track:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 4)
    UI:NewTexture(track, "BACKGROUND", { 0, 0, 0, 0.55 }):SetAllPoints(track)
    UI:AddBorder(track, UI.C_BORDER)

    local fill = UI:NewTexture(track, "ARTWORK", UI.C_GREEN)
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)

    local thumb = CreateFrame("Button", nil, row)
    thumb:SetSize(8, 14)
    UI:NewTexture(thumb, "OVERLAY", UI.C_GREEN):SetAllPoints(thumb)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local function place(value)
        local frac = (value - minV) / (maxV - minV)
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        local trackW = track:GetWidth()
        if trackW <= 0 then trackW = 200 end
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", track, "LEFT", frac * trackW, 0)
        fill:SetPoint("BOTTOMRIGHT", track, "BOTTOMLEFT", frac * trackW, 1)
    end
    place(getter())

    local function setFromX(x)
        local left = track:GetLeft() or 0
        local width = track:GetWidth() or 200
        if width <= 0 then return end
        local frac = (x - left) / width
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        local raw = minV + frac * (maxV - minV)
        local snapped = math.floor(raw / step + 0.5) * step
        if snapped < minV then snapped = minV elseif snapped > maxV then snapped = maxV end
        setter(snapped)
        place(snapped)
        txt:SetText(fmt(snapped))
        if WB.Bag and WB.Bag.Refresh then WB.Bag:Refresh() end
    end

    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local x = GetCursorPosition() / self:GetEffectiveScale()
            setFromX(x)
        end
    end)

    -- Re-place the thumb whenever the row is shown. At first build time
    -- track:GetWidth() can return 0 (before the panel has laid out), which
    -- parks the thumb in the wrong spot and makes a persisted value look
    -- like it didn't load. Re-running place() once the row has a real width
    -- pins the thumb to the saved value.
    row:SetScript("OnShow", function() place(getter()) end)

    -- Drag implementation that doesn't get stuck. Uses an always-on OnUpdate
    -- with an IsMouseButtonDown poll instead of OnDragStart/Stop, which can
    -- miss release events when the cursor leaves the thumb during drag.
    thumb._dragging = false
    thumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self._dragging = true
            local x = GetCursorPosition() / self:GetEffectiveScale()
            setFromX(x)
        end
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self._dragging = false
    end)
    thumb:SetScript("OnUpdate", function(self)
        if not self._dragging then return end
        if not IsMouseButtonDown("LeftButton") then
            self._dragging = false
            return
        end
        local x = GetCursorPosition() / self:GetEffectiveScale()
        setFromX(x)
    end)

    return row
end

local function makeButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(120, ROW_H)
    UI:NewTexture(b, "BACKGROUND", { 0, 0, 0, 0.6 }):SetAllPoints(b)
    UI:AddBorder(b, UI.C_BORDER)
    local txt = UI:NewText(b, 11, UI.C_TEXT_NORMAL)
    txt:SetPoint("CENTER")
    txt:SetText(label)
    b:SetScript("OnEnter", function() txt:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1) end)
    b:SetScript("OnLeave", function() txt:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- ============================================================
-- Build the panel
-- ============================================================
function OP:Build()
    if self.panel then return self.panel end

    local panel = CreateFrame("Frame", "WicksBagsOptions", UIParent)
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetPoint("CENTER")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:Hide()

    UI:NewTexture(panel, "BACKGROUND", UI.C_BG):SetAllPoints(panel)
    UI:AddBorder(panel)
    UI:AddCornerAccents(panel)

    -- Header
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(24)
    UI:NewTexture(header, "BACKGROUND", UI.C_HEADER_BG):SetAllPoints(header)
    UI:AddTitleText(header, "Bags Options", "LEFT", 8, 0)
    local div = UI:NewTexture(header, "BORDER", UI.C_BORDER)
    div:SetPoint("BOTTOMLEFT"); div:SetPoint("BOTTOMRIGHT"); div:SetHeight(1)

    -- Close X
    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -6, 0)
    local x = UI:NewText(close, 14, UI.C_TEXT_DIM)
    x:SetPoint("CENTER"); x:SetText("\195\151")
    close:SetScript("OnClick", function() panel:Hide() end)
    close:SetScript("OnEnter", function() x:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1) end)
    close:SetScript("OnLeave", function() x:SetTextColor(UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], 1) end)

    -- Body
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", 12, -32); body:SetPoint("BOTTOMRIGHT", -12, 12)

    -- Layout: full-width "rows" (cycles, sliders) plus a 2-column "checkbox
    -- grid" below them. Each call to addRow advances the y cursor; addPair
    -- places two half-width widgets side-by-side and advances once.
    local rows = {}
    local yCursor = 0
    local function addRow(widget)
        rows[#rows + 1] = widget
        widget:SetParent(body)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT",  body, "TOPLEFT",  0, -yCursor)
        widget:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -yCursor)
        local h = (widget.GetHeight and widget:GetHeight()) or ROW_H
        yCursor = yCursor + h + 4
    end
    local function addPair(left, right)
        local rowY = yCursor
        if left then
            left:SetParent(body)
            left:ClearAllPoints()
            left:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -rowY)
            left:SetWidth((PANEL_W - 24) / 2 - COL_GAP / 2)
        end
        if right then
            right:SetParent(body)
            right:ClearAllPoints()
            right:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -rowY)
            right:SetWidth((PANEL_W - 24) / 2 - COL_GAP / 2)
        end
        yCursor = yCursor + ROW_H + 4
    end

    addRow(makeCycleButton(body, "Sort", {
        { value = "quality",  text = "Quality (high to low)" },
        { value = "name",     text = "Name (A-Z)" },
        { value = "quantity", text = "Quantity (high to low)" },
    },
        function() return WB.db.options.sortMode end,
        function(v) WB.db.options.sortMode = v end))

    addRow(makeCycleButton(body, "Min quality", {
        { value = 0, text = "Show all" },
        { value = 1, text = "Common+" },
        { value = 2, text = "Uncommon+" },
        { value = 3, text = "Rare+" },
        { value = 4, text = "Epic+" },
    },
        function() return WB.db.options.qualityMin or 0 end,
        function(v) WB.db.options.qualityMin = v end))

    addRow(makeCycleButton(body, "Border intensity", {
        { value = 0.0,  text = "Off" },
        { value = 0.35, text = "Subtle" },
        { value = 0.7,  text = "Medium" },
        { value = 1.0,  text = "Full" },
        { value = 1.5,  text = "Bright" },
    },
        function() return WB.db.options.borderIntensity or 1.0 end,
        function(v) WB.db.options.borderIntensity = v end))

    addRow(makeSlider(body, "Slot scale", 0.8, 1.5, 0.05,
        function() return WB.db.options.slotScale or 1.0 end,
        function(v) WB.db.options.slotScale = v end))

    -- Toggles in a 2-column grid. Left column = display toggles, right
    -- column = currency toggles for the bottom bar.
    addPair(
        makeCheckbox(body, "Show item level",
            function() return WB.db.options.showItemLevel ~= false end,
            function(v) WB.db.options.showItemLevel = v end),
        makeCheckbox(body, "Show search box",
            function() return WB.db.options.showSearch end,
            function(v) WB.db.options.showSearch = v end)
    )
    addPair(
        makeCheckbox(body, "Show junk",
            function() return WB.db.options.showJunk end,
            function(v) WB.db.options.showJunk = v end),
        makeCheckbox(body, "Show bottom bar",
            function() return WB.db.options.showBagBar end,
            function(v) WB.db.options.showBagBar = v end)
    )
    addPair(
        makeCheckbox(body, "Highlight new items",
            function() return WB.db.options.showHighlights end,
            function(v) WB.db.options.showHighlights = v end),
        makeCheckbox(body, "Honor Points",
            function() return WB.db.options.showHonor end,
            function(v) WB.db.options.showHonor = v end)
    )
    addPair(
        makeCheckbox(body, "Arena Points",
            function() return WB.db.options.showArena end,
            function(v) WB.db.options.showArena = v end),
        makeCheckbox(body, "Marks of Honor",
            function() return WB.db.options.showMarks end,
            function(v) WB.db.options.showMarks = v end)
    )
    addPair(
        makeCheckbox(body, "Badges",
            function() return WB.db.options.showBadges end,
            function(v) WB.db.options.showBadges = v end),
        makeCheckbox(body, "Spirit Shards",
            function() return WB.db.options.showShards end,
            function(v) WB.db.options.showShards = v end)
    )
    addPair(
        makeCheckbox(body, "Rep tokens",
            function() return WB.db.options.showRep end,
            function(v) WB.db.options.showRep = v end),
        makeCheckbox(body, "Use ItemRack sets",
            function() return WB.db.options.useItemRack ~= false end,
            function(v) WB.db.options.useItemRack = v end)
    )

    -- Mark-all-seen button
    local markBtn = makeButton(body, "Mark all items seen",
        function() if WB.Bag and WB.Bag.MarkAllSeen then WB.Bag:MarkAllSeen() end end)
    markBtn:SetParent(body)
    markBtn:ClearAllPoints()
    markBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)

    self.panel = panel
    return panel
end

function OP:Toggle()
    self:Build()
    if self.panel:IsShown() then self.panel:Hide() else self.panel:Show() end
end
