-- Wick's Bags
-- Bank.lua: bank panel. Mirrors Bag.lua's structure but iterates the bank
-- containers (-1 main bank, 5..11 bank bags) and shows when BANKFRAME_OPENED
-- fires. Same brand chrome, same masonry layout, same Categories resolver.

local ADDON, ns = ...
local WB = WicksBags
local UI = WB.UI
local CT = WB.Categories

WB.Bank = {}
local BNK = WB.Bank

local MAX_PANEL_W   = 540
local MIN_PANEL_W   = 420
local HEADER_H      = 28
local SLOT_SIZE     = 32
local SLOT_GAP      = 3
local CATEGORY_H    = 18
local CAT_GAP_X     = 12
local CAT_GAP_Y     = 10
local SUB_GAP_X     = 10
local SUB_GAP_Y     = 4
local MAX_COLS_PER_CAT = 6
local PADDING       = 10
local BOTTOM_BUFFER = 14
local BAG_BAR_H     = 32

-- Bank container IDs (TBC):
--   -1     = main bank window (28 slots)
--   5..11  = bank bag containers (one per equipped bank bag)
local BANK_CONTAINER = -1
-- Use Blizzard's global if available, fall back to 7 (TBC default).
local NUM_BANKBAGSLOTS_LOCAL = NUM_BANKBAGSLOTS or 7
local function bankBagIDs()
    local t = { BANK_CONTAINER }
    for i = 1, NUM_BANKBAGSLOTS_LOCAL do
        t[#t + 1] = 4 + i   -- 5, 6, 7, ..., 11
    end
    return t
end
local BANK_BAG_IDS = bankBagIDs()

-- ============================================================
-- Slot widget (separate pool from Bag.lua so bank slots don't recycle bag
-- slot positions). Same template + behavior.
-- ============================================================
local slotPool = {}
local slotInUse = {}

-- Pickup helper — main bank container (-1) uses PickupBankItem(slot) on
-- this build; bank bags (5..11) use the normal container pickup. This
-- mirrors Blizzard's own bank UI dispatch.
local function pickupBankSlot(bag, slot)
    if bag == -1 and PickupBankItem then
        PickupBankItem(slot)
    elseif ns.PickupContainerItem then
        ns.PickupContainerItem(bag, slot)
    end
end

-- Find the first empty bank slot (across main bank + bank bags) and drop
-- the cursor item there. Used by the FREE aggregate tile, which represents
-- N empty bank slots but doesn't have a specific bag/slot of its own.
local function dropIntoFirstEmptyBank()
    for _, bag in ipairs(BANK_BAG_IDS) do
        local n = ns.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            if not ns.GetContainerItemLink(bag, slot) then
                pickupBankSlot(bag, slot)
                return
            end
        end
    end
end

local function buildSlot(parent, index)
    -- Mirror Bag.lua: ContainerFrameItemButtonTemplate with a hidden host
    -- whose :GetID() = bag. Blizzard's template OnClick handles secure
    -- dispatch (right-click bank slot while bank is open shuttles the
    -- item to the first empty bag slot — same behavior as our previous
    -- UseContainerItem path).
    local host = CreateFrame("Button", nil, parent)
    host:SetSize(SLOT_SIZE, SLOT_SIZE)

    local b = CreateFrame("Button", "WicksBankSlot" .. index, host,
        "ContainerFrameItemButtonTemplate")
    b:SetAllPoints(host)
    b._host = host
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if b.GetPushedTexture and b:GetPushedTexture() then b:GetPushedTexture():SetTexture("") end
    if b.GetNormalTexture and b:GetNormalTexture() then b:GetNormalTexture():SetTexture("") end
    -- Hide Blizzard's overlay textures so our quality border shows through.
    local btnName = b:GetName()
    for _, suffix in ipairs({
        "IconBorder", "IconQuestTexture", "NewItemTexture",
        "BattlepayItemTexture", "Stock", "JunkIcon", "ExtendedSlot",
    }) do
        local child = _G[btnName .. suffix] or b[suffix]
        if child and child.Hide then child:Hide() end
        if child and child.SetTexture then child:SetTexture("") end
    end
    -- Nuclear neutralization (same as Bag.lua) — reparent overlay textures
    -- to a permanently-hidden frame and noop their mutator methods.
    if not _G._WicksBagsHiddenHost then
        _G._WicksBagsHiddenHost = CreateFrame("Frame")
        _G._WicksBagsHiddenHost:Hide()
    end
    local hiddenHost = _G._WicksBagsHiddenHost
    local function neuter(tex)
        if not tex then return end
        if tex.SetParent then tex:SetParent(hiddenHost) end
        if tex.ClearAllPoints then tex:ClearAllPoints() end
        if tex.SetTexture then tex:SetTexture("") end
        if tex.SetVertexColor then tex:SetVertexColor(0, 0, 0, 0) end
        if tex.SetAlpha then tex:SetAlpha(0) end
        if tex.Hide then tex:Hide() end
        tex.Show = function() end
        tex.SetShown = function() end
        tex.SetTexture = function() end
        tex.SetVertexColor = function() end
        tex.SetAlpha = function() end
    end
    neuter(b.IconBorder)
    neuter(b.IconQuestTexture)
    neuter(b.NewItemTexture)
    neuter(b.BattlepayItemTexture)

    local name = b:GetName()
    b._iconTex   = _G[name .. "IconTexture"] or b.IconTexture
    b._countText = _G[name .. "Count"]       or b.Count

    local function edge(p1, p2, w, h)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    b._qTop    = edge("TOPLEFT",    "TOPRIGHT",    nil, 1)
    b._qBottom = edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    b._qLeft   = edge("TOPLEFT",    "BOTTOMLEFT",  1,   nil)
    b._qRight  = edge("TOPRIGHT",   "BOTTOMRIGHT", 1,   nil)
    local function setQualityBorder(c)
        for _, t in ipairs({ b._qTop, b._qBottom, b._qLeft, b._qRight }) do
            t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
    b._setQualityBorder = setQualityBorder
    setQualityBorder({ 0.20, 0.18, 0.34, 1 })

    -- Item-level overlay (top-left)
    local ilvl = b:CreateFontString(nil, "OVERLAY")
    ilvl:SetFont("Fonts\\ARIALN.TTF", 10, "OUTLINE")
    ilvl:SetPoint("TOPLEFT", 1, -1)
    ilvl:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1)
    ilvl:SetText("")
    b._ilvlText = ilvl

    -- HookScript (not SetScript) — preserves the template's hover-highlight
    -- show/hide which we'd otherwise leave stuck on the slot after mouseout.
    b:HookScript("OnEnter", function(self)
        if not self._bag or not self._slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- Main bank container (-1) needs SetInventoryItem; SetBagItem(-1, slot)
        -- does not populate the tooltip in TBC 2.5.x. Bank bags (5..11) are
        -- normal containers and the standard path works for those.
        if self._bag == BANK_CONTAINER and BankButtonIDToInvSlotID then
            GameTooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(self._slot))
        else
            GameTooltip:SetBagItem(self._bag, self._slot)
        end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- HookScript (not SetScript) — preserves Blizzard template's secure
    -- OnClick/OnReceiveDrag dispatch. Our hooks only fire for FREE tiles
    -- (no real bag/slot) which the template can't address.
    b:HookScript("OnClick", function(self, button)
        if button == "LeftButton" and CursorHasItem and CursorHasItem()
           and (not self._bag or not self._slot) then
            dropIntoFirstEmptyBank()
        end
    end)
    b:HookScript("OnReceiveDrag", function(self)
        if not self._bag or not self._slot then
            dropIntoFirstEmptyBank()
        end
    end)

    return b
end

local function acquireSlot(parent, index)
    local b = slotPool[index] or buildSlot(parent, index)
    slotPool[index] = b
    local host = b._host or b
    host:SetParent(parent)
    host:Show()
    b:Show()
    slotInUse[index] = true
    return b
end

local function releaseAll()
    for i = 1, #slotPool do
        if slotInUse[i] then
            local b = slotPool[i]
            local host = b._host or b
            host:Hide()
            host:ClearAllPoints()
            slotInUse[i] = false
        end
    end
end

local function dressSlot(b, bag, slot, itemID, link, count, quality, icon, locked)
    b._bag, b._slot = bag, slot
    -- Wire IDs the template's OnClick reads:
    --   self:GetID() = slot, self:GetParent():GetID() = bag
    if b._host then b._host:SetID(bag or 0) end
    b:SetID(slot or 0)

    if itemID and icon then
        b._iconTex:SetTexture(icon)
        b._iconTex:Show()
        if count and count > 1 then
            b._countText:SetText(tostring(count))
            b._countText:Show()
        else
            b._countText:SetText("")
        end
        local q = quality or 1
        local qc = UI.C_QUALITY[q] or UI.C_QUALITY[1]
        local intensity = WB.db.options.borderIntensity or 1.0
        if intensity <= 1.0 then
            b._setQualityBorder({ qc[1], qc[2], qc[3], (qc[4] or 1) * intensity })
        else
            local boost = math.min(intensity - 1.0, 1.0)
            local rr = math.min(1.0, qc[1] + (1 - qc[1]) * boost)
            local gg = math.min(1.0, qc[2] + (1 - qc[2]) * boost)
            local bb = math.min(1.0, qc[3] + (1 - qc[3]) * boost)
            b._setQualityBorder({ rr, gg, bb, 1 })
        end

        if WB.db.options.showItemLevel ~= false then
            local _, _, _, _, _, classID = GetItemInfoInstant(itemID)
            if classID == 2 or classID == 4 then
                local _, _, _, ilvlVal = GetItemInfo(itemID)
                if ilvlVal and ilvlVal > 1 then
                    b._ilvlText:SetText(tostring(ilvlVal))
                    b._ilvlText:Show()
                else
                    b._ilvlText:SetText("")
                end
            else
                b._ilvlText:SetText("")
            end
        else
            b._ilvlText:SetText("")
        end
    else
        b._iconTex:SetTexture(nil)
        b._setQualityBorder({ 0.20, 0.18, 0.34, 1 })
        if b._ilvlText then b._ilvlText:SetText("") end
        if count and count > 0 then
            b._countText:SetText(tostring(count))
            b._countText:Show()
        else
            b._countText:SetText("")
        end
    end

    if b._iconTex then
        b._iconTex:SetDesaturated(locked and true or false)
    end
end

-- ============================================================
-- Header / container pools
-- ============================================================
local categoryHeaders = {}
local function getCategoryHeader(parent, index)
    local h = categoryHeaders[index]
    if not h then
        local f = CreateFrame("Frame", nil, parent)
        f:SetHeight(CATEGORY_H)
        local label = UI:NewText(f, 8, UI.C_TEXT_DIM)
        label:SetPoint("BOTTOM", 0, 3)
        label:SetText("")
        if label.SetWordWrap then label:SetWordWrap(false) end
        f._label = label
        h = f
        categoryHeaders[index] = h
    end
    h:SetParent(parent); h:Show()
    return h
end
local function hideUnusedHeaders(usedCount)
    for i = usedCount + 1, #categoryHeaders do
        categoryHeaders[i]:Hide()
        categoryHeaders[i]:ClearAllPoints()
    end
end

local groupContainers = {}
local GROUP_HEADER_H = 16
local GROUP_PAD_X    = 6
local GROUP_PAD_TOP  = GROUP_HEADER_H + 2
local GROUP_PAD_BOT  = 6

local _measureFS
local function measureHeaderWidth(text)
    if not _measureFS then
        _measureFS = UIParent:CreateFontString(nil, "OVERLAY")
        _measureFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        _measureFS:Hide()
    end
    _measureFS:SetText(text or "")
    return _measureFS:GetStringWidth() or 0
end

local function getGroupContainer(parent, index)
    local f = groupContainers[index]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        UI:AddBorder(f, UI.C_BORDER)
        local label = UI:NewText(f, 10, UI.C_GREEN)
        label:SetPoint("TOP", 0, -3)
        f._label = label
        groupContainers[index] = f
    end
    f:SetParent(parent); f:Show()
    return f
end
local function hideUnusedGroups(usedCount)
    for i = usedCount + 1, #groupContainers do
        groupContainers[i]:Hide()
        groupContainers[i]:ClearAllPoints()
    end
end

-- ============================================================
-- Gather items from all bank containers.
-- ============================================================
local function gatherItems()
    local items = {}
    local filterBag = WB.db.ui and WB.db.ui._filterBankBag
    for _, bag in ipairs(BANK_BAG_IDS) do
        if filterBag == nil or filterBag == bag then
            local n = ns.GetContainerNumSlots(bag) or 0
            for slot = 1, n do
                local link = ns.GetContainerItemLink(bag, slot)
                local itemID = ns.GetContainerItemID and ns.GetContainerItemID(bag, slot)
                           or (link and tonumber(link:match("item:(%d+)")))
                local icon, count, locked, quality = ns.GetContainerItemInfo(bag, slot)
                items[#items + 1] = {
                    bag = bag, slot = slot,
                    itemID = itemID, link = link,
                    count = count or 0, quality = quality,
                    icon = icon, locked = locked,
                }
            end
        end
    end
    return items
end

local function applySearchFilter(items, term)
    if not term or term == "" then return items end
    term = term:lower()
    local out = {}
    for _, it in ipairs(items) do
        if it.link and it.link:lower():find(term, 1, true) then
            out[#out + 1] = it
        end
    end
    return out
end

-- ============================================================
-- Build the panel
-- ============================================================
local function buildPanel()
    local cfg = WB.db.options   -- feature toggles (not position)
    local pos = WB.db.bankPos  -- pre-seeded in DB_DEFAULTS; always exists

    local panel = CreateFrame("Frame", "WicksBankPanel", UIParent)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:SetResizable(true)
    if panel.SetResizeBounds then
        panel:SetResizeBounds(MIN_PANEL_W, 120, 1000, UIParent:GetHeight() - 40)
    elseif panel.SetMinResize then
        panel:SetMinResize(MIN_PANEL_W, 120)
        panel:SetMaxResize(1000, UIParent:GetHeight() - 40)
    end
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:ClearAllPoints()

    local startW = (pos.panelW and pos.panelW > 0) and pos.panelW or MAX_PANEL_W
    panel:SetSize(startW, 200)
    if pos.posPoint and pos.posPoint ~= false then
        panel:SetPoint(pos.posPoint, UIParent, pos.posRel, pos.posX or 0, pos.posY or 0)
    else
        panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 120, 240)
    end

    UI:NewTexture(panel, "BACKGROUND", UI.C_BG):SetAllPoints(panel)
    UI:AddBorder(panel)
    UI:AddCornerAccents(panel)

    local function snapPosition()
        local p, _, rp, x, y = panel:GetPoint()
        if not p then return end
        local t = WB.db.bankPos
        t.posPoint = p;  t.posRel = rp or p;  t.posX = x or 0;  t.posY = y or 0;  t.panelW = panel:GetWidth()
    end
    panel._snapPosition = snapPosition

    panel:SetScript("OnMouseDown", function(self) self:Raise() end)
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing(); snapPosition()
    end)

    -- Header strip
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT",  panel, "TOPLEFT",  1, -1)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    UI:NewTexture(header, "BACKGROUND", UI.C_HEADER_BG):SetAllPoints(header)
    local divider = UI:NewTexture(header, "BORDER", UI.C_BORDER)
    divider:SetPoint("BOTTOMLEFT"); divider:SetPoint("BOTTOMRIGHT"); divider:SetHeight(1)

    -- Title (left)
    local titleL, titleR = UI:AddTitleText(header, "Bank", "LEFT", 8, 0)

    -- Close X (rightmost)
    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    local x = UI:NewText(close, 14, UI.C_TEXT_DIM)
    x:SetPoint("CENTER")
    x:SetText("\195\151")
    -- Closing Wick's Bank also ends the bank session — otherwise the
    -- user would still be "at the banker" silently and the next bag-update
    -- would re-pop the panel. CloseBankFrame fires BANKFRAME_CLOSED.
    close:SetScript("OnClick", function()
        if CloseBankFrame then CloseBankFrame() end
        WB.Bank:Hide()
    end)
    close:SetScript("OnEnter", function() x:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1) end)
    close:SetScript("OnLeave", function() x:SetTextColor(UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], 1) end)

    -- Search input (center-aligned)
    local search = CreateFrame("EditBox", nil, header)
    search:SetSize(110, 16)
    search:SetPoint("CENTER", header, "CENTER", 0, 0)
    search:SetAutoFocus(false)
    search:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    search:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1)
    search:SetMaxLetters(40)
    search:SetText("")
    UI:AddBorder(search)
    UI:NewTexture(search, "BACKGROUND", UI.C_BG):SetAllPoints(search)
    search:SetTextInsets(4, 4, 0, 0)
    panel._search = search
    local placeholder = UI:NewText(search, 10, UI.C_TEXT_DIM)
    placeholder:SetPoint("LEFT", 4, 0)
    placeholder:SetText("search bank")
    search:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        if WB.Bank and WB.Bank.Refresh then WB.Bank:Refresh() end
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() self:SetText("") end)

    -- Body host
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT",     panel, "TOPLEFT",     PADDING, -(HEADER_H + PADDING))
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING,   PADDING + BAG_BAR_H)
    panel._body = body

    -- Bottom bar — buy slot button (left), bag-slot icons (middle), gold (right).
    local botBar = CreateFrame("Frame", nil, panel)
    botBar:SetHeight(BAG_BAR_H - 4)
    botBar:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT",   PADDING, PADDING)
    botBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING, PADDING)
    UI:NewTexture(botBar, "BACKGROUND", UI.C_HEADER_BG):SetAllPoints(botBar)
    local botBarBorder = UI:NewTexture(botBar, "BORDER", UI.C_BORDER)
    botBarBorder:SetPoint("TOPLEFT");    botBarBorder:SetPoint("TOPRIGHT")
    botBarBorder:SetHeight(1)
    panel._botBar = botBar
    -- Right-click on the empty area of the bottom bar clears any active
    -- bank-bag filter — discoverable escape hatch for "I don't remember
    -- which icon I clicked".
    botBar:EnableMouse(true)
    botBar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and WB.db.ui._filterBankBag then
            WB.db.ui._filterBankBag = nil
            if botBar.Refresh then botBar:Refresh() end
            if WB.Bank and WB.Bank.Refresh then WB.Bank:Refresh() end
        end
    end)

    -- Buy slot button (left). Hidden if all 7 bank bag slots already purchased.
    local buyBtn = CreateFrame("Button", nil, botBar)
    buyBtn:SetSize(86, 18)
    buyBtn:SetPoint("LEFT", 4, 0)
    UI:NewTexture(buyBtn, "BACKGROUND", { 0, 0, 0, 0.6 }):SetAllPoints(buyBtn)
    UI:AddBorder(buyBtn, UI.C_BORDER)
    local buyTxt = UI:NewText(buyBtn, 10, UI.C_TEXT_NORMAL)
    buyTxt:SetPoint("CENTER")
    buyTxt:SetText("Buy slot")
    buyBtn:SetScript("OnEnter", function()
        buyTxt:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1)
        local cost = GetBankSlotCost and GetBankSlotCost(GetNumBankSlots and GetNumBankSlots() or 0)
        if cost then
            GameTooltip:SetOwner(buyBtn, "ANCHOR_TOP")
            GameTooltip:AddLine("Buy next bank bag slot", 1, 1, 1)
            GameTooltip:AddLine("Cost: " .. UI:FormatMoney(cost),
                UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3])
            GameTooltip:Show()
        end
    end)
    buyBtn:SetScript("OnLeave", function()
        buyTxt:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1)
        GameTooltip:Hide()
    end)
    buyBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        -- Blizzard's confirmation dialog — opens the buy-slot popup.
        if PurchaseSlot then
            local cost = GetBankSlotCost and GetBankSlotCost(GetNumBankSlots and GetNumBankSlots() or 0)
            if cost and StaticPopup_Show then
                StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
            else
                PurchaseSlot()
            end
        end
    end)
    panel._buyBtn = buyBtn

    -- Bank bag icons (left of gold). Show only the bag slots the player
    -- owns. Click filters the bank panel to that bank-bag's contents
    -- (mirrors the bag panel's right-click bag-filter). Click again on
    -- the same icon (or anywhere off-icon) to clear the filter.
    botBar._slots = {}
    local bankSlotSize = 22
    for i = 1, NUM_BANKBAGSLOTS_LOCAL do
        local btn = CreateFrame("Button", nil, botBar)
        btn:SetSize(bankSlotSize, bankSlotSize)
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(btn)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        UI:AddBorder(btn)
        -- Filter highlight overlay (shown when this bag is the active filter)
        local hilite = btn:CreateTexture(nil, "OVERLAY")
        hilite:SetColorTexture(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 0.25)
        hilite:SetPoint("TOPLEFT", -1, 1)
        hilite:SetPoint("BOTTOMRIGHT", 1, -1)
        hilite:Hide()
        btn._icon = icon
        btn._hilite = hilite
        btn._index = i
        btn._bag = 4 + i   -- container ID 5..11
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local invID = ns.ContainerIDToInventoryID and ns.ContainerIDToInventoryID(4 + i) or nil
            if invID then GameTooltip:SetInventoryItem("player", invID) end
            GameTooltip:AddLine(("Bank Bag %d"):format(i),
                UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3])
            GameTooltip:AddLine("Left-click: open this bag", 1, 1, 1)
            GameTooltip:AddLine("Right-click: toggle filter (click again to clear)",
                UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3])
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                -- Toggle filter for this bank bag.
                WB.db.ui._filterBankBag = (WB.db.ui._filterBankBag == self._bag) and nil or self._bag
                if botBar.Refresh then botBar:Refresh() end
                if WB.Bank and WB.Bank.Refresh then WB.Bank:Refresh() end
                return
            end
            -- Left-click: open the specific bank bag in Blizzard's container UI
            -- (lets the user interact with it as its own window if desired).
            if InCombatLockdown() then return end
            if ToggleBag then ToggleBag(self._bag)
            elseif OpenBag then OpenBag(self._bag) end
        end)
        botBar._slots[i] = btn
    end

    -- Main-bank icon (left of bank bag icons). Right-click toggles filter
    -- to main bank only. (No left-click "open" — main bank has no separate
    -- window; the items are already in the unified panel.)
    local mainBankBtn = CreateFrame("Button", nil, botBar)
    mainBankBtn:SetSize(bankSlotSize, bankSlotSize)
    mainBankBtn:EnableMouse(true)
    mainBankBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local mbIcon = mainBankBtn:CreateTexture(nil, "ARTWORK")
    mbIcon:SetAllPoints(mainBankBtn)
    mbIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mbIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_07_Black")
    UI:AddBorder(mainBankBtn)
    local mbHilite = mainBankBtn:CreateTexture(nil, "OVERLAY")
    mbHilite:SetColorTexture(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 0.25)
    mbHilite:SetPoint("TOPLEFT", -1, 1)
    mbHilite:SetPoint("BOTTOMRIGHT", 1, -1)
    mbHilite:Hide()
    mainBankBtn._hilite = mbHilite
    mainBankBtn._bag = -1
    mainBankBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Main Bank", 1, 1, 1)
        GameTooltip:AddLine("Right-click: filter to main bank only",
            UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3])
        GameTooltip:Show()
    end)
    mainBankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainBankBtn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            WB.db.ui._filterBankBag = (WB.db.ui._filterBankBag == -1) and nil or -1
            if botBar.Refresh then botBar:Refresh() end
            if WB.Bank and WB.Bank.Refresh then WB.Bank:Refresh() end
        end
    end)
    botBar._mainBankBtn = mainBankBtn

    -- Gold display (far right)
    local goldText = UI:NewText(botBar, 11, UI.C_TEXT_NORMAL)
    goldText:SetPoint("RIGHT", botBar, "RIGHT", -8, 0)
    goldText:SetText(UI:FormatMoney(GetMoney()))
    botBar._gold = goldText
    panel._gold = goldText
    WB:On("MONEY_CHANGED", function() goldText:SetText(UI:FormatMoney(GetMoney())) end)

    function botBar:Refresh()
        -- Bank bag icons: show only purchased slots, with filter highlight.
        local numPurchased = (GetNumBankSlots and GetNumBankSlots()) or 0
        local activeFilter = WB.db.ui._filterBankBag
        local prev = self._gold
        for i = NUM_BANKBAGSLOTS_LOCAL, 1, -1 do
            local btn = self._slots[i]
            if i <= numPurchased then
                local invID = ns.ContainerIDToInventoryID and ns.ContainerIDToInventoryID(4 + i) or nil
                local tex = invID and GetInventoryItemTexture("player", invID)
                            or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
                btn._icon:SetTexture(tex)
                if btn._hilite then btn._hilite:SetShown(activeFilter == btn._bag) end
                btn:ClearAllPoints()
                btn:SetPoint("RIGHT", prev, "LEFT", -6, 0)
                btn:Show()
                prev = btn
            else
                btn:Hide()
            end
        end
        -- Main-bank filter icon: anchor left of the rightmost visible bag
        if self._mainBankBtn then
            self._mainBankBtn._hilite:SetShown(activeFilter == -1)
            self._mainBankBtn:ClearAllPoints()
            self._mainBankBtn:SetPoint("RIGHT", prev, "LEFT", -6, 0)
            self._mainBankBtn:Show()
        end
        -- Buy slot button visibility
        if numPurchased >= NUM_BANKBAGSLOTS_LOCAL then
            panel._buyBtn:Hide()
        else
            panel._buyBtn:Show()
        end
        -- Gold
        if self._gold then self._gold:SetText(UI:FormatMoney(GetMoney())) end
    end
    botBar:Refresh()

    -- Resize grip
    local grip = CreateFrame("Button", nil, panel)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    grip:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            panel._isResizing = true
            panel:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function()
        panel:StopMovingOrSizing()
        panel._isResizing = false
        if panel._snapPosition then panel._snapPosition() end
        if WB.Bank and WB.Bank.Refresh then WB.Bank:Refresh() end
    end)

    local resizePending = false
    panel:SetScript("OnSizeChanged", function()
        if resizePending then return end
        resizePending = true
        C_Timer.After(0.05, function()
            resizePending = false
            if WB.Bank and WB.Bank.Refresh then WB.Bank:Refresh() end
        end)
    end)

    return panel
end

-- ============================================================
-- Main refresh — masonry layout pipeline
-- ============================================================
function BNK:Refresh()
    if not self.panel then return end
    if not self.panel:IsShown() then return end

    if CT.RefreshItemRack then CT:RefreshItemRack() end

    local body = self.panel._body
    local bodyW = body:GetWidth()

    local items = gatherItems()
    local term = self.panel._search and self.panel._search:GetText() or ""
    items = applySearchFilter(items, term)

    local slotScale = WB.db.options.slotScale or 1.0
    local slotSize  = math.floor(SLOT_SIZE * slotScale)
    local SLOT_W    = slotSize + SLOT_GAP

    -- Bucket by category. Empty slots condense into one Free tile.
    local buckets = {}
    local freeCount = 0
    for _, it in ipairs(items) do
        if not it.itemID then
            freeCount = freeCount + 1
        else
            local cat = CT:GetCategory(it.itemID, it.link) or "Misc"
            buckets[cat] = buckets[cat] or {}
            table.insert(buckets[cat], it)
        end
    end
    if freeCount > 0 then
        buckets["Free"] = { { itemID = nil, count = freeCount, isFreeAggregate = true } }
    end

    if not WB.db.options.showJunk then buckets["Junk"] = nil end

    local qMin = WB.db.options.qualityMin or 0
    if qMin > 0 then
        for cat, bucket in pairs(buckets) do
            if cat ~= "Free" then
                local kept = {}
                for _, it in ipairs(bucket) do
                    if (it.quality or 0) >= qMin then kept[#kept + 1] = it end
                end
                if #kept == 0 then buckets[cat] = nil else buckets[cat] = kept end
            end
        end
    end

    local mode = WB.db.options.sortMode or "quality"
    local function nameOf(it)
        if it._sortName then return it._sortName end
        local n = ""
        if it.link then n = (it.link:match("%[(.-)%]") or ""):lower() end
        it._sortName = n
        return n
    end
    local sortFns = {
        quality = function(a, b)
            local qa, qb = a.quality or 0, b.quality or 0
            if qa ~= qb then return qa > qb end
            return nameOf(a) < nameOf(b)
        end,
        name = function(a, b) return nameOf(a) < nameOf(b) end,
        quantity = function(a, b)
            local ca, cb = a.count or 1, b.count or 1
            if ca ~= cb then return ca > cb end
            return nameOf(a) < nameOf(b)
        end,
    }
    local sortFn = sortFns[mode] or sortFns.quality
    for _, bucket in pairs(buckets) do
        table.sort(bucket, sortFn)
    end

    -- Build block specs
    releaseAll()
    local ordered = CT:OrderedCategories()
    local blocks = {}
    local seenCat = {}
    local function addBlock(cat, bucket)
        if not bucket or #bucket == 0 then return end
        local n = #bucket
        local blkCols = math.min(n, MAX_COLS_PER_CAT)
        local blkRows = math.ceil(n / blkCols)
        blocks[#blocks + 1] = {
            cat = cat, items = bucket,
            cols = blkCols, rows = blkRows,
            slotW = blkCols * SLOT_W - SLOT_GAP,
        }
    end
    for _, cat in ipairs(ordered) do
        if cat ~= "Recent" then   -- Recent doesn't apply to bank items
            seenCat[cat] = true
            addBlock(cat, buckets[cat])
        end
    end
    local extras = {}
    for cat in pairs(buckets) do
        if not seenCat[cat] and cat ~= "Recent" then extras[#extras + 1] = cat end
    end
    table.sort(extras)
    for _, cat in ipairs(extras) do
        addBlock(cat, buckets[cat])
    end

    -- Group blocks by parent class
    local groups = {}
    local groupByParent = {}
    for _, blk in ipairs(blocks) do
        local parent = CT:GetParent(blk.cat)
        local g = groupByParent[parent]
        if not g then
            g = { parent = parent, blocks = {} }
            groupByParent[parent] = g
            groups[#groups + 1] = g
        end
        g.blocks[#g.blocks + 1] = blk
    end

    for _, g in ipairs(groups) do
        local soleIsItemRackSet = (#g.blocks == 1)
            and CT.IsItemRackSetName
            and CT:IsItemRackSetName(g.blocks[1].cat)
        if #g.blocks == 1 and not soleIsItemRackSet then
            g.containerHeader      = g.blocks[1].cat:upper()
            g.blocks[1].skipHeader = true
        else
            g.containerHeader = g.parent:upper()
        end
        for _, blk in ipairs(g.blocks) do
            local minW = blk.slotW
            if not blk.skipHeader then
                local headerW = measureHeaderWidth(blk.cat:upper())
                if headerW + 4 > minW then minW = headerW + 4 end
            end
            blk.w = minW
            blk.h = CATEGORY_H + blk.rows * SLOT_W - SLOT_GAP
        end
    end

    -- Pass 1: masonry within each group
    for _, g in ipairs(groups) do
        local availW = bodyW - GROUP_PAD_X * 2
        local placed = {}
        local function overlapsSub(x, y, w, h)
            for _, p in ipairs(placed) do
                if x < p.x + p.w + SUB_GAP_X
                   and x + w + SUB_GAP_X > p.x
                   and y < p.y + p.h + SUB_GAP_Y
                   and y + h + SUB_GAP_Y > p.y
                then return true end
            end
            return false
        end
        local subMaxW = 0
        local subTotalH = 0
        for _, blk in ipairs(g.blocks) do
            local xs, ys = { 0 }, { 0 }
            for _, p in ipairs(placed) do
                xs[#xs + 1] = p.x + p.w + SUB_GAP_X
                ys[#ys + 1] = p.y + p.h + SUB_GAP_Y
            end
            table.sort(ys); table.sort(xs)
            local px, py
            for _, y in ipairs(ys) do
                for _, x in ipairs(xs) do
                    if x + blk.w <= availW and not overlapsSub(x, y, blk.w, blk.h) then
                        px, py = x, y; break
                    end
                end
                if px then break end
            end
            if not px then
                px, py = 0, subTotalH + (subTotalH > 0 and SUB_GAP_Y or 0)
            end
            blk.subX, blk.subY = px, py
            placed[#placed + 1] = { x = px, y = py, w = blk.w, h = blk.h }
            if px + blk.w > subMaxW then subMaxW = px + blk.w end
            if py + blk.h > subTotalH then subTotalH = py + blk.h end
        end
        local headerW = measureHeaderWidth(g.containerHeader) + 12
        g.w = math.max(subMaxW + GROUP_PAD_X * 2, headerW)
        g.h = GROUP_PAD_TOP + subTotalH + GROUP_PAD_BOT
    end

    -- Pass 2: try multiple orderings, pick shortest
    local function tryPack(order)
        local placed = {}
        local function overlapsAny(x, y, w, h)
            for _, p in ipairs(placed) do
                if x < p.x + p.w + CAT_GAP_X
                   and x + w + CAT_GAP_X > p.x
                   and y < p.y + p.h + CAT_GAP_Y
                   and y + h + CAT_GAP_Y > p.y
                then return true end
            end
            return false
        end
        local positions = {}
        local totalH = 0
        for _, g in ipairs(order) do
            local xs, ys = { 0 }, { 0 }
            for _, p in ipairs(placed) do
                xs[#xs + 1] = p.x + p.w + CAT_GAP_X
                ys[#ys + 1] = p.y + p.h + CAT_GAP_Y
            end
            table.sort(ys); table.sort(xs)
            local px, py
            for _, y in ipairs(ys) do
                for _, x in ipairs(xs) do
                    if x + g.w <= bodyW and not overlapsAny(x, y, g.w, g.h) then
                        px, py = x, y; break
                    end
                end
                if px then break end
            end
            if not px then
                px, py = 0, totalH + (totalH > 0 and CAT_GAP_Y or 0)
            end
            positions[g] = { x = px, y = py }
            placed[#placed + 1] = { x = px, y = py, w = g.w, h = g.h }
            if py + g.h > totalH then totalH = py + g.h end
        end
        return totalH, positions
    end

    local function copyOrder()
        local out = {}
        for i, g in ipairs(groups) do out[i] = g end
        return out
    end
    local orderings = { copyOrder(), copyOrder(), copyOrder(), copyOrder() }
    table.sort(orderings[2], function(a, b) return a.h > b.h end)
    table.sort(orderings[3], function(a, b) return a.w > b.w end)
    table.sort(orderings[4], function(a, b) return a.w * a.h > b.w * b.h end)

    local bestH, bestPositions = math.huge, nil
    for _, ord in ipairs(orderings) do
        local h, pos = tryPack(ord)
        if h < bestH then bestH = h; bestPositions = pos end
    end

    local totalH = bestH
    for _, g in ipairs(groups) do
        local p = bestPositions[g]
        g.x, g.y = p.x, p.y
    end

    -- Render
    local nextHeaderIdx = 1
    local nextSlotIdx   = 1
    local nextGroupIdx  = 0
    for _, g in ipairs(groups) do
        nextGroupIdx = nextGroupIdx + 1
        local container = getGroupContainer(body, nextGroupIdx)
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", body, "TOPLEFT", g.x, -g.y)
        container:SetSize(g.w, g.h)
        container._label:SetText(g.containerHeader)

        local subBaseX = g.x + GROUP_PAD_X
        local subBaseY = g.y + GROUP_PAD_TOP

        for _, blk in ipairs(g.blocks) do
            if not blk.skipHeader then
                local h = getCategoryHeader(body, nextHeaderIdx)
                nextHeaderIdx = nextHeaderIdx + 1
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", body, "TOPLEFT", subBaseX + blk.subX, -(subBaseY + blk.subY))
                h:SetWidth(blk.w)
                h._label:SetText(blk.cat:upper())
            end

            local slotsYOffset = CATEGORY_H
            local slotsXOffset = math.floor((blk.w - blk.slotW) / 2)
            if slotsXOffset < 0 then slotsXOffset = 0 end
            for j, it in ipairs(blk.items) do
                local col = (j - 1) % blk.cols
                local row = math.floor((j - 1) / blk.cols)
                local sx2 = subBaseX + blk.subX + slotsXOffset + col * SLOT_W
                local sy2 = subBaseY + blk.subY + slotsYOffset + row * SLOT_W
                local b = acquireSlot(body, nextSlotIdx)
                nextSlotIdx = nextSlotIdx + 1
                -- Position the host (button is anchored inside via SetAllPoints).
                local host = b._host or b
                host:SetSize(slotSize, slotSize)
                host:ClearAllPoints()
                host:SetPoint("TOPLEFT", body, "TOPLEFT", sx2, -sy2)
                dressSlot(b, it.bag, it.slot, it.itemID, it.link, it.count, it.quality, it.icon, it.locked)
            end
        end
    end

    hideUnusedHeaders(nextHeaderIdx - 1)
    hideUnusedGroups(nextGroupIdx)

    local barH = BAG_BAR_H
    local fitH = HEADER_H + PADDING + math.max(40, totalH) + PADDING + BOTTOM_BUFFER + barH
    fitH = math.min(fitH, UIParent:GetHeight() - 80)
    if self.panel._isResizing then
        if self.panel:GetHeight() < fitH then
            self.panel:SetHeight(fitH)
        end
    else
        self.panel:SetHeight(fitH)
    end

    if self.panel._botBar and self.panel._botBar.Refresh then
        self.panel._botBar:Refresh()
    end
end

-- ============================================================
-- Lifecycle
-- ============================================================
function BNK:Init()
    if self.initialized then return end
    self.initialized = true
    self.panel = buildPanel()
    self.panel:Hide()
end

function BNK:Show()
    if not self.panel then self:Init() end
    local pos = WB.db.bankPos
    if pos and pos.posPoint and pos.posPoint ~= false then
        self.panel:ClearAllPoints()
        self.panel:SetPoint(pos.posPoint, UIParent, pos.posRel, pos.posX or 0, pos.posY or 0)
    end
    if pos and pos.panelW and pos.panelW > 0 then
        self.panel:SetWidth(pos.panelW)
    end
    self.panel:Show()
    self.panel:Raise()
    self:Refresh()
end

function BNK:Hide()
    if not self.panel then return end
    if self.panel._snapPosition then self.panel._snapPosition() end
    self.panel:Hide()
    -- Walking away from banker fires BANKFRAME_CLOSED which calls this
    -- and also fires Blizzard's CloseBankFrame. Don't double-call.
end

function BNK:Toggle()
    if not self.panel then self:Init() end
    if self.panel:IsShown() then self:Hide() else self:Show() end
end

-- ============================================================
-- Suppress Blizzard's default BankFrame
-- ============================================================
-- We can't just Hide() it — on this build, hiding BankFrame stops
-- Blizzard from sending the slot-data sync, leaving the bank empty in
-- our panel. Instead, leave it Shown but invisible: alpha=0, mouse off,
-- pushed offscreen so it can't intercept clicks. Blizzard still treats
-- it as the active bank UI and syncs slot data normally.
local function suppressDefaultBank()
    if not BankFrame then return end
    if BankFrame._wicksHooked then return end
    BankFrame._wicksHooked = true
    BankFrame:HookScript("OnShow", function(self)
        if WB.db.options.hideDefaultBank ~= false then
            self:SetAlpha(0)
            self:EnableMouse(false)
            self:EnableKeyboard(false)
            self:ClearAllPoints()
            self:SetPoint("LEFT", UIParent, "RIGHT", 100, 0)
        end
    end)
    BankFrame:HookScript("OnHide", function(self)
        -- Reset alpha/mouse so the frame works normally if user toggles
        -- hideDefaultBank off later.
        self:SetAlpha(1)
        self:EnableMouse(true)
        self:EnableKeyboard(true)
    end)
end

-- Wire to events
WB:On("LOGIN", function()
    BNK:Init()
    suppressDefaultBank()
end)
WB:On("BANK_OPENED", function()
    BNK:Show()
    -- Auto-open the bag panel too so the user can drag items between
    -- without manually toggling it. Remember whether the bag was already
    -- open so we can restore state when the bank closes.
    if WB.Bag and WB.Bag.panel then
        BNK._bagWasOpen = WB.Bag.panel:IsShown()
        if not BNK._bagWasOpen and WB.Bag.Show then WB.Bag:Show() end
    end
    -- Slot data can lag the OPENED event by a frame or two on this build —
    -- schedule a couple of follow-up refreshes so items populate even if
    -- PLAYERBANKSLOTS_CHANGED doesn't fire as expected.
    C_Timer.After(0.1, function()
        if BNK.panel and BNK.panel:IsShown() then BNK:Refresh() end
    end)
    C_Timer.After(0.5, function()
        if BNK.panel and BNK.panel:IsShown() then BNK:Refresh() end
    end)
end)
WB:On("BANK_CLOSED", function()
    BNK:Hide()
    -- Restore the bag panel to its pre-bank state. If the user opened it
    -- manually before visiting the banker, leave it open; if we opened it
    -- automatically when bank fired, close it on the way out.
    if WB.Bag and WB.Bag.Hide and BNK._bagWasOpen == false then
        WB.Bag:Hide()
    end
    BNK._bagWasOpen = nil
end)
WB:On("BANK_DIRTY", function() BNK:Refresh() end)
-- Also refresh on regular bag updates if bank panel is open (cross-bag moves
-- update both panels' content in some Blizzard event fires).
WB:On("BAGS_DIRTY", function()
    if BNK.panel and BNK.panel:IsShown() then BNK:Refresh() end
end)
