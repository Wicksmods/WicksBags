-- Wick's Bags
-- Bag.lua: main panel, header, item-slot grid, category layout.
--
-- Layout:
--   header strip (24px): title left, gold center, search right, X far-right
--   body:               categories rendered top-down, each = section header
--                       + grid of item slots
--
-- Slot widget: 32x32 button. Visual via ItemButton template; secure use-on-
-- click via SecureActionButtonTemplate (type=item, item=item:NNNN). Drag
-- and right-click container actions are deferred to v0.2.

local ADDON, ns = ...
local WB = WicksBags
local UI = WB.UI
local CT = WB.Categories

WB.Bag = {}
local BG = WB.Bag

local MAX_PANEL_W   = 480
local MIN_PANEL_W   = 400   -- header (title/gold/search/cog/close) fits at full font sizes
local HEADER_H      = 28
local SLOT_SIZE     = 32
local SLOT_GAP      = 3
local CATEGORY_H    = 18
local CAT_GAP_X     = 12   -- horizontal gap between top-level group containers
local CAT_GAP_Y     = 10   -- vertical gap between top-level group containers
local SUB_GAP_X     = 10   -- horizontal gap between sub-blocks INSIDE a container
local SUB_GAP_Y     = 4    -- vertical gap between sub-block rows INSIDE a container
local MAX_COLS_PER_CAT = 5
local PADDING       = 10
local BOTTOM_BUFFER = 14
local BAG_BAR_H     = 32    -- height reserved for the optional bag bar
local NUM_BAGS      = 4   -- TBC: 0 (backpack) + 1..4
local KEYRING_CONTAINER = -2   -- TBC: keys live in their own container
-- Iteration list — backpack, 4 carry bags, plus the keyring so quest keys
-- and dungeon keys show up alongside regular items.
local BAG_IDS = { 0, 1, 2, 3, 4, KEYRING_CONTAINER }

-- ============================================================
-- Slot widget
-- ============================================================
-- Buttons are pooled: created lazily, reused on every refresh. Each holds
-- (bag, slot, itemID, quality, count, link). Visual update is done in
-- :SetItem; secure attributes are armed only out of combat.

local slotPool = {}
local slotInUse = {}

local function buildSlot(parent, index)
    -- Use Blizzard's ContainerFrameItemButtonTemplate — its built-in
    -- OnClick handles secure dispatch correctly for ALL items (potions,
    -- food, bandages, mounts, gear, containers). Pattern lifted from
    -- BetterBags TBC: a hidden host Button whose :GetID() returns the
    -- bag number, with the actual item button inside. Blizzard's template
    -- calls UseContainerItem(self:GetParent():GetID(), self:GetID()),
    -- so host:SetID(bag) + button:SetID(slot) wires it up correctly.
    local host = CreateFrame("Button", nil, parent)
    host:SetSize(SLOT_SIZE, SLOT_SIZE)

    local b = CreateFrame("Button", "WicksBagsSlot" .. index, host,
        "ContainerFrameItemButtonTemplate")
    b:SetAllPoints(host)
    b._host = host
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Hide the template's pushed/normal textures so our quality-border
    -- treatment isn't covered by Blizzard's default frame art.
    if b.GetPushedTexture and b:GetPushedTexture() then
        b:GetPushedTexture():SetTexture("")
    end
    if b.GetNormalTexture and b:GetNormalTexture() then
        b:GetNormalTexture():SetTexture("")
    end
    -- Hide Blizzard's IconBorder (the colored ring it draws around the
    -- icon), IconQuestTexture, NewItemTexture, BattlepayItemTexture, etc.
    -- We supply our own quality border via b._setQualityBorder below.
    local btnName = b:GetName()
    for _, suffix in ipairs({
        "IconBorder", "IconQuestTexture", "NewItemTexture",
        "BattlepayItemTexture", "Stock", "JunkIcon", "ExtendedSlot",
    }) do
        local child = _G[btnName .. suffix] or b[suffix]
        if child and child.Hide then child:Hide() end
        if child and child.SetTexture then child:SetTexture("") end
    end
    -- Nuclear IconBorder neutralization: reparent the texture to a permanently
    -- hidden frame so that no matter what the template does (Show, SetTexture,
    -- SetVertexColor, animation play, etc.), the texture cannot render in our
    -- panel because its parent isn't in any visible chain. Also override the
    -- common mutator methods to no-ops so subsequent template calls don't
    -- bring the texture back.
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
        -- Override mutators so future template calls are inert.
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

    -- The ItemButton template already provides:
    --   b.IconTexture (or _G[name.."IconTexture"])
    --   b.Count       (or _G[name.."Count"])
    --   b.NormalTexture (border)
    -- TBC's template uses globals; cache them here.
    local name = b:GetName()
    b._iconTex   = _G[name .. "IconTexture"] or b.IconTexture
    b._countText = _G[name .. "Count"]       or b.Count

    -- Quality border: 4 thin colored edges (no full-cover overlay).
    local function edge(p1, p2, w, h)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    b._qTop    = edge("TOPLEFT",    "TOPRIGHT",    nil, 2)
    b._qBottom = edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    b._qLeft   = edge("TOPLEFT",    "BOTTOMLEFT",  2,   nil)
    b._qRight  = edge("TOPRIGHT",   "BOTTOMRIGHT", 2,   nil)
    local function setQualityBorder(c)
        for _, t in ipairs({ b._qTop, b._qBottom, b._qLeft, b._qRight }) do
            t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
    b._setQualityBorder = setQualityBorder
    setQualityBorder({ 0.20, 0.18, 0.34, 1 })   -- default: muted purple

    -- Cooldown spiral (e.g. potions on shared CD)
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(b)
    cd:SetDrawEdge(false)
    cd:SetSwipeColor(0, 0, 0, 0.7)
    b._cd = cd

    -- Item-level overlay (top-left corner; equipment only)
    local ilvl = b:CreateFontString(nil, "OVERLAY")
    ilvl:SetFont("Fonts\\ARIALN.TTF", 10, "OUTLINE")
    ilvl:SetPoint("TOPLEFT", 1, -1)
    ilvl:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1)
    ilvl:SetText("")
    b._ilvlText = ilvl

    -- New-item highlight (green pulse, hidden until marked new)
    local newGlow = b:CreateTexture(nil, "OVERLAY")
    newGlow:SetColorTexture(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 0.0)
    newGlow:SetPoint("TOPLEFT", -2, 2)
    newGlow:SetPoint("BOTTOMRIGHT", 2, -2)
    newGlow:Hide()
    b._newGlow = newGlow
    -- Pulse animation
    local pulse = newGlow:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local up = pulse:CreateAnimation("Alpha")
    up:SetFromAlpha(0); up:SetToAlpha(0.55); up:SetDuration(0.7); up:SetOrder(1)
    local down = pulse:CreateAnimation("Alpha")
    down:SetFromAlpha(0.55); down:SetToAlpha(0); down:SetDuration(0.7); down:SetOrder(2)
    b._newPulse = pulse

    -- Tooltip on hover. HookScript (not SetScript) — the template's own
    -- OnEnter/OnLeave drives the highlight texture (shown on enter, hidden
    -- on leave); replacing them with SetScript leaves the highlight stuck.
    b:HookScript("OnEnter", function(self)
        if not self._bag or not self._slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self._bag, self._slot)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function(self)
        GameTooltip:Hide()
        -- Brute-force highlight clear. Some setups (ElvUI skinning, etc.)
        -- show a green highlight on hover but the template/skin doesn't
        -- always clear it on the way out, leaving the slot stuck green.
        -- Force-hide every highlight surface we know about.
        local hl = self.GetHighlightTexture and self:GetHighlightTexture()
        if hl then
            if hl.SetAlpha then hl:SetAlpha(0) end
            if hl.Hide then hl:Hide() end
        end
        if self.HighlightTexture then
            if self.HighlightTexture.SetAlpha then self.HighlightTexture:SetAlpha(0) end
            if self.HighlightTexture.Hide then self.HighlightTexture:Hide() end
        end
    end)

    -- Helper: drop the cursor item into the first empty bag slot. Used
    -- only for the FREE aggregate tile (which has no real bag/slot), via
    -- a HookScript — Blizzard's template handles real-slot drops natively.
    local function dropIntoFirstEmpty()
        for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
            local n = ns.GetContainerNumSlots(bag) or 0
            for slot = 1, n do
                if not ns.GetContainerItemLink(bag, slot) then
                    if ns.PickupContainerItem then ns.PickupContainerItem(bag, slot) end
                    return
                end
            end
        end
    end

    -- HookScript (not SetScript) — preserves the template's secure OnClick
    -- and OnReceiveDrag handlers. Our hooks only fire for FREE-tile cases
    -- where the template's bag/slot dispatch wouldn't have a real target.
    b:HookScript("OnClick", function(self, button)
        if button == "LeftButton" and CursorHasItem and CursorHasItem()
           and (not self._bag or not self._slot) then
            dropIntoFirstEmpty()
        end
    end)
    b:HookScript("OnReceiveDrag", function(self)
        if not self._bag or not self._slot then
            dropIntoFirstEmpty()
        end
    end)

    return b
end

local function acquireSlot(parent, index)
    local b = slotPool[index] or buildSlot(parent, index)
    slotPool[index] = b
    -- Re-parent the HOST (the button stays a child of the host via
    -- SetAllPoints). The host's :GetID() needs to live in the panel's
    -- layout tree so Blizzard's template OnClick reaches a real bag.
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

-- Apply current item state to a slot widget.
local function dressSlot(b, bag, slot, itemID, link, count, quality, icon, locked, isNew)
    b._bag, b._slot = bag, slot
    -- Wire the IDs the template's OnClick reads:
    --   self:GetID() = slot, self:GetParent():GetID() = bag
    if b._host then b._host:SetID(bag or 0) end
    b:SetID(slot or 0)
    -- Re-kill template overlays in case the template re-shows them in
    -- response to mouseover/refresh events (this is the source of the
    -- "stuck green ring" — IconBorder gets re-applied with quality color).
    local function _killTex(tex)
        if not tex then return end
        if tex.SetTexture then tex:SetTexture("") end
        if tex.SetVertexColor then tex:SetVertexColor(0, 0, 0, 0) end
        if tex.SetAlpha then tex:SetAlpha(0) end
        if tex.Hide then tex:Hide() end
    end
    _killTex(b.IconBorder)
    _killTex(b.IconQuestTexture)
    _killTex(b.NewItemTexture)
    _killTex(b.BattlepayItemTexture)

    -- New items now live in the dedicated "Recent" container instead of
    -- pulsing in place. Keep the pulse infrastructure stopped/hidden.
    -- Force alpha to 0 alongside Hide(); animation stop alone can leave
    -- alpha at a mid-cycle value, which would re-appear on next Show().
    if b._newPulse and b._newPulse:IsPlaying() then b._newPulse:Stop() end
    if b._newGlow then
        b._newGlow:SetAlpha(0)
        b._newGlow:Hide()
    end

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
        -- Below 1.0: scale alpha down (faded). At/above 1.0: alpha is full,
        -- and any extra (intensity > 1.0) brightens RGB by lifting each
        -- channel toward 1.0 — preserves hue while giving the borders a
        -- "blown out" pop at "Bright".
        if intensity <= 1.0 then
            b._setQualityBorder({ qc[1], qc[2], qc[3], (qc[4] or 1) * intensity })
        else
            local boost = math.min(intensity - 1.0, 1.0)
            local rr = math.min(1.0, qc[1] + (1 - qc[1]) * boost)
            local gg = math.min(1.0, qc[2] + (1 - qc[2]) * boost)
            local bb = math.min(1.0, qc[3] + (1 - qc[3]) * boost)
            b._setQualityBorder({ rr, gg, bb, 1 })
        end

        -- Item level overlay — equipment only (Weapon class 2, Armor class 4).
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
        -- Cooldown
        local start, dur = ns.GetItemCooldown and ns.GetItemCooldown(itemID)
        if start and start > 0 and dur and dur > 1.5 then
            b._cd:SetCooldown(start, dur)
            b._cd:Show()
        else
            b._cd:Hide()
        end
        -- (No secure attributes — ContainerFrameItemButtonTemplate
        -- handles its own click dispatch via host:GetID() + button:GetID()
        -- pointing at bag/slot.)
    else
        b._iconTex:SetTexture(nil)
        b._setQualityBorder({ 0.20, 0.18, 0.34, 1 })
        b._cd:Hide()
        if b._ilvlText then b._ilvlText:SetText("") end
        -- Free-slot aggregate tile: empty visual + count overlay.
        if count and count > 0 then
            b._countText:SetText(tostring(count))
            b._countText:Show()
        else
            b._countText:SetText("")
        end
    end

    -- Lock state (during a drag or split)
    if b._iconTex then
        b._iconTex:SetDesaturated(locked and true or false)
    end
end

-- ============================================================
-- Build the panel
-- ============================================================
local function buildPanel()
    -- cfg = WicksBagsDB.ui (visibility flags only)
    -- opt = WicksBagsDB.options (everything else, including position +
    --       width — putting them here rides the same code path that
    --       successfully persisted other options keys on this build)
    local cfg = WB.db.ui
    local opt = WB.db.options

    local panel = CreateFrame("Frame", "WicksBagsPanel", UIParent)
    -- 0-default trap: in Lua `0 or X` returns 0 (only nil/false are falsy),
    -- so a saved width of 0 would yield a zero-width invisible panel. Guard
    -- explicitly against non-positive widths.
    local startW = (opt.panelW and opt.panelW > 0) and opt.panelW or MAX_PANEL_W
    panel:SetSize(startW, 200)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:SetResizable(true)
    if panel.SetResizeBounds then
        panel:SetResizeBounds(MIN_PANEL_W, 120, 900, UIParent:GetHeight() - 40)
    elseif panel.SetMinResize then
        panel:SetMinResize(MIN_PANEL_W, 120)
        panel:SetMaxResize(900, UIParent:GetHeight() - 40)
    end
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:ClearAllPoints()
    -- Restore position from opt (= WicksBagsDB.options).
    local pp, prp, px, py = opt.posPoint, opt.posRel, opt.posX, opt.posY
    if pp and prp and px ~= nil and py ~= nil and (px ~= 0 or py ~= 0) then
        panel:SetPoint(pp, UIParent, prp, px, py)
    else
        panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
            math.max(120, (UIParent:GetWidth() / 2) - 240), 240)
    end

    UI:NewTexture(panel, "BACKGROUND", UI.C_BG):SetAllPoints(panel)
    UI:AddBorder(panel)
    UI:AddCornerAccents(panel)

    -- Capture the panel's current anchor as a 4-tuple { point, relativePoint,
    -- x, y } and store it in WB.db.ui.pos. This matches the canonical Wick
    -- saved-variable pattern (see WicksCDTracker UI.lua) — a single array
    -- under one key persists more reliably across the TBC Anniversary
    -- saved-variable serializer than individual nested numeric keys.
    local function snapPosition()
        local p, _, rp, x, y = panel:GetPoint()
        if not p then return end
        opt.posPoint = p
        opt.posRel   = rp or p
        opt.posX     = x or 0
        opt.posY     = y or 0
    end
    panel._snapPosition = snapPosition

    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        snapPosition()
    end)

    -- Header strip
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT",  panel, "TOPLEFT",  1, -1)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    UI:NewTexture(header, "BACKGROUND", UI.C_HEADER_BG):SetAllPoints(header)
    -- Subtle 1px divider under header
    local divider = UI:NewTexture(header, "BORDER", UI.C_BORDER)
    divider:SetPoint("BOTTOMLEFT"); divider:SetPoint("BOTTOMRIGHT"); divider:SetHeight(1)

    -- Title (left)
    local titleL, titleR = UI:AddTitleText(header, "Bags", "LEFT", 8, 0)

    -- Close X (rightmost)
    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    local x = UI:NewText(close, 14, UI.C_TEXT_DIM)
    x:SetPoint("CENTER")
    x:SetText("\195\151")
    close:SetScript("OnClick", function() WB.Bag:Hide() end)
    close:SetScript("OnEnter", function() x:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1) end)
    close:SetScript("OnLeave", function() x:SetTextColor(UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], 1) end)

    -- Cog (options) — left of close X
    local cog = CreateFrame("Button", nil, header)
    cog:SetSize(20, 20)
    cog:SetPoint("RIGHT", close, "LEFT", -2, 0)
    local cogTex = cog:CreateTexture(nil, "ARTWORK")
    cogTex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cogTex:SetSize(14, 14)
    cogTex:SetPoint("CENTER")
    cogTex:SetVertexColor(UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], 1)
    cog:SetScript("OnClick", function() if WB.Options then WB.Options:Toggle() end end)
    cog:SetScript("OnEnter", function() cogTex:SetVertexColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1) end)
    cog:SetScript("OnLeave", function() cogTex:SetVertexColor(UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], 1) end)
    panel._cog = cog

    -- Title-bar icons. Sort uses a 1-char letter (Q/A/#) since that conveys
    -- the active mode at a glance. Junk/Highlights/BagBar/MarkSeen use real
    -- texture icons. Clicking either a title icon or its cog-panel
    -- counterpart keeps the two in sync.
    local titleButtons = {}

    -- Text icon: uses a font-string (Q/A/# for sort cycle).
    local function makeTitleTextIcon(getText, tooltip, getActive, onClick)
        local b = CreateFrame("Button", nil, header)
        b:SetSize(18, 18)
        local txt = UI:NewText(b, 11, UI.C_TEXT_DIM)
        txt:SetPoint("CENTER")
        local function refresh()
            txt:SetText(getText())
            local on = getActive()
            if on then
                txt:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1)
            else
                txt:SetTextColor(UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], 1)
            end
        end
        refresh()
        b._refresh = refresh
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function()
            onClick(); refresh()
            if WB.Bag and WB.Bag.ApplyOptionsUI then WB.Bag:ApplyOptionsUI() end
            if WB.Bag and WB.Bag.Refresh        then WB.Bag:Refresh()        end
        end)
        titleButtons[#titleButtons + 1] = b
        return b
    end

    -- Texture icon: uses a 14x14 inset with the default Blizzard 8% crop.
    -- For toggle icons getActive controls saturation. For action icons
    -- (mark-seen) pass nil for getActive; the icon stays full-color.
    local function makeTitleTexIcon(texPath, tooltip, getActive, onClick)
        local b = CreateFrame("Button", nil, header)
        b:SetSize(20, 20)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(texPath)
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local function refresh()
            if not getActive then return end
            local on = getActive()
            if on then
                icon:SetVertexColor(1, 1, 1, 1)
                if icon.SetDesaturated then icon:SetDesaturated(false) end
            else
                icon:SetVertexColor(0.55, 0.55, 0.55, 0.65)
                if icon.SetDesaturated then icon:SetDesaturated(true) end
            end
        end
        refresh()
        b._refresh = refresh
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1, true); GameTooltip:Show()
            icon:SetVertexColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1)
        end)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if getActive then
                -- Toggle button: refresh re-applies the active/inactive color.
                refresh()
            else
                -- Action button (mark-seen): no toggle state, so reset to
                -- the always-on white color. Without this, the green from
                -- OnEnter sticks because refresh() early-returns on nil
                -- getActive and never undoes the color change.
                icon:SetVertexColor(1, 1, 1, 1)
            end
        end)
        b:SetScript("OnClick", function()
            onClick(); refresh()
            if WB.Bag and WB.Bag.ApplyOptionsUI then WB.Bag:ApplyOptionsUI() end
            if WB.Bag and WB.Bag.Refresh        then WB.Bag:Refresh()        end
        end)
        if getActive then titleButtons[#titleButtons + 1] = b end
        return b
    end

    local sortBtn = makeTitleTextIcon(
        function()
            local m = WB.db.options.sortMode
            if m == "quality"  then return "Q" end
            if m == "name"     then return "A" end
            if m == "quantity" then return "#" end
            return "?"
        end,
        "Sort (click to cycle):  Q = Quality   A = Name   # = Quantity",
        function() return true end,
        function()
            local m = WB.db.options.sortMode
            if     m == "quality"  then m = "name"
            elseif m == "name"     then m = "quantity"
            else                        m = "quality"
            end
            WB.db.options.sortMode = m
        end
    )

    -- Junk = gold coin (vanilla-era texture, guaranteed in TBC).
    local junkBtn = makeTitleTexIcon(
        "Interface\\Icons\\INV_Misc_Coin_01",
        "Show junk (gray-quality items)",
        function() return WB.db.options.showJunk and true or false end,
        function() WB.db.options.showJunk = not WB.db.options.showJunk end
    )

    -- Highlights = yellow sparkle aura (vanilla holy texture).
    local highlightsBtn = makeTitleTexIcon(
        "Interface\\Icons\\Spell_Holy_RighteousnessAura",
        "Highlight new items",
        function() return WB.db.options.showHighlights and true or false end,
        function() WB.db.options.showHighlights = not WB.db.options.showHighlights end
    )

    -- Bag bar = bag of beans (vanilla item icon).
    local bagBarBtn = makeTitleTexIcon(
        "Interface\\Icons\\INV_Misc_Bag_07",
        "Show bottom bar (bag icons + gold + PvP currencies)",
        function() return WB.db.options.showBagBar and true or false end,
        function() WB.db.options.showBagBar = not WB.db.options.showBagBar end
    )

    -- Mark-seen = rogue spy ability eye glyph.
    local markSeenBtn = makeTitleTexIcon(
        "Interface\\Icons\\Ability_Spy",
        "Mark all items seen (clears the new-item highlights)",
        nil,
        function() if WB.Bag and WB.Bag.MarkAllSeen then WB.Bag:MarkAllSeen() end end
    )

    panel._refreshTitleIcons = function()
        for _, b in ipairs(titleButtons) do
            if b._refresh then b._refresh() end
        end
    end

    -- Search input — immediately right of the addon title.
    local search = CreateFrame("EditBox", nil, header)
    search:SetSize(110, 16)
    -- Center search in the header (between the title cluster on the left and
    -- the icon cluster on the right). Title ends ~98px in, icon cluster
    -- ~150px from the right edge — the 110px-wide search box fits centered.
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
    placeholder:SetText("search")
    search:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        if WB.Bag and WB.Bag.Refresh then WB.Bag:Refresh() end
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() self:SetText("") end)

    -- (Gold and currencies live on the bag/bottom bar — see below.)

    -- Right-cluster icon row, anchored leftward from the cog. Visual order
    -- (left to right within the row): mark-seen, bag-bar, highlights, junk, sort.
    local prev = cog
    for _, btn in ipairs({ sortBtn, junkBtn, highlightsBtn, bagBarBtn, markSeenBtn }) do
        btn:SetPoint("RIGHT", prev, "LEFT", -4, 0)
        prev = btn
    end

    -- Body host (anchors get re-applied by ApplyOptionsUI when bag bar toggles)
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT",     panel, "TOPLEFT",     PADDING, -(HEADER_H + PADDING))
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING,   PADDING)
    panel._body = body

    -- Bottom bar — bag icons (left), gold (middle), TBC PvP currencies (right).
    -- One toggleable strip for everything that doesn't belong inside an item
    -- category. ON by default; toggle via the title-bar bag icon or Options.
    local bagBar = CreateFrame("Frame", nil, panel)
    bagBar:SetHeight(BAG_BAR_H - 4)
    bagBar:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT",   PADDING, PADDING)
    bagBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING, PADDING)
    UI:NewTexture(bagBar, "BACKGROUND", UI.C_HEADER_BG):SetAllPoints(bagBar)
    local bagBarBorder = UI:NewTexture(bagBar, "BORDER", UI.C_BORDER)
    bagBarBorder:SetPoint("TOPLEFT");    bagBarBorder:SetPoint("TOPRIGHT")
    bagBarBorder:SetHeight(1)
    panel._bagBar = bagBar
    -- Right-click on empty area of the bottom bar clears the bag filter.
    -- Discoverable escape hatch — same pattern as Wick's Bank's bottom bar.
    bagBar:EnableMouse(true)
    bagBar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and WB.db.ui._filterBag then
            WB.db.ui._filterBag = nil
            if bagBar.Refresh then bagBar:Refresh() end
            if WB.Bag and WB.Bag.Refresh then WB.Bag:Refresh() end
        end
    end)

    -- Bag icons (5: backpack + 4 carry bags), anchored on the LEFT.
    bagBar._slots = {}
    local bagSlotSize = 22
    for bag = 0, NUM_BAGS do
        local btn = CreateFrame("Button", nil, bagBar)
        btn:SetSize(bagSlotSize, bagSlotSize)
        btn:SetPoint("LEFT", bag * (bagSlotSize + 3) + 4, 0)
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
        btn._bag = bag
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            if bag == 0 then
                GameTooltip:AddLine("Backpack", 1, 1, 1)
            else
                local invID = ns.ContainerIDToInventoryID and ns.ContainerIDToInventoryID(bag) or nil
                if invID then GameTooltip:SetInventoryItem("player", invID) end
                GameTooltip:AddLine(("Bag %d"):format(bag),
                    UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3])
            end
            GameTooltip:AddLine("Left-click: open this bag", 1, 1, 1)
            GameTooltip:AddLine("Right-click: toggle filter (click again to clear)",
                UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3])
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Left-click: open the specific bag. Calls OpenBag/OpenBackpack
        -- directly (not MainMenuBarBackpackButton:Click) so addons that
        -- differentiate per-bag can do so. With BetterBags loaded, this may
        -- still consolidate into a single UI — that's BetterBags' design.
        -- Right-click: toggle filter (Wick's panel shows only this bag).
        btn:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if WB.db.ui._filterBag == bag then
                    WB.db.ui._filterBag = nil
                else
                    WB.db.ui._filterBag = bag
                end
                if bagBar.Refresh then bagBar:Refresh() end
                if WB.Bag and WB.Bag.Refresh then WB.Bag:Refresh() end
                return
            end
            -- Left click → toggle the specific bag (open if closed, close if
            -- open). Uses ToggleBag/ToggleBackpack so a second click on the
            -- same icon closes it.
            if InCombatLockdown() then return end
            if bag == 0 then
                if ToggleBackpack then ToggleBackpack()
                elseif OpenBackpack then OpenBackpack() end
            else
                if ToggleBag then ToggleBag(bag)
                elseif OpenBag then OpenBag(bag) end
            end
        end)
        bagBar._slots[bag] = btn
    end

    -- Gold display, anchored to the FAR RIGHT of the bottom bar.
    local goldText = UI:NewText(bagBar, 11, UI.C_TEXT_NORMAL)
    goldText:SetPoint("RIGHT", bagBar, "RIGHT", -8, 0)
    goldText:SetText(UI:FormatMoney(GetMoney()))
    bagBar._gold = goldText
    panel._gold = goldText
    WB:On("MONEY_CHANGED", function() goldText:SetText(UI:FormatMoney(GetMoney())) end)

    -- TBC PvP currencies on the RIGHT side. Each tile is icon + count text.
    -- Hidden when count is 0 (not every player PvPs). Honor and Arena Points
    -- come from Blizzard PvP currency functions; Marks of Honor are bag items.
    -- Currency definitions. `group` ties multiple currencies to one option
    -- toggle. PvP: honor / arena / marks. PvE: badges / shards. Rep: rep.
    local CURRENCIES = {
        { key = "honor",  group = "honor",  fn = function() return GetHonorCurrency and GetHonorCurrency() or 0 end,
          name = "Honor Points",  icon = "Interface\\PVPFrame\\PVP-Currency-Alliance" },
        { key = "arena",  group = "arena",  fn = function() return GetArenaCurrency and GetArenaCurrency() or 0 end,
          name = "Arena Points",  icon = "Interface\\Icons\\Achievement_PVP_A_06" },
        -- BG Marks of Honor
        { key = "ab",     group = "marks",  itemID = 20559, name = "Arathi Basin Mark of Honor" },
        { key = "wsg",    group = "marks",  itemID = 20558, name = "Warsong Gulch Mark of Honor" },
        { key = "av",     group = "marks",  itemID = 20560, name = "Alterac Valley Mark of Honor" },
        { key = "eots",   group = "marks",  itemID = 29024, name = "Eye of the Storm Mark of Honor" },
        -- PvE tokens
        { key = "boj",    group = "badges", itemID = 29434, name = "Badge of Justice" },
        { key = "apexis", group = "badges", itemID = 32569, name = "Apexis Shard" },
        { key = "ssh",    group = "shards", itemID = 28558, name = "Spirit Shard" },
        -- Outland rep tokens
        { key = "marksarg", group = "rep",  itemID = 28572, name = "Mark of Sargeras" },
        { key = "sunfury",  group = "rep",  itemID = 28570, name = "Sunfury Signet" },
        { key = "coilfang", group = "rep",  itemID = 24368, name = "Coilfang Armaments" },
        { key = "glowcap",  group = "rep",  itemID = 24245, name = "Glowcap" },
    }
    local GROUP_OPTION = {
        honor  = "showHonor",
        arena  = "showArena",
        marks  = "showMarks",
        badges = "showBadges",
        shards = "showShards",
        rep    = "showRep",
    }
    bagBar._currencyTiles = {}
    for _, c in ipairs(CURRENCIES) do
        local tile = CreateFrame("Frame", nil, bagBar)
        tile:SetSize(bagSlotSize + 24, bagSlotSize)
        tile:EnableMouse(true)
        local iconHost = CreateFrame("Frame", nil, tile)
        iconHost:SetSize(bagSlotSize, bagSlotSize)
        iconHost:SetPoint("LEFT", 0, 0)
        UI:AddBorder(iconHost)
        local icon = iconHost:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local count = UI:NewText(tile, 10, UI.C_TEXT_NORMAL)
        count:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        tile._icon = icon
        tile._count = count
        tile._def = c
        tile:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(c.name, 1, 1, 1)
            if c.itemID then GameTooltip:SetHyperlink("item:" .. c.itemID) end
            GameTooltip:Show()
        end)
        tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tile:Hide()   -- shown by Refresh when count > 0
        bagBar._currencyTiles[#bagBar._currencyTiles + 1] = tile
    end

    function bagBar:Refresh()
        -- Bag icons + filter highlight
        local activeFilter = WB.db.ui._filterBag
        for bag, btn in pairs(self._slots) do
            local tex
            if bag == 0 then
                tex = "Interface\\Buttons\\Button-Backpack-Up"
            else
                local invID = ns.ContainerIDToInventoryID and ns.ContainerIDToInventoryID(bag) or nil
                tex = invID and GetInventoryItemTexture("player", invID) or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
            end
            btn._icon:SetTexture(tex)
            btn._hilite:SetShown(activeFilter == bag)
        end
        -- Gold
        if self._gold then self._gold:SetText(UI:FormatMoney(GetMoney())) end
        -- Currencies — only show ones with count > 0 AND whose option group
        -- is enabled. Anchored leftward starting from the gold display.
        local opts = WB.db.options
        local prev = self._gold
        for _, tile in ipairs(self._currencyTiles) do
            local c = tile._def
            local n = 0
            local groupOpt = GROUP_OPTION[c.group]
            local groupOn = (not groupOpt) or (opts[groupOpt] ~= false)
            if groupOn then
                if c.fn then
                    n = c.fn() or 0
                elseif c.itemID and GetItemCount then
                    n = GetItemCount(c.itemID) or 0
                end
            end
            if n > 0 then
                tile._count:SetText(tostring(n))
                -- Resolve item icon for item-based currencies
                if c.itemID then
                    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(c.itemID)
                    tile._icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
                else
                    tile._icon:SetTexture(c.icon)
                end
                tile:ClearAllPoints()
                tile:SetPoint("RIGHT", prev, "LEFT", -10, 0)
                tile:Show()
                prev = tile
            else
                tile:Hide()
            end
        end
    end
    bagBar:Refresh()
    -- Currencies refresh alongside the main panel refresh (BAG_UPDATE-driven).
    WB:On("BAGS_DIRTY", function() if bagBar:IsShown() then bagBar:Refresh() end end)

    -- Resize grip — invisible button stacked under the BOTTOMRIGHT corner
    -- accent. While dragging, height auto-fit is suspended so the panel
    -- doesn't snap up/down each time the content reflows; instead the
    -- user-dragged height is respected during the drag and we re-auto-fit
    -- only on release.
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
        opt.panelW = panel:GetWidth()
        -- Resize anchors the frame at its current location; recapture
        -- BOTTOMLEFT coords so the saved position matches the on-screen
        -- position after the resize finishes.
        snapPosition()
        if WB.Bag and WB.Bag.Refresh then WB.Bag:Refresh() end
    end)

    -- Live content reflow during drag (sub-blocks rewrap), but height stays
    -- locked while _isResizing is true. Throttled to ~20Hz.
    local resizePending = false
    panel:SetScript("OnSizeChanged", function()
        if resizePending then return end
        resizePending = true
        C_Timer.After(0.05, function()
            resizePending = false
            if WB.Bag and WB.Bag.Refresh then WB.Bag:Refresh() end
        end)
    end)

    return panel
end

-- ============================================================
-- Layout pass: walk all bags, classify, group by category, place slots
-- ============================================================
local categoryHeaders = {}  -- pool of section-header font strings

local function getCategoryHeader(parent, index)
    local h = categoryHeaders[index]
    if not h then
        local f = CreateFrame("Frame", nil, parent)
        f:SetHeight(CATEGORY_H)
        local label = UI:NewText(f, 8, UI.C_TEXT_DIM)
        -- Single BOTTOM anchor centers the FontString horizontally on the
        -- parent frame's bottom midpoint (the label auto-sizes to its text).
        -- This mirrors how getGroupContainer centers the parent header above
        -- sub-blocks. Dual-anchor + SetJustifyH("CENTER") looks equivalent
        -- on paper but didn't visibly center under SetWidth pressure.
        label:SetPoint("BOTTOM", 0, 3)
        label:SetText("")
        -- Clip overflowing labels at the block boundary instead of letting
        -- "JEWELCRAFTING" bleed into the next sub-block.
        if label.SetWordWrap then label:SetWordWrap(false) end
        f._label = label
        h = f
        categoryHeaders[index] = h
    end
    h:SetParent(parent)
    h:Show()
    return h
end

local function hideUnusedHeaders(usedCount)
    for i = usedCount + 1, #categoryHeaders do
        categoryHeaders[i]:Hide()
        categoryHeaders[i]:ClearAllPoints()
    end
end

-- Pool of group-container frames (one per parent class with 2+ sub-cats in view).
local groupContainers = {}
local GROUP_HEADER_H = 16
local GROUP_PAD_X    = 6
local GROUP_PAD_TOP  = GROUP_HEADER_H + 2
local GROUP_PAD_BOT  = 6

-- Hidden FontString used to measure header text width so container width
-- can be sized to fit both the slot grid AND the centered header label.
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
        label:SetPoint("TOP", 0, -3)   -- centered horizontally in the container
        f._label = label
        -- Optional accent border (1px ring offset 2px outside the main
        -- border). Used to subtly mark special containers like "Recent".
        -- Hidden by default; toggled via f._setAccent(true/false).
        local accent = { tex = {} }
        local function makeEdge(p1, p2, w, h)
            local t = f:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 0.35)
            t:SetPoint(p1, f, p1, p1:find("LEFT") and -2 or (p1:find("RIGHT") and 2 or 0),
                       p1:find("TOP") and 2 or (p1:find("BOTTOM") and -2 or 0))
            t:SetPoint(p2, f, p2, p2:find("LEFT") and -2 or (p2:find("RIGHT") and 2 or 0),
                       p2:find("TOP") and 2 or (p2:find("BOTTOM") and -2 or 0))
            if w then t:SetWidth(w) end
            if h then t:SetHeight(h) end
            t:Hide()
            accent.tex[#accent.tex + 1] = t
        end
        makeEdge("TOPLEFT",    "TOPRIGHT",    nil, 1)
        makeEdge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
        makeEdge("TOPLEFT",    "BOTTOMLEFT",  1,   nil)
        makeEdge("TOPRIGHT",   "BOTTOMRIGHT", 1,   nil)
        f._setAccent = function(on)
            for _, t in ipairs(accent.tex) do
                if on then t:Show() else t:Hide() end
            end
        end
        groupContainers[index] = f
    end
    f:SetParent(parent)
    f:Show()
    return f
end

local function hideUnusedGroups(usedCount)
    for i = usedCount + 1, #groupContainers do
        groupContainers[i]:Hide()
        groupContainers[i]:ClearAllPoints()
    end
end

-- ============================================================
-- New-item tracking
-- ============================================================
-- Baseline lives in WicksBagsCharDB.baseline as { [itemID] = count }.
-- On login if no baseline, snapshot current bags so first-load doesn't
-- light every slot up. On panel hide, update baseline to current.
local function snapshotCounts()
    local snap = {}
    for _, bag in ipairs(BAG_IDS) do
        local n = ns.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local link = ns.GetContainerItemLink(bag, slot)
            if link then
                local id = tonumber(link:match("item:(%d+)"))
                if id then snap[id] = (snap[id] or 0) + 1 end
            end
        end
    end
    return snap
end

local function ensureBaseline()
    -- Just ensure the table exists. The actual seeding happens in Refresh
    -- once we have real currentCounts (and never a second time, gated by
    -- WB.charDB.baselineSeeded — that flag persists across /reload so a
    -- mark-seen survives logout).
    if not WB.charDB.baseline then WB.charDB.baseline = {} end
end

-- Treat showHighlights == nil as default-on (so a missing key from older
-- saved-variable schemas behaves like the current default true).
local function isNewItem(itemID, currentCounts)
    if not itemID then return false end
    if WB.db.options.showHighlights == false then return false end
    -- ItemRack-tracked gear is exempt from Recent. Spec/set swaps bump bag
    -- counts every time gear comes off the body; the user shouldn't have
    -- to mark-seen after each swap.
    if CT.IsItemRackTracked and CT:IsItemRackTracked(itemID) then return false end
    local base = WB.charDB.baseline or {}
    return (currentCounts[itemID] or 0) > (base[itemID] or 0)
end

function BG:MarkAllSeen()
    -- Defer the actual snapshot to Refresh so it's built from the SAME
    -- currentCounts the bucketing uses (snapshotCounts and gatherItems can
    -- diverge if e.g. GetContainerItemID returns for slots where the link
    -- isn't yet cached).
    self._pendingSnapshot = true
    self:Refresh()
end

local function gatherItems()
    -- Returns a flat list: { {bag, slot, itemID, link, count, quality, icon, locked}, ... }
    -- Honors WB.db.ui._filterBag — if set, only collects from that one bag.
    -- Iterates regular bags PLUS the keyring (-2) so quest/dungeon keys
    -- show up in the panel under the "Key" auto-category.
    local items = {}
    local filterBag = WB.db.ui and WB.db.ui._filterBag
    for _, bag in ipairs(BAG_IDS) do
        if filterBag ~= nil and bag ~= filterBag then
            -- skip non-filter bags
        else
        local n = ns.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local link = ns.GetContainerItemLink(bag, slot)
            local itemID = ns.GetContainerItemID and ns.GetContainerItemID(bag, slot)
                       or (link and tonumber(link:match("item:(%d+)")))
            -- Container item info: ns.GetContainerItemInfo handles both
            -- C_Container (table) and legacy (tuple) forms.
            local icon, count, locked, quality = ns.GetContainerItemInfo(bag, slot)
            items[#items + 1] = {
                bag = bag, slot = slot,
                itemID = itemID, link = link,
                count = count or 0, quality = quality,
                icon = icon, locked = locked,
            }
        end
        end   -- close else branch
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
-- Main refresh
-- ============================================================
function BG:Refresh()
    if not self.panel then return end
    if not self.panel:IsShown() then return end

    -- Rebuild the ItemRack reverse-map at the top of every refresh so set
    -- edits show up live (no /reload). Cheap: a few dozen string ops at most.
    if CT.RefreshItemRack then CT:RefreshItemRack() end

    local body = self.panel._body
    local bodyW = body:GetWidth()
    local cols = math.max(1, math.floor((bodyW + SLOT_GAP) / (SLOT_SIZE + SLOT_GAP)))

    local items = gatherItems()
    local term = self.panel._search and self.panel._search:GetText() or ""
    items = applySearchFilter(items, term)

    -- Build current-count map for new-item detection
    local currentCounts = {}
    for _, it in ipairs(items) do
        if it.itemID then
            currentCounts[it.itemID] = (currentCounts[it.itemID] or 0) + (it.count > 0 and it.count or 1)
        end
    end

    -- Baseline seeding policy:
    --   * Mark-seen (self._pendingSnapshot) ALWAYS reseeds — explicit user
    --     action wins regardless of state.
    --   * First-time auto-seed only fires once per character — gated by
    --     WB.charDB.baselineSeeded which persists in saved-variables-per-
    --     character. Once true, the only way to refresh baseline is mark-seen.
    --   * Auto-seed waits until currentCounts has real entries; otherwise we
    --     might seed an empty baseline from a partial bag load.
    local hasItems = next(currentCounts) ~= nil
    if self._pendingSnapshot or (not WB.charDB.baselineSeeded and hasItems) then
        local seed = {}
        for id, n in pairs(currentCounts) do seed[id] = n end
        WB.charDB.baseline = seed
        WB.charDB.baselineSeeded = true
        self._pendingSnapshot = false
    end

    -- Effective slot size depends on the user-controlled slotScale option.
    -- All block math + button sizing keys off these locals.
    local slotScale = WB.db.options.slotScale or 1.0
    local slotSize  = math.floor(SLOT_SIZE * slotScale)
    local SLOT_W    = slotSize + SLOT_GAP

    -- Bucket by category. Empty slots condense into one Free tile.
    -- New items (those acquired since the last mark-all-seen) go into a
    -- dedicated "Recent" bucket instead of their normal category, so they
    -- show up at the top in their own container until the user clicks the
    -- mark-seen icon — at which point baseline updates and they fall back
    -- into their normal categories on the next refresh.
    local buckets = {}
    local freeCount = 0
    for _, it in ipairs(items) do
        if not it.itemID then
            freeCount = freeCount + 1
        elseif isNewItem(it.itemID, currentCounts) then
            buckets["Recent"] = buckets["Recent"] or {}
            table.insert(buckets["Recent"], it)
        else
            local cat = CT:GetCategory(it.itemID, it.link) or "Misc"
            buckets[cat] = buckets[cat] or {}
            table.insert(buckets[cat], it)
        end
    end
    if freeCount > 0 then
        buckets["Free"] = { { itemID = nil, count = freeCount, isFreeAggregate = true } }
    end

    -- Junk filter
    if not WB.db.options.showJunk then
        buckets["Junk"] = nil
    end

    -- Quality-min filter (drops anything below the chosen threshold from
    -- ALL buckets, not just Junk)
    local qMin = WB.db.options.qualityMin or 0
    if qMin > 0 then
        for cat, bucket in pairs(buckets) do
            if cat ~= "Free" then
                local kept = {}
                for _, it in ipairs(bucket) do
                    if (it.quality or 0) >= qMin then kept[#kept + 1] = it end
                end
                if #kept == 0 then
                    buckets[cat] = nil
                else
                    buckets[cat] = kept
                end
            end
        end
    end

    -- Sort items inside each bucket. New items always sort first (so they
    -- show up at the front of their category), then by the active mode.
    --
    -- IMPORTANT: extract the bracketed item name from the link before
    -- comparing. Raw links start with `|cAARRGGBB` color codes, so a naive
    -- `link < link` comparison sorts by color code (= quality) first, which
    -- made "name" sort look identical to "quality" sort. Pull just the name.
    local mode = WB.db.options.sortMode or "quality"
    local function newWeight(it)
        return isNewItem(it.itemID, currentCounts) and 1 or 0
    end
    local function nameOf(it)
        if it._sortName then return it._sortName end
        local n = ""
        if it.link then n = (it.link:match("%[(.-)%]") or ""):lower() end
        it._sortName = n
        return n
    end
    local sortFns = {
        quality = function(a, b)
            local na, nb = newWeight(a), newWeight(b)
            if na ~= nb then return na > nb end
            local qa, qb = a.quality or 0, b.quality or 0
            if qa ~= qb then return qa > qb end
            return nameOf(a) < nameOf(b)
        end,
        name = function(a, b)
            local na, nb = newWeight(a), newWeight(b)
            if na ~= nb then return na > nb end
            return nameOf(a) < nameOf(b)
        end,
        quantity = function(a, b)
            local na, nb = newWeight(a), newWeight(b)
            if na ~= nb then return na > nb end
            local ca, cb = a.count or 1, b.count or 1
            if ca ~= cb then return ca > cb end
            return nameOf(a) < nameOf(b)
        end,
    }
    local sortFn = sortFns[mode] or sortFns.quality
    for _, bucket in pairs(buckets) do
        table.sort(bucket, sortFn)
    end

    -- Build block specs (without h or w yet — both depend on whether the
    -- sub-cat header gets drawn, which we decide after grouping).
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
            slotW = blkCols * SLOT_W - SLOT_GAP,   -- raw slot-grid width
        }
    end
    for _, cat in ipairs(ordered) do
        seenCat[cat] = true
        addBlock(cat, buckets[cat])
    end
    -- Append any bucket whose name isn't in DISPLAY_ORDER (e.g. ItemRack
    -- gear-set names, future custom-rule cats). Sort alphabetically for
    -- a stable order.
    local extras = {}
    for cat in pairs(buckets) do
        if not seenCat[cat] then extras[#extras + 1] = cat end
    end
    table.sort(extras)
    for _, cat in ipairs(extras) do
        addBlock(cat, buckets[cat])
    end

    -- Group blocks by parent class. Every group now gets a container for
    -- visual uniformity. When a group has only 1 sub-block, the container
    -- header IS the sub-cat name (more specific) and the sub-label inside
    -- is skipped to avoid duplicating the same word twice.
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
        -- 1-block group normally collapses: container takes the sole sub-cat
        -- name (e.g. just "ENCHANTING" instead of "TRADE GOODS > ENCHANTING").
        -- EXCEPTION: ItemRack sets must always read as a sub-class under
        -- Equipment, so even when a set is the only Equipment-family block
        -- in view we keep the EQUIPMENT parent header and draw the set
        -- name as a sub-header inside.
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
            -- Block width = max of the slot-grid width AND the sub-cat
            -- header text width (so labels like SCROLL don't bleed into the
            -- next sub-block's gap when there's only 1-2 slots underneath).
            -- skipHeader case: no sub-header drawn, just slot-grid width.
            local minW = blk.slotW
            if not blk.skipHeader then
                local headerW = measureHeaderWidth(blk.cat:upper())
                if headerW + 4 > minW then minW = headerW + 4 end
            end
            blk.w = minW
            -- Always reserve sub-header height so single-sub groups line up
            -- vertically with multi-sub siblings on the same row.
            blk.h = CATEGORY_H + blk.rows * SLOT_W - SLOT_GAP
        end
    end

    -- Pass 1: masonry-pack each group's sub-blocks into its natural width.
    -- Sub-block gaps INSIDE a container use SUB_GAP_X/Y (tighter than the
    -- inter-container CAT_GAP_X/Y) so the inner layout reads as a unit.
    --
    -- Masonry vs row-based: a simple row packer would leave dead space
    -- under short blocks (POTION 1-row) when a sibling on the same row is
    -- tall (FOOD 2-row), because the next row can't start until all of row
    -- 1 finishes. Masonry places each next block at the lowest-leftmost
    -- free slot, so CONSUMABLE backfills the void under POTION.
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
            -- Build candidate (x, y) positions: top-left of the container,
            -- plus the right edge of each placed block (for new columns)
            -- and the bottom edge of each (for new rows beneath them).
            local xs, ys = { 0 }, { 0 }
            for _, p in ipairs(placed) do
                xs[#xs + 1] = p.x + p.w + SUB_GAP_X
                ys[#ys + 1] = p.y + p.h + SUB_GAP_Y
            end
            table.sort(ys)
            table.sort(xs)
            local px, py
            for _, y in ipairs(ys) do
                for _, x in ipairs(xs) do
                    if x + blk.w <= availW and not overlapsSub(x, y, blk.w, blk.h) then
                        px, py = x, y
                        break
                    end
                end
                if px then break end
            end
            if not px then
                -- Block wider than the container or pathological case: drop
                -- it below everything.
                px, py = 0, subTotalH + (subTotalH > 0 and SUB_GAP_Y or 0)
            end
            blk.subX, blk.subY = px, py
            placed[#placed + 1] = { x = px, y = py, w = blk.w, h = blk.h }
            if px + blk.w > subMaxW then subMaxW = px + blk.w end
            if py + blk.h > subTotalH then subTotalH = py + blk.h end
        end

        -- Container width: fit BOTH the slot grid AND the centered header
        -- label (e.g. "ENCHANTING" is wider than a single slot, so a
        -- single-item group still needs enough horizontal room).
        local headerW = measureHeaderWidth(g.containerHeader) + 12
        g.w = math.max(subMaxW + GROUP_PAD_X * 2, headerW)
        g.h = GROUP_PAD_TOP + subTotalH + GROUP_PAD_BOT
    end

    -- Pass 2: greedy masonry, tried over multiple orderings.
    -- For each ordering of the groups, run a lowest-then-leftmost packer:
    -- candidate positions are (0, 0), (right edge of any placed group, 0),
    -- and (any x, bottom edge of any placed group), so a short group lets
    -- a later one backfill the void underneath. Pick whichever ordering
    -- yields the smallest total height for the current bodyW — which is
    -- the dimension that user-drag changes, so the layout adapts as the
    -- panel resizes.
    --
    -- Heuristics tried:
    --   * natural   — DISPLAY_ORDER (preserves semantic top-down reading)
    --   * tall      — tallest first (best for narrow panels: tall anchors
    --                  the height column, short ones backfill)
    --   * wide      — widest first (best when one block is much wider than
    --                  the rest and would otherwise force a late row break)
    --   * area      — largest area first (well-rounded fallback)
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
            table.sort(ys)
            table.sort(xs)
            local px, py
            for _, y in ipairs(ys) do
                for _, x in ipairs(xs) do
                    if x + g.w <= bodyW and not overlapsAny(x, y, g.w, g.h) then
                        px, py = x, y
                        break
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

    local orderings = {
        copyOrder(),                                                      -- natural
        copyOrder(),                                                      -- tall
        copyOrder(),                                                      -- wide
        copyOrder(),                                                      -- area
    }
    table.sort(orderings[2], function(a, b) return a.h > b.h end)
    table.sort(orderings[3], function(a, b) return a.w > b.w end)
    table.sort(orderings[4], function(a, b) return a.w * a.h > b.w * b.h end)

    local bestH, bestPositions = math.huge, nil
    for _, ord in ipairs(orderings) do
        local h, pos = tryPack(ord)
        if h < bestH then
            bestH = h
            bestPositions = pos
        end
    end

    local totalH = bestH
    for _, g in ipairs(groups) do
        local p = bestPositions[g]
        g.x, g.y = p.x, p.y
    end

    -- Render: containers, sub-cat headers (when not skipped), item slots
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
        -- Subtle muted-green accent ring around the Recent container so new
        -- items stand out at a glance without flashing or pulsing.
        if container._setAccent then
            container._setAccent(g.parent == "Recent" or g.containerHeader == "RECENT")
        end

        local subBaseX = g.x + GROUP_PAD_X
        local subBaseY = g.y + GROUP_PAD_TOP

        for _, blk in ipairs(g.blocks) do
            if not blk.skipHeader then
                local h = getCategoryHeader(body, nextHeaderIdx)
                nextHeaderIdx = nextHeaderIdx + 1
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", body, "TOPLEFT", subBaseX + blk.subX, -(subBaseY + blk.subY))
                h:SetWidth(blk.w)
                -- Label auto-sizes to its text now (single BOTTOM anchor),
                -- so no SetWidth on the label — the frame's blk.w sets the
                -- centering reference and the text auto-shrinks to fit.
                h._label:SetText(blk.cat:upper())
            end

            -- Always offset items by CATEGORY_H so single-sub groups (no
            -- visible sub-header) align with multi-sub siblings on the row.
            local slotsYOffset = CATEGORY_H
            -- Center the slot grid horizontally within blk.w. When the
            -- sub-header text is wider than the raw slot grid (e.g.
            -- "JEWELCRAFTING" above 1 slot, "ENCHANTING" above 2), blk.w was
            -- inflated to fit the header — without this offset the slots
            -- would pack at the block's left edge while the header sits
            -- centered, looking misaligned.
            local slotsXOffset = math.floor((blk.w - blk.slotW) / 2)
            if slotsXOffset < 0 then slotsXOffset = 0 end
            for j, it in ipairs(blk.items) do
                local col = (j - 1) % blk.cols
                local row = math.floor((j - 1) / blk.cols)
                local sx2 = subBaseX + blk.subX + slotsXOffset + col * SLOT_W
                local sy2 = subBaseY + blk.subY + slotsYOffset + row * SLOT_W
                local b = acquireSlot(body, nextSlotIdx)
                nextSlotIdx = nextSlotIdx + 1
                -- Position the HOST frame (the button is SetAllPoints-anchored
                -- inside it, so it follows). Sizing the host also resizes
                -- the button via the anchor relationship.
                local host = b._host or b
                host:SetSize(slotSize, slotSize)
                host:ClearAllPoints()
                host:SetPoint("TOPLEFT", body, "TOPLEFT", sx2, -sy2)
                dressSlot(b, it.bag, it.slot, it.itemID, it.link, it.count, it.quality, it.icon, it.locked,
                    isNewItem(it.itemID, currentCounts))
            end
        end
    end

    hideUnusedHeaders(nextHeaderIdx - 1)
    hideUnusedGroups(nextGroupIdx)

    -- Width is user-controlled. Height auto-fits to content + bottom buffer
    -- + bag-bar reservation when shown.
    --
    -- Drag behavior: during an active resize we don't shrink the panel below
    -- the content footprint (otherwise slots spill out the bottom border as
    -- you drag smaller). We DO allow the user to drag taller than content
    -- for breathing room. On release, Refresh shrinks back to fit.
    local barH = WB.db.options.showBagBar and BAG_BAR_H or 0
    local fitH = HEADER_H + PADDING + math.max(40, totalH) + PADDING + BOTTOM_BUFFER + barH
    fitH = math.min(fitH, UIParent:GetHeight() - 80)
    if self.panel._isResizing then
        -- Anti-overflow only — never shrink below content during drag.
        if self.panel:GetHeight() < fitH then
            self.panel:SetHeight(fitH)
        end
    else
        self.panel:SetHeight(fitH)
    end
end

-- ============================================================
-- Lifecycle
-- ============================================================
function BG:Init()
    if self.initialized then return end
    self.initialized = true
    ensureBaseline()
    self.panel = buildPanel()
    self:ApplyOptionsUI()
    if WB.db.ui.hidden then self.panel:Hide() else self.panel:Show() end
end

function BG:ApplyOptionsUI()
    local panel = self.panel
    if not panel then return end
    if panel._search then
        panel._search:SetShown(WB.db.options.showSearch and true or false)
    end
    -- Sync title-bar icons so cog-panel toggles reflect there too.
    if panel._refreshTitleIcons then panel._refreshTitleIcons() end

    -- Bag bar visibility + body bottom anchor (clears space for the bar)
    local showBar = WB.db.options.showBagBar and true or false
    if panel._bagBar then
        panel._bagBar:SetShown(showBar)
        if showBar then panel._bagBar:Refresh() end
    end
    if panel._body then
        panel._body:ClearAllPoints()
        panel._body:SetPoint("TOPLEFT",     panel, "TOPLEFT",     PADDING, -(HEADER_H + PADDING))
        panel._body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING,   PADDING + (showBar and BAG_BAR_H or 0))
    end
end

function BG:Show()
    if not self.panel then return end
    -- Force-restore saved position and width on every Show.
    local opt = WB.db.options
    if opt.posPoint and opt.posRel and (opt.posX ~= 0 or opt.posY ~= 0) then
        self.panel:ClearAllPoints()
        self.panel:SetPoint(opt.posPoint, UIParent, opt.posRel, opt.posX, opt.posY)
    end
    if opt.panelW and opt.panelW > 0 then
        self.panel:SetWidth(opt.panelW)
    end
    self.panel:Show()
    WB.db.ui.hidden = false
    self:ApplyOptionsUI()
    self:Refresh()
end

function BG:Hide()
    if not self.panel then return end
    self.panel:Hide()
    WB.db.ui.hidden = true
    -- Note: we no longer auto-mark items as seen on hide. The "Recent"
    -- container persists across opens until the user explicitly clicks the
    -- mark-seen icon (or the Options "Mark all items seen" button).
end

function BG:Toggle()
    if not self.panel then return end
    if self.panel:IsShown() then self:Hide() else self:Show() end
end

function BG:ResetPosition()
    if not self.panel then return end
    local defX = math.max(120, (UIParent:GetWidth() / 2) - 240)
    local defY = 240
    local opt = WB.db.options
    opt.posPoint = "BOTTOMLEFT"
    opt.posRel   = "BOTTOMLEFT"
    opt.posX     = defX
    opt.posY     = defY
    self.panel:ClearAllPoints()
    self.panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", defX, defY)
    self:Show()
end

-- Wire to events
WB:On("LOGIN",        function() BG:Init() end)
WB:On("BAGS_DIRTY",   function() BG:Refresh() end)
WB:On("COOLDOWN_CHANGED", function() BG:Refresh() end)
