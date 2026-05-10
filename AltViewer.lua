-- Wick's Bags
-- AltViewer.lua: read-only viewer for snapshotted alt character inventories.
--
-- Data source: WB.altDB[realmName.."-"..charName]
--   { bagsLastSeen, bankLastSeen, bags = { {itemID,count,quality,icon,link,cat} }, bank = {...} }
-- Snapshots are written by SnapshotBags() on PLAYER_LOGOUT and SnapshotBank()
-- on BANKFRAME_CLOSED.

local ADDON, ns = ...
local WB = WicksBags
local UI = WB.UI
local CT = WB.Categories

WB.AltViewer = {}
local AV = WB.AltViewer

local HEADER_H         = 28
local TOOLBAR_H        = 26
local SLOT_SIZE        = 32
local SLOT_GAP         = 3
local CATEGORY_H       = 18
local CAT_GAP_X        = 12
local CAT_GAP_Y        = 10
local SUB_GAP_X        = 10
local SUB_GAP_Y        = 4
local MAX_COLS_PER_CAT = 5
local PADDING          = 10
local SECTION_GAP      = 14
local SECTION_LABEL_H  = 18
local CONTENT_PAD      = 10
local MIN_PANEL_W      = 600
local MAX_PANEL_W      = 960

-- Bank section visual treatment: muted green wash + green borders on containers
local C_BANK_WASH    = { 0.310, 0.780, 0.471, 0.06 }
local C_BANK_BORDER  = { 0.310, 0.780, 0.471, 0.35 }

local function formatGold(copper)
    if not copper or copper <= 0 then return "" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = "|cffFFD700" .. g .. "g|r" end
    if s > 0 or g > 0 then parts[#parts + 1] = "|cffC0C0C0" .. s .. "s|r" end
    parts[#parts + 1] = "|cffCC9966" .. c .. "c|r"
    return table.concat(parts, " ")
end

-- ============================================================
-- Snapshot helpers
-- ============================================================
local KEYRING = -2

local function snapshotBagSlots()
    local out = {}
    for _, bag in ipairs({ 0, 1, 2, 3, 4, KEYRING }) do
        local n = ns.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local link = ns.GetContainerItemLink(bag, slot)
            local itemID = (ns.GetContainerItemID and ns.GetContainerItemID(bag, slot))
                        or (link and tonumber(link:match("item:(%d+)")))
            if itemID and link then
                local icon, count, _, quality = ns.GetContainerItemInfo(bag, slot)
                out[#out + 1] = {
                    itemID  = itemID,
                    count   = count or 1,
                    quality = quality or 1,
                    icon    = icon,
                    link    = link,
                    cat     = CT:GetCategory(itemID, link),
                }
            end
        end
    end
    return out
end

local function snapshotBankSlots()
    local out = {}
    local BANK_IDS = { -1 }
    local numBankBags = NUM_BANKBAGSLOTS or 7
    for i = 1, numBankBags do BANK_IDS[#BANK_IDS + 1] = 4 + i end
    for _, bag in ipairs(BANK_IDS) do
        local n = ns.GetContainerNumSlots(bag) or 0
        for slot = 1, n do
            local link = ns.GetContainerItemLink(bag, slot)
            local itemID = (ns.GetContainerItemID and ns.GetContainerItemID(bag, slot))
                        or (link and tonumber(link:match("item:(%d+)")))
            if itemID and link then
                local icon, count, _, quality = ns.GetContainerItemInfo(bag, slot)
                out[#out + 1] = {
                    itemID  = itemID,
                    count   = count or 1,
                    quality = quality or 1,
                    icon    = icon,
                    link    = link,
                    cat     = CT:GetCategory(itemID, link),
                }
            end
        end
    end
    return out
end

local function charKey()
    local realm = GetRealmName and GetRealmName() or "Unknown"
    local char  = UnitName  and UnitName("player") or "Unknown"
    return realm .. "-" .. char
end

function AV:SnapshotBags()
    WB.altDB = WB.altDB or {}
    local key      = charKey()
    local existing = WB.altDB[key] or {}
    WB.altDB[key] = {
        bagsLastSeen = time(),
        bankLastSeen = existing.bankLastSeen,
        bags         = snapshotBagSlots(),
        bank         = existing.bank or {},
        gold         = GetMoney and GetMoney() or existing.gold,
    }
end

function AV:SnapshotBank()
    -- Guard: bank slot data is zeroed when the bank is closed. GET_ITEM_INFO_RECEIVED
    -- triggers BANK_DIRTY even with the bank closed, so without this check we'd
    -- overwrite the stored bank snapshot with an empty array.
    if not (WB.Bank and WB.Bank.panel and WB.Bank.panel:IsShown()) then return end
    local slots = snapshotBankSlots()
    if #slots == 0 then return end
    WB.altDB = WB.altDB or {}
    local key      = charKey()
    local existing = WB.altDB[key] or {}
    WB.altDB[key] = {
        bagsLastSeen = existing.bagsLastSeen,
        bankLastSeen = time(),
        bags         = existing.bags or {},
        bank         = slots,
        gold         = GetMoney and GetMoney() or existing.gold,
    }
end

-- ============================================================
-- Display-only slot pool (no ContainerFrame template needed)
-- ============================================================
local slotPools  = { bank = {}, bags = {} }
local slotInUse  = { bank = {}, bags = {} }

local function buildDisplaySlot(parent)
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(SLOT_SIZE, SLOT_SIZE)
    UI:NewTexture(host, "BACKGROUND", { 0, 0, 0, 0.4 }):SetAllPoints(host)

    local icon = host:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     1,  -1)
    icon:SetPoint("BOTTOMRIGHT", -1,  1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    host._iconTex = icon

    local cnt = host:CreateFontString(nil, "OVERLAY")
    cnt:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    cnt:SetPoint("BOTTOMRIGHT", -1, 1)
    cnt:SetJustifyH("RIGHT")
    host._countText = cnt

    local function edge(p1, p2, w, h)
        local t = host:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    host._qEdges = {
        edge("TOPLEFT",    "TOPRIGHT",    nil, 2),
        edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2),
        edge("TOPLEFT",    "BOTTOMLEFT",  2,   nil),
        edge("TOPRIGHT",   "BOTTOMRIGHT", 2,   nil),
    }
    local function setQBorder(c)
        for _, t in ipairs(host._qEdges) do
            t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
    host._setQualityBorder = setQBorder
    setQBorder({ 0.20, 0.18, 0.34, 1 })

    host:EnableMouse(true)
    host:SetScript("OnEnter", function(self)
        if not self._link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(function() GameTooltip:SetHyperlink(self._link) end)
        if not ok then
            GameTooltip:SetText(self._link:match("%[(.-)%]") or "?", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    host:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return host
end

local function acquireSlot(parent, poolName, idx)
    local pool  = slotPools[poolName]
    local inUse = slotInUse[poolName]
    local s = pool[idx] or buildDisplaySlot(parent)
    pool[idx] = s
    s:SetParent(parent)
    s:Show()
    inUse[idx] = true
    return s
end

local function releaseSlots(poolName)
    local pool  = slotPools[poolName]
    local inUse = slotInUse[poolName]
    for i = 1, #pool do
        if inUse[i] then
            pool[i]:Hide()
            pool[i]:ClearAllPoints()
            inUse[i] = false
        end
    end
end

local function dressSlot(s, it)
    s._link = it.link
    if it.icon then
        s._iconTex:SetTexture(it.icon)
        s._iconTex:Show()
        if it.count and it.count > 1 then
            s._countText:SetText(tostring(it.count)); s._countText:Show()
        else
            s._countText:SetText("")
        end
        local qc = UI.C_QUALITY[it.quality or 1] or UI.C_QUALITY[1]
        s._setQualityBorder({ qc[1], qc[2], qc[3], qc[4] or 1 })
    else
        s._iconTex:SetTexture(nil); s._iconTex:Hide()
        s._countText:SetText("")
        s._setQualityBorder({ 0.20, 0.18, 0.34, 1 })
    end
end

-- ============================================================
-- Category header + group container pools (separate per section)
-- ============================================================
local catHeaderPools   = { bank = {}, bags = {} }
local groupContPools   = { bank = {}, bags = {} }

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

local function getCategoryHeader(parent, poolName, idx)
    local pool = catHeaderPools[poolName]
    local h = pool[idx]
    if not h then
        local f = CreateFrame("Frame", nil, parent)
        f:SetHeight(CATEGORY_H)
        local lbl = UI:NewText(f, 8, UI.C_TEXT_DIM)
        lbl:SetPoint("BOTTOM", 0, 3)
        if lbl.SetWordWrap then lbl:SetWordWrap(false) end
        f._label = lbl
        h = f; pool[idx] = h
    end
    h:SetParent(parent); h:Show()
    return h
end

local function hideUnusedHeaders(poolName, used)
    local pool = catHeaderPools[poolName]
    for i = used + 1, #pool do pool[i]:Hide(); pool[i]:ClearAllPoints() end
end

local function getGroupContainer(parent, poolName, idx, isBankSection)
    local pool = groupContPools[poolName]
    local f = pool[idx]
    if not f then
        f = CreateFrame("Frame", nil, parent)
        if isBankSection then
            UI:AddBorder(f, C_BANK_BORDER)
        else
            UI:AddBorder(f, UI.C_BORDER)
        end
        local labelColor = isBankSection and UI.C_BORDER or UI.C_GREEN
        local lbl = UI:NewText(f, 10, labelColor)
        lbl:SetPoint("TOP", 0, -3)
        f._label = lbl
        pool[idx] = f
    end
    f:SetParent(parent); f:Show()
    return f
end

local function hideUnusedGroups(poolName, used)
    local pool = groupContPools[poolName]
    for i = used + 1, #pool do pool[i]:Hide(); pool[i]:ClearAllPoints() end
end

-- ============================================================
-- Masonry layout for one section
-- Returns totalH (content height, not including top padding)
-- ============================================================
local function layoutSection(body, contentW, items, poolName, isBankSection, filter)
    local SLOT_W = SLOT_SIZE + SLOT_GAP
    local filterLow = filter and filter ~= "" and filter:lower() or nil

    releaseSlots(poolName)

    -- Bucket items by pre-stored category, applying optional name filter
    local buckets = {}
    for _, it in ipairs(items) do
        if filterLow then
            local name = (it.link and it.link:match("%[(.-)%]") or ""):lower()
            if not name:find(filterLow, 1, true) then
                -- skip this item
            else
                local cat = it.cat or "Misc"
                buckets[cat] = buckets[cat] or {}
                buckets[cat][#buckets[cat] + 1] = it
            end
        else
            local cat = it.cat or "Misc"
            buckets[cat] = buckets[cat] or {}
            buckets[cat][#buckets[cat] + 1] = it
        end
    end

    -- Sort within buckets: quality desc, then name asc
    for _, bucket in pairs(buckets) do
        table.sort(bucket, function(a, b)
            local qa, qb = a.quality or 0, b.quality or 0
            if qa ~= qb then return qa > qb end
            local na = (a.link and a.link:match("%[(.-)%]") or ""):lower()
            local nb = (b.link and b.link:match("%[(.-)%]") or ""):lower()
            return na < nb
        end)
    end

    -- Build block specs, preserving DISPLAY_ORDER where possible
    local ordered = CT:OrderedCategories()
    local blocks, seenCat = {}, {}
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
        if cat ~= "Recent" and cat ~= "Free" then
            seenCat[cat] = true
            addBlock(cat, buckets[cat])
        end
    end
    local extras = {}
    for cat in pairs(buckets) do
        if not seenCat[cat] and cat ~= "Recent" and cat ~= "Free" then
            extras[#extras + 1] = cat
        end
    end
    table.sort(extras)
    for _, cat in ipairs(extras) do addBlock(cat, buckets[cat]) end

    -- Group blocks by parent class
    local groups, groupByParent = {}, {}
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
        if #g.blocks == 1 then
            g.containerHeader = g.blocks[1].cat:upper()
            g.blocks[1].skipHeader = true
        else
            g.containerHeader = g.parent:upper()
        end
        for _, blk in ipairs(g.blocks) do
            local minW = blk.slotW
            if not blk.skipHeader then
                local hw = measureHeaderWidth(blk.cat:upper())
                if hw + 4 > minW then minW = hw + 4 end
            end
            blk.w = minW
            blk.h = CATEGORY_H + blk.rows * SLOT_W - SLOT_GAP
        end
    end

    -- Inner masonry per group
    for _, g in ipairs(groups) do
        local availW = contentW - GROUP_PAD_X * 2
        local placed = {}
        local function overlapsSub(x, y, w, h)
            for _, p in ipairs(placed) do
                if x < p.x + p.w + SUB_GAP_X and x + w + SUB_GAP_X > p.x
                   and y < p.y + p.h + SUB_GAP_Y and y + h + SUB_GAP_Y > p.y
                then return true end
            end
            return false
        end
        local subMaxW, subTotalH = 0, 0
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
            if not px then px, py = 0, subTotalH + (subTotalH > 0 and SUB_GAP_Y or 0) end
            blk.subX, blk.subY = px, py
            placed[#placed + 1] = { x = px, y = py, w = blk.w, h = blk.h }
            if px + blk.w > subMaxW then subMaxW = px + blk.w end
            if py + blk.h > subTotalH then subTotalH = py + blk.h end
        end
        local hw = measureHeaderWidth(g.containerHeader) + 12
        g.w = math.max(subMaxW + GROUP_PAD_X * 2, hw)
        g.h = GROUP_PAD_TOP + subTotalH + GROUP_PAD_BOT
    end

    -- Outer masonry: try multiple orderings, pick shortest total height
    local function tryPack(order)
        local placed = {}
        local function overlapsAny(x, y, w, h)
            for _, p in ipairs(placed) do
                if x < p.x + p.w + CAT_GAP_X and x + w + CAT_GAP_X > p.x
                   and y < p.y + p.h + CAT_GAP_Y and y + h + CAT_GAP_Y > p.y
                then return true end
            end
            return false
        end
        local positions, totalH = {}, 0
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
                    if x + g.w <= contentW and not overlapsAny(x, y, g.w, g.h) then
                        px, py = x, y; break
                    end
                end
                if px then break end
            end
            if not px then px, py = 0, totalH + (totalH > 0 and CAT_GAP_Y or 0) end
            positions[g] = { x = px, y = py }
            placed[#placed + 1] = { x = px, y = py, w = g.w, h = g.h }
            if py + g.h > totalH then totalH = py + g.h end
        end
        return totalH, positions
    end

    local function copyOrder()
        local out = {}; for i, g in ipairs(groups) do out[i] = g end; return out
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
    if not bestPositions then return 0 end

    for _, g in ipairs(groups) do
        local p = bestPositions[g]; g.x, g.y = p.x, p.y
    end

    -- Render group containers, sub-headers, and slots
    local nextHdrIdx, nextSlotIdx, nextGrpIdx = 1, 1, 0
    for _, g in ipairs(groups) do
        nextGrpIdx = nextGrpIdx + 1
        local container = getGroupContainer(body, poolName, nextGrpIdx, isBankSection)
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", body, "TOPLEFT", g.x, -g.y)
        container:SetSize(g.w, g.h)
        container._label:SetText(g.containerHeader)

        local subBaseX = g.x + GROUP_PAD_X
        local subBaseY = g.y + GROUP_PAD_TOP

        for _, blk in ipairs(g.blocks) do
            if not blk.skipHeader then
                local hdr = getCategoryHeader(body, poolName, nextHdrIdx)
                nextHdrIdx = nextHdrIdx + 1
                hdr:ClearAllPoints()
                hdr:SetPoint("TOPLEFT", body, "TOPLEFT", subBaseX + blk.subX, -(subBaseY + blk.subY))
                hdr:SetWidth(blk.w)
                hdr._label:SetText(blk.cat:upper())
            end
            local slotsY = CATEGORY_H
            local slotsX = math.max(0, math.floor((blk.w - blk.slotW) / 2))
            for j, it in ipairs(blk.items) do
                local col = (j - 1) % blk.cols
                local row = math.floor((j - 1) / blk.cols)
                local sx = subBaseX + blk.subX + slotsX + col * SLOT_W
                local sy = subBaseY + blk.subY + slotsY + row * SLOT_W
                local s = acquireSlot(body, poolName, nextSlotIdx)
                nextSlotIdx = nextSlotIdx + 1
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", body, "TOPLEFT", sx, -sy)
                dressSlot(s, it)
            end
        end
    end

    hideUnusedHeaders(poolName, nextHdrIdx - 1)
    hideUnusedGroups(poolName, nextGrpIdx)

    return bestH
end

-- ============================================================
-- Character dropdown
-- ============================================================
local function buildDropdown(panel)
    local dd = CreateFrame("Frame", nil, panel)
    dd:SetFrameStrata("TOOLTIP")
    dd:SetSize(200, 10)
    UI:NewTexture(dd, "BACKGROUND", UI.C_BG):SetAllPoints(dd)
    UI:AddBorder(dd, UI.C_BORDER)
    dd:Hide()
    dd._buttons = {}

    local ROW_H = 20

    function dd:Populate(keys, onSelect)
        for _, b in ipairs(self._buttons) do b:Hide() end
        self._buttons = {}
        if #keys == 0 then self:Hide(); return end

        table.sort(keys)
        for i, key in ipairs(keys) do
            local b = CreateFrame("Button", nil, self)
            b:SetHeight(ROW_H)
            b:SetPoint("TOPLEFT",  self, "TOPLEFT",  4, -(i - 1) * ROW_H - 4)
            b:SetPoint("TOPRIGHT", self, "TOPRIGHT", -4, -(i - 1) * ROW_H - 4)
            local txt = UI:NewText(b, 10, UI.C_TEXT_NORMAL)
            txt:SetPoint("LEFT", 4, 0)
            txt:SetText(key)
            local hl = UI:NewTexture(b, "BACKGROUND", { UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 0.15 })
            hl:SetAllPoints(b); hl:Hide()
            b:SetScript("OnEnter", function()
                hl:Show()
                txt:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1)
            end)
            b:SetScript("OnLeave", function()
                hl:Hide()
                txt:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1)
            end)
            b:SetScript("OnClick", function()
                onSelect(key); self:Hide()
            end)
            self._buttons[#self._buttons + 1] = b
        end
        self:SetHeight(#keys * ROW_H + 8)
        self:Show()
    end

    return dd
end

-- ============================================================
-- Time-ago helper
-- ============================================================
local function timeAgo(ts)
    if not ts then return "" end
    local ago = time() - ts
    if ago < 120     then return "just now"
    elseif ago < 3600   then return math.floor(ago / 60) .. "m ago"
    elseif ago < 86400  then return math.floor(ago / 3600) .. "h ago"
    else                     return math.floor(ago / 86400) .. "d ago"
    end
end

-- ============================================================
-- Build the viewer panel
-- ============================================================
local function buildPanel()
    local panel = CreateFrame("Frame", "WicksAltViewerPanel", UIParent)
    panel:SetSize(MAX_PANEL_W, 300)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:SetResizable(true)
    if panel.SetResizeBounds then
        panel:SetResizeBounds(MIN_PANEL_W, 150, 1400, UIParent:GetHeight() - 40)
    elseif panel.SetMinResize then
        panel:SetMinResize(MIN_PANEL_W, 150)
    end
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")

    -- pos pre-seeded in DB_DEFAULTS; posPoint == false means no saved position yet
    local pos = WB.db.avPos
    if pos.posPoint and pos.posPoint ~= false then
        panel:SetPoint(pos.posPoint, UIParent, pos.posRel, pos.posX or 0, pos.posY or 0)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    if pos.panelW and pos.panelW > 0 then
        panel:SetWidth(pos.panelW)
    end

    UI:NewTexture(panel, "BACKGROUND", UI.C_BG):SetAllPoints(panel)
    UI:AddBorder(panel)
    UI:AddCornerAccents(panel)

    local function snapPosition()
        local p, _, rp, x, y = panel:GetPoint()
        if not p then return end
        -- In-place mutation (table reference is preserved from DB_DEFAULTS).
        -- Replacing the table reference creates a fresh runtime object that
        -- the TBC Anniversary saved-variable serializer doesn't pick up.
        local t = WB.db.avPos
        t.posPoint = p
        t.posRel   = rp or p
        t.posX     = x or 0
        t.posY     = y or 0
        t.panelW   = panel:GetWidth()
    end

    panel._snapPosition = snapPosition
    panel:SetScript("OnMouseDown", function(self) self:Raise() end)
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing(); snapPosition()
    end)

    -- Header
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT",  panel, "TOPLEFT",  1, -1)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    UI:NewTexture(header, "BACKGROUND", UI.C_HEADER_BG):SetAllPoints(header)
    local divider = UI:NewTexture(header, "BORDER", UI.C_BORDER)
    divider:SetPoint("BOTTOMLEFT"); divider:SetPoint("BOTTOMRIGHT"); divider:SetHeight(1)

    UI:AddTitleText(header, "Alts", "LEFT", 8, 0)

    -- Close X
    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    local xTxt = UI:NewText(close, 14, UI.C_TEXT_DIM)
    xTxt:SetPoint("CENTER"); xTxt:SetText("\195\151")
    close:SetScript("OnClick", function() AV:Hide() end)
    close:SetScript("OnEnter", function() xTxt:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1) end)
    close:SetScript("OnLeave", function() xTxt:SetTextColor(UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], 1) end)

    -- Character selector button
    local charBtn = CreateFrame("Button", nil, header)
    charBtn:SetSize(180, 18)
    charBtn:SetPoint("RIGHT", close, "LEFT", -8, 0)
    UI:NewTexture(charBtn, "BACKGROUND", { 0, 0, 0, 0.4 }):SetAllPoints(charBtn)
    UI:AddBorder(charBtn, UI.C_BORDER)
    local charTxt = UI:NewText(charBtn, 10, UI.C_TEXT_NORMAL)
    charTxt:SetPoint("LEFT", 6, 0)
    charTxt:SetText("Select character...")
    local chevron = UI:NewText(charBtn, 10, UI.C_TEXT_DIM)
    chevron:SetPoint("RIGHT", -5, 0)
    chevron:SetText("v")
    charBtn:SetScript("OnEnter", function()
        charTxt:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1)
    end)
    charBtn:SetScript("OnLeave", function()
        charTxt:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1)
    end)
    panel._charBtn = charBtn
    panel._charTxt = charTxt

    -- Toolbar row: gold on left, filter search box on right
    local toolbar = CreateFrame("Frame", nil, panel)
    toolbar:SetPoint("TOPLEFT",  panel, "TOPLEFT",  1, -(HEADER_H + 1))
    toolbar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -(HEADER_H + 1))
    toolbar:SetHeight(TOOLBAR_H)
    UI:NewTexture(toolbar, "BACKGROUND", { UI.C_HEADER_BG[1], UI.C_HEADER_BG[2], UI.C_HEADER_BG[3], 0.6 }):SetAllPoints(toolbar)
    local toolbarDiv = UI:NewTexture(toolbar, "BORDER", UI.C_BORDER)
    toolbarDiv:SetPoint("BOTTOMLEFT"); toolbarDiv:SetPoint("BOTTOMRIGHT"); toolbarDiv:SetHeight(1)

    local goldTxt = UI:NewText(toolbar, 11, UI.C_TEXT_NORMAL)
    goldTxt:SetPoint("LEFT", toolbar, "LEFT", 8, 0)
    goldTxt:SetText("")
    panel._goldTxt = goldTxt

    local avSearch = CreateFrame("EditBox", nil, toolbar)
    avSearch:SetHeight(18)
    avSearch:SetPoint("LEFT",  toolbar, "LEFT",  130, 0)
    avSearch:SetPoint("RIGHT", toolbar, "RIGHT", -8,  0)
    avSearch:SetAutoFocus(false)
    avSearch:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    avSearch:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1)
    avSearch:SetMaxLetters(40)
    avSearch:SetText("")
    UI:AddBorder(avSearch)
    UI:NewTexture(avSearch, "BACKGROUND", UI.C_BG):SetAllPoints(avSearch)
    avSearch:SetTextInsets(4, 4, 0, 0)
    panel._avSearch = avSearch
    local avPlaceholder = UI:NewText(avSearch, 10, UI.C_TEXT_DIM)
    avPlaceholder:SetPoint("LEFT", 4, 0)
    avPlaceholder:SetText("Filter items...")
    avSearch:SetScript("OnTextChanged", function(self)
        avPlaceholder:SetShown(self:GetText() == "")
        if AV.panel and AV.panel:IsShown() then AV:Refresh() end
    end)
    avSearch:SetScript("OnEscapePressed", function(self)
        self:SetText(""); self:ClearFocus()
    end)

    -- Body
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT",     panel, "TOPLEFT",     PADDING, -(HEADER_H + TOOLBAR_H + PADDING))
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING, PADDING)
    panel._body = body

    -- Empty / hint message
    local emptyMsg = UI:NewText(body, 11, UI.C_TEXT_DIM)
    emptyMsg:SetPoint("CENTER"); emptyMsg:SetText("")
    panel._emptyMsg = emptyMsg

    -- Bank section (left)
    local bankSection = CreateFrame("Frame", nil, body)
    UI:NewTexture(bankSection, "BACKGROUND", C_BANK_WASH):SetAllPoints(bankSection)
    UI:AddBorder(bankSection, C_BANK_BORDER)
    panel._bankSection = bankSection

    local bankLabel = UI:NewText(bankSection, 9, UI.C_GREEN)
    bankLabel:SetPoint("TOPLEFT", 6, -4)
    bankLabel:SetText("BANK")
    panel._bankLabel = bankLabel

    local bankAge = UI:NewText(bankSection, 8, UI.C_TEXT_DIM)
    bankAge:SetPoint("LEFT", bankLabel, "RIGHT", 6, 0)
    panel._bankAge = bankAge

    -- Bags section (right)
    local bagsSection = CreateFrame("Frame", nil, body)
    UI:NewTexture(bagsSection, "BACKGROUND", UI.C_BG):SetAllPoints(bagsSection)
    UI:AddBorder(bagsSection, UI.C_BORDER)
    panel._bagsSection = bagsSection

    local bagsLabel = UI:NewText(bagsSection, 9, UI.C_GREEN)
    bagsLabel:SetPoint("TOPLEFT", 6, -4)
    bagsLabel:SetText("BAGS")
    panel._bagsLabel = bagsLabel

    local bagsAge = UI:NewText(bagsSection, 8, UI.C_TEXT_DIM)
    bagsAge:SetPoint("LEFT", bagsLabel, "RIGHT", 6, 0)
    panel._bagsAge = bagsAge

    -- Content sub-frames (parented to their section; holds the masonry slots)
    local bankBody = CreateFrame("Frame", nil, bankSection)
    panel._bankBody = bankBody

    local bagsBody = CreateFrame("Frame", nil, bagsSection)
    panel._bagsBody = bagsBody

    -- Dropdown
    local dropdown = buildDropdown(panel)
    dropdown:SetPoint("TOPRIGHT", charBtn, "BOTTOMRIGHT", 0, -2)
    panel._dropdown = dropdown

    charBtn:SetScript("OnClick", function()
        if dropdown:IsShown() then dropdown:Hide(); return end
        local snaps = WB.altDB or {}
        local keys = {}
        for k in pairs(snaps) do keys[#keys + 1] = k end
        if #keys == 0 then
            GameTooltip:SetOwner(charBtn, "ANCHOR_BOTTOM")
            GameTooltip:SetText("No alt snapshots yet.", 1, 1, 1)
            GameTooltip:AddLine("Log in to another character and open/close their bags.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
            C_Timer.After(3, function() GameTooltip:Hide() end)
            return
        end
        dropdown:Populate(keys, function(key)
            AV._currentKey = key
            panel._charTxt:SetText(key)
            AV:Refresh()
        end)
    end)

    -- Resize grip
    local grip = CreateFrame("Button", nil, panel)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    grip:EnableMouse(true)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            panel._isResizing = true
            panel:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnMouseUp", function()
        panel:StopMovingOrSizing()
        panel._isResizing = false
        snapPosition()
        if AV.Refresh then AV:Refresh() end
    end)

    local resizePending = false
    panel:SetScript("OnSizeChanged", function()
        if resizePending then return end
        resizePending = true
        C_Timer.After(0.05, function()
            resizePending = false
            if AV.Refresh then AV:Refresh() end
        end)
    end)

    return panel
end

-- ============================================================
-- Refresh: populate both section bodies from snapshot
-- ============================================================
function AV:Refresh()
    if not self.panel or not self.panel:IsShown() then return end

    local body  = self.panel._body
    local bodyW = body:GetWidth()
    if bodyW < 100 then
        C_Timer.After(0.05, function()
            if self.panel and self.panel:IsShown() then self:Refresh() end
        end)
        return
    end

    local snap = WB.altDB
                 and self._currentKey
                 and WB.altDB[self._currentKey]

    if not snap then
        self.panel._emptyMsg:SetText(self._currentKey
            and (self._currentKey .. ": no snapshot yet. Open and close bags on that character first.")
            or "Select a character above.")
        self.panel._bankSection:Hide()
        self.panel._bagsSection:Hide()
        return
    end
    self.panel._emptyMsg:SetText("")
    self.panel._bankSection:Show()
    self.panel._bagsSection:Show()

    local sectionW = math.floor((bodyW - SECTION_GAP) / 2)
    local contentW = sectionW - CONTENT_PAD * 2
    if contentW < 50 then contentW = 50 end

    -- Position sections side by side in body
    local bankSection = self.panel._bankSection
    bankSection:ClearAllPoints()
    bankSection:SetPoint("TOPLEFT",    body, "TOPLEFT",    0, 0)
    bankSection:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
    bankSection:SetWidth(sectionW)

    local bagsSection = self.panel._bagsSection
    bagsSection:ClearAllPoints()
    bagsSection:SetPoint("TOPRIGHT",    body, "TOPRIGHT",    0, 0)
    bagsSection:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    bagsSection:SetWidth(sectionW)

    -- Content bodies inside sections (inset from border + section label)
    local topInset = SECTION_LABEL_H + CONTENT_PAD
    local bankBody = self.panel._bankBody
    bankBody:ClearAllPoints()
    bankBody:SetPoint("TOPLEFT",     bankSection, "TOPLEFT",     CONTENT_PAD, -topInset)
    bankBody:SetPoint("BOTTOMRIGHT", bankSection, "BOTTOMRIGHT", -CONTENT_PAD, CONTENT_PAD)

    local bagsBody = self.panel._bagsBody
    bagsBody:ClearAllPoints()
    bagsBody:SetPoint("TOPLEFT",     bagsSection, "TOPLEFT",     CONTENT_PAD, -topInset)
    bagsBody:SetPoint("BOTTOMRIGHT", bagsSection, "BOTTOMRIGHT", -CONTENT_PAD, CONTENT_PAD)

    -- Layout each section
    local filter = (self.panel._avSearch and self.panel._avSearch:GetText()) or ""
    local bankH = layoutSection(bankBody, contentW, snap.bank or {}, "bank", true,  filter)
    local bagH  = layoutSection(bagsBody, contentW, snap.bags or {}, "bags", false, filter)

    -- Update age and gold labels
    self.panel._bankAge:SetText(timeAgo(snap.bankLastSeen))
    self.panel._bagsAge:SetText(timeAgo(snap.bagsLastSeen))
    if self.panel._goldTxt then
        self.panel._goldTxt:SetText(snap.gold and formatGold(snap.gold) or "")
    end

    -- Fit panel height to content
    local contentH = math.max(bankH, bagH, 40)
    local fitH = HEADER_H + TOOLBAR_H + PADDING + topInset + contentH + CONTENT_PAD + PADDING
    fitH = math.min(fitH, UIParent:GetHeight() - 80)
    if not self.panel._isResizing then
        self.panel:SetHeight(fitH)
    end
end

-- ============================================================
-- Lifecycle
-- ============================================================
function AV:Init()
    if self.initialized then return end
    self.initialized = true
    self._currentKey = nil
    self.panel = buildPanel()
    self.panel:Hide()
end

function AV:Show()
    if not self.panel then self:Init() end
    -- avPos is pre-seeded in DB_DEFAULTS so it's always present; posPoint
    -- == false means "no saved position yet" (use the build-time default).
    local pos = WB.db.avPos
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

function AV:Hide()
    if not self.panel then return end
    if self.panel._snapPosition then self.panel._snapPosition() end
    self.panel:Hide()
    if WB.Bag and WB.Bag.panel and WB.Bag.panel._refreshTitleIcons then
        WB.Bag.panel._refreshTitleIcons()
    end
end

function AV:Toggle()
    if not self.panel then self:Init() end
    if self.panel:IsShown() then self:Hide() else self:Show() end
end

-- ============================================================
-- Event wiring
-- ============================================================
WB:On("LOGIN", function() AV:Init() end)

-- Bag snapshot: debounced 3s after any bag change.
-- PLAYER_LOGOUT is unreliable — container data is often zeroed before it
-- fires in TBC 2.5.5. BAGS_DIRTY fires during live play when data is valid.
local _bagSnapQueued = false
WB:On("BAGS_DIRTY", function()
    if _bagSnapQueued then return end
    _bagSnapQueued = true
    C_Timer.After(3.0, function()
        _bagSnapQueued = false
        AV:SnapshotBags()
    end)
end)

-- Bank snapshot: debounced 2s after any bank change (while bank is open).
-- BANKFRAME_CLOSED is similarly unreliable — bank slots are cleared before
-- the event fires on this build. BANK_DIRTY fires while the bank is open.
local _bankSnapQueued = false
local function scheduleBankSnapshot()
    if _bankSnapQueued then return end
    _bankSnapQueued = true
    C_Timer.After(2.0, function()
        _bankSnapQueued = false
        AV:SnapshotBank()
    end)
end
WB:On("BANK_DIRTY",   scheduleBankSnapshot)
-- Also snapshot on open (after 1s delay for slot data to fully populate).
WB:On("BANK_OPENED",  function() C_Timer.After(1.0, scheduleBankSnapshot) end)
