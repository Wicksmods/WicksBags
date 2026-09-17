-- Wick's Bags
-- Options.lua: tabbed modal panel.
--   Tab 1 — General: existing toggles / sliders / cycle buttons.
--   Tab 2 — Rules: custom category assignment (by item, class/subclass, name pattern).

local ADDON, ns = ...
local WB = WicksBags
local UI = WB.UI

WB.Options = {}
local OP = WB.Options

local PANEL_W, PANEL_H = 520, 420
local ROW_H  = 22
local COL_GAP = 8

-- ============================================================
-- TBC item class / subclass tables for the Rules dropdowns
-- ============================================================
local ITEM_CLASSES = {
    { id = 0,  name = "Consumable" },
    { id = 1,  name = "Container" },
    { id = 2,  name = "Weapon" },
    { id = 3,  name = "Gem" },
    { id = 4,  name = "Armor" },
    { id = 5,  name = "Reagent" },
    { id = 6,  name = "Projectile" },
    { id = 7,  name = "Trade Goods" },
    { id = 9,  name = "Recipe" },
    { id = 11, name = "Quiver" },
    { id = 12, name = "Quest" },
    { id = 13, name = "Key" },
    { id = 15, name = "Miscellaneous" },
}
local ITEM_SUBCLASSES = {
    [0]  = {
        { id = 0,  name = "Generic" },
        { id = 1,  name = "Potion" },
        { id = 2,  name = "Elixir" },
        { id = 3,  name = "Flask" },
        { id = 4,  name = "Scroll" },
        { id = 5,  name = "Food & Drink" },
        { id = 6,  name = "Item Enhancement" },
        { id = 7,  name = "Bandage" },
        { id = 8,  name = "Other" },
    },
    [1]  = {
        { id = 0, name = "Bag" },
        { id = 1, name = "Soul Bag" },
        { id = 2, name = "Herb Bag" },
        { id = 3, name = "Enchanting Bag" },
        { id = 4, name = "Engineering Bag" },
        { id = 5, name = "Gem Bag" },
        { id = 6, name = "Mining Bag" },
        { id = 7, name = "Leatherworking Bag" },
        { id = 8, name = "Inscription Bag" },
    },
    [2]  = {
        { id = 0,  name = "Axe (1H)" },
        { id = 1,  name = "Axe (2H)" },
        { id = 2,  name = "Bow" },
        { id = 3,  name = "Gun" },
        { id = 4,  name = "Mace (1H)" },
        { id = 5,  name = "Mace (2H)" },
        { id = 6,  name = "Polearm" },
        { id = 7,  name = "Sword (1H)" },
        { id = 8,  name = "Sword (2H)" },
        { id = 10, name = "Staff" },
        { id = 13, name = "Fist Weapon" },
        { id = 14, name = "Misc Weapon" },
        { id = 15, name = "Dagger" },
        { id = 16, name = "Thrown" },
        { id = 17, name = "Crossbow" },
        { id = 18, name = "Wand" },
        { id = 19, name = "Fishing Pole" },
    },
    [3]  = {
        { id = 0, name = "Red" },
        { id = 1, name = "Blue" },
        { id = 2, name = "Yellow" },
        { id = 3, name = "Purple" },
        { id = 4, name = "Green" },
        { id = 5, name = "Orange" },
        { id = 6, name = "Meta" },
        { id = 7, name = "Simple" },
        { id = 8, name = "Prismatic" },
    },
    [4]  = {
        { id = 0,  name = "Misc" },
        { id = 1,  name = "Cloth" },
        { id = 2,  name = "Leather" },
        { id = 3,  name = "Mail" },
        { id = 4,  name = "Plate" },
        { id = 6,  name = "Shield" },
        { id = 7,  name = "Libram" },
        { id = 8,  name = "Idol" },
        { id = 9,  name = "Totem" },
        { id = 10, name = "Sigil" },
        { id = 11, name = "Relic (Shaman)" },
    },
    [5]  = { { id = 0, name = "Reagent" } },
    [6]  = {
        { id = 2, name = "Arrow" },
        { id = 3, name = "Bullet" },
    },
    [7]  = {
        { id = 1,  name = "Parts" },
        { id = 2,  name = "Explosives" },
        { id = 3,  name = "Devices" },
        { id = 4,  name = "Jewelcrafting" },
        { id = 5,  name = "Cloth" },
        { id = 6,  name = "Leather" },
        { id = 7,  name = "Metal & Stone" },
        { id = 8,  name = "Meat" },
        { id = 9,  name = "Herb" },
        { id = 10, name = "Elemental" },
        { id = 11, name = "Other" },
        { id = 12, name = "Enchanting" },
    },
    [9]  = {
        { id = 0, name = "Book" },
        { id = 1, name = "Leatherworking" },
        { id = 2, name = "Tailoring" },
        { id = 3, name = "Engineering" },
        { id = 4, name = "Blacksmithing" },
        { id = 5, name = "Cooking" },
        { id = 6, name = "Alchemy" },
        { id = 7, name = "First Aid" },
        { id = 8, name = "Enchanting" },
        { id = 9, name = "Fishing" },
        { id = 10, name = "Jewelcrafting" },
    },
    [15] = {
        { id = 0, name = "Junk" },
        { id = 1, name = "Reagent" },
        { id = 2, name = "Companion Pet" },
        { id = 3, name = "Holiday" },
        { id = 4, name = "Other" },
        { id = 5, name = "Mount" },
    },
}

-- Parent groups for user-defined categories
local USER_CAT_PARENTS = {
    "Consumable", "Equipment", "Trade Goods", "Misc",
    "(none — standalone)",
}

-- ============================================================
-- Shared widget helpers
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
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function() cb:Click() end)
    return row
end

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
            if opt.value == v then idx = i; break end
        end
        idx = (idx % #options) + 1
        setter(options[idx].value)
        refresh()
        if WB.Bag and WB.Bag.ApplyOptionsUI then WB.Bag:ApplyOptionsUI() end
        if WB.Bag and WB.Bag.Refresh then WB.Bag:Refresh() end
    end)
    return b
end

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
        if button == "LeftButton" then setFromX(GetCursorPosition() / self:GetEffectiveScale()) end
    end)
    row:SetScript("OnShow", function() place(getter()) end)
    thumb._dragging = false
    thumb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self._dragging = true
            setFromX(GetCursorPosition() / self:GetEffectiveScale())
        end
    end)
    thumb:SetScript("OnMouseUp", function(self) self._dragging = false end)
    thumb:SetScript("OnUpdate", function(self)
        if not self._dragging then return end
        if not IsMouseButtonDown("LeftButton") then self._dragging = false; return end
        setFromX(GetCursorPosition() / self:GetEffectiveScale())
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

-- Small inline dropdown. options = { { id, name }, ... }. Returns frame with
-- :SetSelected(id), :GetSelected() -> id, and onChange callback field.
local function makeDropdown(parent, options, w, h)
    h = h or ROW_H
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w or 160, h)
    UI:NewTexture(btn, "BACKGROUND", { 0, 0, 0, 0.6 }):SetAllPoints(btn)
    UI:AddBorder(btn, UI.C_BORDER)
    local lbl = UI:NewText(btn, 10, UI.C_TEXT_NORMAL)
    lbl:SetPoint("LEFT", 5, 0)
    lbl:SetPoint("RIGHT", -16, 0)
    if lbl.SetWordWrap then lbl:SetWordWrap(false) end
    -- Chevron
    local chev = UI:NewText(btn, 10, UI.C_TEXT_DIM)
    chev:SetPoint("RIGHT", -3, 0)
    chev:SetText("v")

    local selected = options[1] and options[1].id
    local function refreshLabel()
        for _, o in ipairs(options) do
            if o.id == selected then lbl:SetText(o.name); return end
        end
        lbl:SetText("—")
    end
    refreshLabel()

    function btn:SetSelected(id)
        selected = id
        refreshLabel()
    end
    function btn:GetSelected() return selected end
    btn.onChange = nil  -- caller sets this

    -- Popup list
    local popup = CreateFrame("Frame", nil, parent)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetWidth(w or 160)
    UI:NewTexture(popup, "BACKGROUND", { UI.C_BG[1], UI.C_BG[2], UI.C_BG[3], 0.97 }):SetAllPoints(popup)
    UI:AddBorder(popup, UI.C_BORDER)
    popup:Hide()

    local ITEM_H = 18
    local rows = {}
    for i, opt in ipairs(options) do
        local row = CreateFrame("Button", nil, popup)
        row:SetHeight(ITEM_H)
        row:SetPoint("TOPLEFT",  popup, "TOPLEFT",  1, -(i - 1) * ITEM_H - 1)
        row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -(i - 1) * ITEM_H - 1)
        local hl = UI:NewTexture(row, "BACKGROUND", { UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 0 })
        hl:SetAllPoints(row)
        local txt2 = UI:NewText(row, 10, UI.C_TEXT_NORMAL)
        txt2:SetPoint("LEFT", 5, 0)
        txt2:SetText(opt.name)
        row:SetScript("OnEnter", function() hl:SetAlpha(0.15) end)
        row:SetScript("OnLeave", function() hl:SetAlpha(0) end)
        row:SetScript("OnClick", function()
            selected = opt.id
            refreshLabel()
            popup:Hide()
            if btn.onChange then btn.onChange(selected) end
        end)
        rows[i] = row
    end
    popup:SetHeight(#options * ITEM_H + 2)

    btn:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
        else
            popup:ClearAllPoints()
            popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
            popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -1)
            popup:Show()
            popup:Raise()
        end
    end)
    -- Close on outside click
    popup:SetScript("OnHide", function() end)

    btn._popup = popup
    return btn
end

-- Branded EditBox
local function makeEditBox(parent, w, h, placeholder)
    h = h or ROW_H
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w or 180, h)
    UI:NewTexture(f, "BACKGROUND", { 0, 0, 0, 0.55 }):SetAllPoints(f)
    UI:AddBorder(f, UI.C_BORDER)
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetPoint("TOPLEFT", 4, -3)
    eb:SetPoint("BOTTOMRIGHT", -4, 3)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1)
    eb:SetMaxLetters(64)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f._eb = eb
    f._placeholder = placeholder or ""
    -- Expose common EditBox methods on the wrapper frame
    function f:GetText() return eb:GetText() end
    function f:SetText(t) eb:SetText(t or "") end
    function f:SetFocus() eb:SetFocus() end
    function f:ClearFocus() eb:ClearFocus() end
    function f:SetScript(ev, fn) eb:SetScript(ev, fn) end
    return f
end

-- ============================================================
-- Tab system
-- ============================================================
local function makeTabs(parent, tabDefs, bodyFrame)
    -- tabDefs = { { label="General", build=fn }, { label="Rules", build=fn } }
    local TAB_H = 22
    local tabs = {}
    local bodies = {}
    local activeIdx = 1

    local function switchTo(idx)
        activeIdx = idx
        for i, t in ipairs(tabs) do
            local isActive = (i == idx)
            t._lbl:SetTextColor(
                isActive and UI.C_GREEN[1]    or UI.C_TEXT_DIM[1],
                isActive and UI.C_GREEN[2]    or UI.C_TEXT_DIM[2],
                isActive and UI.C_GREEN[3]    or UI.C_TEXT_DIM[3], 1)
            UI:NewTexture(t, "BACKGROUND", isActive and { 0.14, 0.11, 0.22, 1 } or { 0, 0, 0, 0.6 })
        end
        for i, b in ipairs(bodies) do
            if b then b:SetShown(i == idx) end
        end
    end

    local tabW = math.floor((PANEL_W - 24) / #tabDefs)
    for i, def in ipairs(tabDefs) do
        local t = CreateFrame("Button", nil, parent)
        t:SetHeight(TAB_H)
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", (i - 1) * tabW, 0)
        t:SetWidth(tabW)
        UI:NewTexture(t, "BACKGROUND", { 0, 0, 0, 0.6 }):SetAllPoints(t)
        UI:AddBorder(t, UI.C_BORDER)
        local lbl = UI:NewText(t, 10, UI.C_TEXT_DIM)
        lbl:SetPoint("CENTER")
        lbl:SetText(def.label)
        t._lbl = lbl
        t:SetScript("OnClick", function() switchTo(i) end)
        tabs[i] = t

        -- Build per-tab body (hidden child of bodyFrame)
        local b = CreateFrame("Frame", nil, bodyFrame)
        b:SetAllPoints(bodyFrame)
        b:Hide()
        if def.build then def.build(b) end
        bodies[i] = b
    end

    switchTo(1)
    return { switchTo = switchTo, bodies = bodies }
end

-- ============================================================
-- Rules tab
-- ============================================================
-- Stored in: WB.db.customRules.byItemId  [itemID]="Cat"
--            WB.db.customRules.byClass   [{classID,subClassID?,category}]
--            WB.db.customRules.patterns  [{match,category}]
--            WB.db.userCats              ["Cat"]={parent="Trade Goods"}

local rulesTab  -- forward ref; filled by buildRulesTab

-- Helper: collect all category names (built-in + user-defined), sorted.
local function allCategoryNames()
    local seen = {}
    local names = {}
    local builtIn = {
        "Equipment","Totem","Potion","Elixir","Flask","Scroll","Food",
        "Bandage","Consumable","Cloth","Leather","Metal & Stone","Herb",
        "Elemental","Enchanting","Jewelcrafting","Cooking","Trade Goods",
        "Soul Shard","Mount","Pet","Quest","Recipe","Gem","Container","Projectile",
        "Quiver","Key","Junk","Misc",
    }
    for _, n in ipairs(builtIn) do
        if not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
    if WB.db and WB.db.userCats then
        for n in pairs(WB.db.userCats) do
            if not seen[n] then seen[n] = true; names[#names + 1] = n end
        end
    end
    table.sort(names)
    return names
end

local function buildRulesTab(body)
    local RULE_ROW_H = 20
    local LIST_H     = 180  -- height of the scrollable rule list
    local FORM_Y     = LIST_H + 10

    -- --------------------------------------------------------
    -- Rule list (scrollable)
    -- --------------------------------------------------------
    local listClip = CreateFrame("Frame", nil, body)
    listClip:SetPoint("TOPLEFT", 0, 0)
    listClip:SetPoint("TOPRIGHT", 0, 0)
    listClip:SetHeight(LIST_H)
    listClip:SetClipsChildren(true)

    local listContent = CreateFrame("Frame", nil, listClip)
    listContent:SetPoint("TOPLEFT", 0, 0)
    listContent:SetPoint("TOPRIGHT", 0, 0)
    listContent:SetHeight(1)

    -- Scrollbar
    local sb = CreateFrame("Slider", nil, body)
    sb:SetOrientation("VERTICAL")
    sb:SetPoint("TOPRIGHT",    listClip, "TOPRIGHT",    18, 0)
    sb:SetPoint("BOTTOMRIGHT", listClip, "BOTTOMRIGHT", 18, 0)
    sb:SetWidth(8)
    sb:SetMinMaxValues(0, 0)
    sb:SetValue(0)
    sb:SetValueStep(RULE_ROW_H)
    UI:NewTexture(sb, "BACKGROUND", { 0, 0, 0, 0.4 }):SetAllPoints(sb)
    local sbThumb = UI:NewTexture(sb, "OVERLAY", UI.C_BORDER)
    sbThumb:SetSize(6, 24)
    sb:SetThumbTexture(sbThumb)

    local function scrollTo(v)
        local _, max = sb:GetMinMaxValues()
        if v < 0 then v = 0 end
        if v > max then v = max end
        listContent:SetPoint("TOPLEFT",  0, v)
        listContent:SetPoint("TOPRIGHT", 0, v)
        sb:SetValue(v)
    end
    listClip:EnableMouseWheel(true)
    listClip:SetScript("OnMouseWheel", function(_, d) scrollTo(sb:GetValue() - d * RULE_ROW_H * 2) end)
    sb:SetScript("OnValueChanged", function(_, v) scrollTo(v) end)

    -- Row pool for the list
    local rowPool = {}
    local function getRuleRow(idx)
        if not rowPool[idx] then
            local r = CreateFrame("Frame", nil, listContent)
            r:SetHeight(RULE_ROW_H)
            r:SetPoint("TOPLEFT",  listContent, "TOPLEFT",  0, -(idx - 1) * RULE_ROW_H)
            r:SetPoint("TOPRIGHT", listContent, "TOPRIGHT", -22, -(idx - 1) * RULE_ROW_H)

            local bg = UI:NewTexture(r, "BACKGROUND", { 0, 0, 0, idx % 2 == 0 and 0.18 or 0.06 })
            bg:SetAllPoints(r)

            local typeLbl = UI:NewText(r, 9, UI.C_TEXT_DIM)
            typeLbl:SetPoint("LEFT", 4, 0)
            typeLbl:SetWidth(44)
            if typeLbl.SetWordWrap then typeLbl:SetWordWrap(false) end
            r._typeLbl = typeLbl

            local descLbl = UI:NewText(r, 9, UI.C_TEXT_NORMAL)
            descLbl:SetPoint("LEFT", 52, 0)
            descLbl:SetPoint("RIGHT", -56, 0)
            if descLbl.SetWordWrap then descLbl:SetWordWrap(false) end
            r._descLbl = descLbl

            local catLbl = UI:NewText(r, 9, UI.C_GREEN)
            catLbl:SetPoint("RIGHT", -22, 0)
            catLbl:SetWidth(54)
            catLbl:SetJustifyH("RIGHT")
            if catLbl.SetWordWrap then catLbl:SetWordWrap(false) end
            r._catLbl = catLbl

            local delBtn = CreateFrame("Button", nil, r)
            delBtn:SetSize(16, 16)
            delBtn:SetPoint("RIGHT", -2, 0)
            local delX = UI:NewText(delBtn, 11, UI.C_TEXT_DIM)
            delX:SetPoint("CENTER")
            delX:SetText("\195\151")
            delBtn:SetScript("OnEnter", function() delX:SetTextColor(0.9, 0.2, 0.2, 1) end)
            delBtn:SetScript("OnLeave", function() delX:SetTextColor(UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], 1) end)
            r._delBtn = delBtn

            rowPool[idx] = r
        end
        rowPool[idx]:Show()
        return rowPool[idx]
    end
    local function hideRowsFrom(n)
        for i = n, #rowPool do rowPool[i]:Hide() end
    end

    -- Rebuild the visible list from saved vars
    local function rebuildList()
        local rules = WB.db.customRules or {}
        local entries = {}

        -- byItemId
        local byId = rules.byItemId or {}
        for itemID, cat in pairs(byId) do
            local name = GetItemInfo(itemID) or ("item:" .. itemID)
            entries[#entries + 1] = {
                kind = "item", display = name, cat = cat,
                del = function()
                    byId[itemID] = nil
                    WB:Emit("BAGS_DIRTY")
                    rebuildList()
                end,
            }
        end

        -- byClass
        for i, rule in ipairs(rules.byClass or {}) do
            local className = "?"
            for _, c in ipairs(ITEM_CLASSES) do
                if c.id == rule.classID then className = c.name; break end
            end
            local subName = ""
            if rule.subClassID ~= nil then
                local subs = ITEM_SUBCLASSES[rule.classID] or {}
                for _, s in ipairs(subs) do
                    if s.id == rule.subClassID then subName = " / " .. s.name; break end
                end
            end
            local idx = i
            entries[#entries + 1] = {
                kind = "class", display = className .. subName, cat = rule.category,
                del = function()
                    table.remove(rules.byClass, idx)
                    WB:Emit("BAGS_DIRTY")
                    rebuildList()
                end,
            }
        end

        -- patterns
        for i, rule in ipairs(rules.patterns or {}) do
            local idx = i
            entries[#entries + 1] = {
                kind = "name", display = '"' .. rule.match .. '"', cat = rule.category,
                del = function()
                    table.remove(rules.patterns, idx)
                    WB:Emit("BAGS_DIRTY")
                    rebuildList()
                end,
            }
        end

        -- userCats
        local userCats = WB.db.userCats or {}
        for name, info in pairs(userCats) do
            local n = name
            entries[#entries + 1] = {
                kind = "cat", display = name,
                cat = "parent: " .. (info.parent or "—"),
                del = function()
                    userCats[n] = nil
                    -- Remove any rules that pointed to this cat
                    for id, cat in pairs(byId) do
                        if cat == n then byId[id] = nil end
                    end
                    WB:Emit("BAGS_DIRTY")
                    rebuildList()
                end,
            }
        end

        -- Render
        for idx, entry in ipairs(entries) do
            local r = getRuleRow(idx)
            local typeColor = {
                item  = "|cffaaaaff",
                class = "|cffffcc44",
                name  = "|cff88ddaa",
                cat   = "|cff4FC778",
            }
            r._typeLbl:SetText((typeColor[entry.kind] or "") .. entry.kind:upper() .. "|r")
            r._descLbl:SetText(entry.display)
            r._catLbl:SetText(entry.cat)
            r._delBtn:SetScript("OnClick", entry.del)
        end
        hideRowsFrom(#entries + 1)

        local totalH = math.max(LIST_H, #entries * RULE_ROW_H)
        listContent:SetHeight(totalH)
        local overflow = math.max(0, #entries * RULE_ROW_H - LIST_H)
        sb:SetMinMaxValues(0, overflow)
        if overflow == 0 then sb:Hide() else sb:Show() end
        scrollTo(0)
    end

    -- Store rebuild fn so other code can call it
    body._rebuildList = rebuildList

    -- --------------------------------------------------------
    -- Column headers above the list
    -- --------------------------------------------------------
    local hType = UI:NewText(body, 9, UI.C_TEXT_DIM)
    hType:SetPoint("BOTTOMLEFT", listClip, "TOPLEFT", 4, 2)
    hType:SetText("TYPE")
    local hDesc = UI:NewText(body, 9, UI.C_TEXT_DIM)
    hDesc:SetPoint("BOTTOMLEFT", listClip, "TOPLEFT", 52, 2)
    hDesc:SetText("MATCH")
    local hCat = UI:NewText(body, 9, UI.C_TEXT_DIM)
    hCat:SetPoint("BOTTOMRIGHT", listClip, "TOPRIGHT", -22, 2)
    hCat:SetText("CATEGORY")

    -- Divider between list and form
    local div = UI:NewTexture(body, "ARTWORK", UI.C_BORDER)
    div:SetPoint("TOPLEFT",  body, "TOPLEFT",  0, -(LIST_H + 6))
    div:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -(LIST_H + 6))
    div:SetHeight(1)

    -- --------------------------------------------------------
    -- Add-rule form
    -- --------------------------------------------------------
    local FORM_PAD = 8
    local labelColor = UI.C_TEXT_DIM

    -- Rule type selector (cycle button)
    local ruleTypes = { "item", "class", "name", "new category" }
    local ruleTypeIdx = 1
    local ruleTypeBtn = CreateFrame("Button", nil, body)
    ruleTypeBtn:SetSize(110, ROW_H)
    ruleTypeBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(FORM_Y))
    UI:NewTexture(ruleTypeBtn, "BACKGROUND", { 0, 0, 0, 0.6 }):SetAllPoints(ruleTypeBtn)
    UI:AddBorder(ruleTypeBtn, UI.C_BORDER)
    local ruleTypeTxt = UI:NewText(ruleTypeBtn, 10, UI.C_GREEN)
    ruleTypeTxt:SetPoint("CENTER")

    -- Form fields (shown/hidden based on rule type)
    -- Item fields
    local itemPreview = UI:NewText(body, 10, UI.C_TEXT_NORMAL)
    itemPreview:SetPoint("TOPLEFT", body, "TOPLEFT", 118, -(FORM_Y + 4))
    itemPreview:SetText("|cffaaaaff[shift-click an item]|r")
    local pendingItemID = nil

    -- Class fields
    local classDD = makeDropdown(body, ITEM_CLASSES, 130, ROW_H)
    classDD:SetPoint("TOPLEFT", body, "TOPLEFT", 118, -(FORM_Y))

    local subclassDD = makeDropdown(body, { { id = -1, name = "(any subclass)" } }, 150, ROW_H)
    subclassDD:SetPoint("TOPLEFT", classDD, "TOPRIGHT", 4, 0)

    local function refreshSubclasses(classID)
        local subs = ITEM_SUBCLASSES[classID] or {}
        local opts = { { id = -1, name = "(any subclass)" } }
        for _, s in ipairs(subs) do opts[#opts + 1] = s end
        -- Rebuild popup rows
        local popup = subclassDD._popup
        local ITEM_H2 = 18
        -- Clear old rows
        local children = { popup:GetChildren() }
        for _, c in ipairs(children) do c:Hide(); c:SetParent(nil) end
        subclassDD._opts = opts
        for i, opt in ipairs(opts) do
            local row = CreateFrame("Button", nil, popup)
            row:SetHeight(ITEM_H2)
            row:SetPoint("TOPLEFT",  popup, "TOPLEFT",  1, -(i - 1) * ITEM_H2 - 1)
            row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -1, -(i - 1) * ITEM_H2 - 1)
            local hl2 = UI:NewTexture(row, "BACKGROUND", { UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 0 })
            hl2:SetAllPoints(row)
            local t2 = UI:NewText(row, 10, UI.C_TEXT_NORMAL)
            t2:SetPoint("LEFT", 5, 0)
            t2:SetText(opt.name)
            row:SetScript("OnEnter", function() hl2:SetAlpha(0.15) end)
            row:SetScript("OnLeave", function() hl2:SetAlpha(0) end)
            row:SetScript("OnClick", function()
                subclassDD:SetSelected(opt.id)
                popup:Hide()
                if subclassDD.onChange then subclassDD.onChange(opt.id) end
            end)
        end
        popup:SetHeight(#opts * ITEM_H2 + 2)
        subclassDD:SetSelected(-1)
    end
    classDD.onChange = function(id) refreshSubclasses(id) end
    refreshSubclasses(ITEM_CLASSES[1].id)

    -- Name pattern field
    local nameEB = makeEditBox(body, 280, ROW_H, "name contains...")
    nameEB:SetPoint("TOPLEFT", body, "TOPLEFT", 118, -(FORM_Y))

    -- New category fields
    local newCatEB = makeEditBox(body, 160, ROW_H, "category name...")
    newCatEB:SetPoint("TOPLEFT", body, "TOPLEFT", 118, -(FORM_Y))

    local parentLbl = UI:NewText(body, 9, labelColor)
    parentLbl:SetPoint("TOPLEFT", newCatEB, "TOPRIGHT", 6, -3)
    parentLbl:SetText("parent:")

    local parentOpts = {}
    for _, p in ipairs(USER_CAT_PARENTS) do
        parentOpts[#parentOpts + 1] = { id = p, name = p }
    end
    local parentDD = makeDropdown(body, parentOpts, 130, ROW_H)
    parentDD:SetPoint("TOPLEFT", parentLbl, "TOPRIGHT", 4, 3)

    -- Category target field (row 2 of the form — which cat to assign to)
    local catLblText = UI:NewText(body, 9, labelColor)
    catLblText:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(FORM_Y + ROW_H + 6))
    catLblText:SetText("assign to category:")

    local catEB = makeEditBox(body, 200, ROW_H, "category name...")
    catEB:SetPoint("TOPLEFT", body, "TOPLEFT", 118, -(FORM_Y + ROW_H + 6))

    -- Add button
    local addBtn = makeButton(body, "+ Add Rule", function()
        local ruleType = ruleTypes[ruleTypeIdx]
        local cat = catEB:GetText():match("^%s*(.-)%s*$")

        if ruleType == "new category" then
            local name = newCatEB:GetText():match("^%s*(.-)%s*$")
            if name == "" then return end
            local parent = parentDD:GetSelected()
            if parent == "(none — standalone)" then parent = nil end
            if not WB.db.userCats then WB.db.userCats = {} end
            WB.db.userCats[name] = { parent = parent }
            WB:Emit("BAGS_DIRTY")
            newCatEB:SetText("")
            rebuildList()
            return
        end

        if cat == "" then return end

        if ruleType == "item" then
            if not pendingItemID then return end
            if not WB.db.customRules then WB.db.customRules = {} end
            if not WB.db.customRules.byItemId then WB.db.customRules.byItemId = {} end
            WB.db.customRules.byItemId[pendingItemID] = cat
            pendingItemID = nil
            itemPreview:SetText("|cffaaaaff[shift-click an item]|r")

        elseif ruleType == "class" then
            local classID = classDD:GetSelected()
            local subID   = subclassDD:GetSelected()
            if not WB.db.customRules then WB.db.customRules = {} end
            if not WB.db.customRules.byClass then WB.db.customRules.byClass = {} end
            local rule = { classID = classID, category = cat }
            if subID ~= -1 then rule.subClassID = subID end
            table.insert(WB.db.customRules.byClass, rule)

        elseif ruleType == "name" then
            local match = nameEB:GetText():match("^%s*(.-)%s*$")
            if match == "" then return end
            if not WB.db.customRules then WB.db.customRules = {} end
            if not WB.db.customRules.patterns then WB.db.customRules.patterns = {} end
            table.insert(WB.db.customRules.patterns, { match = match, category = cat })
            nameEB:SetText("")
        end

        catEB:SetText("")
        WB:Emit("BAGS_DIRTY")
        rebuildList()
    end)
    addBtn:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)

    -- Hint text below the form
    local hintTxt = UI:NewText(body, 9, UI.C_TEXT_DIM)
    hintTxt:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 4)
    hintTxt:SetText("Shift-click any item in your bags to pre-fill the item rule.")

    -- Show/hide form fields based on current rule type
    local function applyRuleType()
        local t = ruleTypes[ruleTypeIdx]
        ruleTypeTxt:SetText(t == "new category" and "New Cat" or t:upper())

        itemPreview:SetShown(t == "item")
        classDD:SetShown(t == "class")
        subclassDD:SetShown(t == "class")
        nameEB:SetShown(t == "name")
        newCatEB:SetShown(t == "new category")
        parentLbl:SetShown(t == "new category")
        parentDD:SetShown(t == "new category")
        catLblText:SetShown(t ~= "new category")
        catEB:SetShown(t ~= "new category")
        addBtn:SetShown(true)
        hintTxt:SetShown(t == "item")
    end

    ruleTypeBtn:SetScript("OnClick", function()
        ruleTypeIdx = (ruleTypeIdx % #ruleTypes) + 1
        applyRuleType()
    end)
    applyRuleType()

    -- Expose for shift-click population from Bag.lua
    body._setItem = function(itemID, name)
        pendingItemID = itemID
        itemPreview:SetText("|cff4FC778" .. (name or ("item:" .. itemID)) .. "|r")
        ruleTypeIdx = 1   -- switch to "item" mode
        applyRuleType()
    end

    -- Initial populate
    body:SetScript("OnShow", rebuildList)
    rebuildList()

    rulesTab = body
end

-- ============================================================
-- General tab
-- ============================================================
local function buildGeneralTab(body)
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

    addPair(
        makeCheckbox(body, "Show item level",
            function() return WB.db.options.showItemLevel ~= false end,
            function(v) WB.db.options.showItemLevel = v end),
        makeCheckbox(body, "Show search box",
            function() return WB.db.options.showSearch end,
            function(v) WB.db.options.showSearch = v end))
    addPair(
        makeCheckbox(body, "Show junk",
            function() return WB.db.options.showJunk end,
            function(v) WB.db.options.showJunk = v end),
        makeCheckbox(body, "Show bottom bar",
            function() return WB.db.options.showBagBar end,
            function(v) WB.db.options.showBagBar = v end))
    addPair(
        makeCheckbox(body, "Highlight new items",
            function() return WB.db.options.showHighlights end,
            function(v) WB.db.options.showHighlights = v end),
        makeCheckbox(body, "Honor Points",
            function() return WB.db.options.showHonor end,
            function(v) WB.db.options.showHonor = v end))
    addPair(
        makeCheckbox(body, "Arena Points",
            function() return WB.db.options.showArena end,
            function(v) WB.db.options.showArena = v end),
        makeCheckbox(body, "Marks of Honor",
            function() return WB.db.options.showMarks end,
            function(v) WB.db.options.showMarks = v end))
    addPair(
        makeCheckbox(body, "Badges",
            function() return WB.db.options.showBadges end,
            function(v) WB.db.options.showBadges = v end),
        makeCheckbox(body, "Spirit Shards",
            function() return WB.db.options.showShards end,
            function(v) WB.db.options.showShards = v end))
    addPair(
        makeCheckbox(body, "Rep tokens",
            function() return WB.db.options.showRep end,
            function(v) WB.db.options.showRep = v end),
        makeCheckbox(body, "Use ItemRack sets",
            function() return WB.db.options.useItemRack ~= false end,
            function(v) WB.db.options.useItemRack = v end))

    local markBtn = makeButton(body, "Mark all items seen",
        function() if WB.Bag and WB.Bag.MarkAllSeen then WB.Bag:MarkAllSeen() end end)
    markBtn:SetParent(body)
    markBtn:ClearAllPoints()
    markBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
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
    panel:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    panel:Hide()

    UI:NewTexture(panel, "BACKGROUND", UI.C_BG):SetAllPoints(panel)
    UI:AddBorder(panel)
    UI:AddCornerAccents(panel)

    -- Header strip
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(24)
    UI:NewTexture(header, "BACKGROUND", UI.C_HEADER_BG):SetAllPoints(header)
    UI:AddTitleText(header, "Bags Options", "LEFT", 8, 0)
    local div = UI:NewTexture(header, "BORDER", UI.C_BORDER)
    div:SetPoint("BOTTOMLEFT"); div:SetPoint("BOTTOMRIGHT"); div:SetHeight(1)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -6, 0)
    local cx = UI:NewText(close, 14, UI.C_TEXT_DIM)
    cx:SetPoint("CENTER"); cx:SetText("\195\151")
    close:SetScript("OnClick",  function() panel:Hide() end)
    close:SetScript("OnEnter",  function() cx:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1) end)
    close:SetScript("OnLeave",  function() cx:SetTextColor(UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], 1) end)

    -- Tab bar sits just below the header
    local TAB_H = 22
    local tabBar = CreateFrame("Frame", nil, panel)
    tabBar:SetPoint("TOPLEFT",  panel, "TOPLEFT",  12, -28)
    tabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -28)
    tabBar:SetHeight(TAB_H)

    -- Body below tabs
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT",     panel, "TOPLEFT",  12, -(28 + TAB_H + 6))
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)

    panel._tabs = makeTabs(tabBar, {
        { label = "General", build = buildGeneralTab },
        { label = "Rules",   build = buildRulesTab   },
    }, body)

    self.panel = panel
    return panel
end

function OP:Toggle()
    self:Build()
    if self.panel:IsShown() then self.panel:Hide() else self.panel:Show() end
end

-- Called by Bag.lua on shift-click: opens the options panel on the Rules tab
-- and pre-fills the item fields.
function OP:OpenRulesForItem(itemID, name)
    self:Build()
    -- Switch to the Rules tab (index 2)
    if self.panel._tabs then self.panel._tabs.switchTo(2) end
    if rulesTab and rulesTab._setItem then
        rulesTab._setItem(itemID, name)
    end
    self.panel:Show()
    self.panel:Raise()
end
