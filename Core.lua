-- Wick's Bags
-- Core.lua: namespace, saved variables, event dispatch, slash command.

local ADDON, ns = ...

-- ============================================================
-- TBC Anniversary 2.5.5 namespaced calls
-- ============================================================
-- Resolve once at load with fallback to legacy globals so older clients still work.
ns.GetNumAddOns       = (C_AddOns   and C_AddOns.GetNumAddOns)            or GetNumAddOns
ns.GetAddOnInfo       = (C_AddOns   and C_AddOns.GetAddOnInfo)            or GetAddOnInfo
ns.IsAddOnLoaded      = (C_AddOns   and C_AddOns.IsAddOnLoaded)           or IsAddOnLoaded
ns.LoadAddOn          = (C_AddOns   and C_AddOns.LoadAddOn)               or LoadAddOn
ns.GetAddOnMetadata   = (C_AddOns   and C_AddOns.GetAddOnMetadata)        or GetAddOnMetadata
ns.GetItemCooldown    = (C_Container and C_Container.GetItemCooldown)     or GetItemCooldown
ns.GetContainerNumSlots       = (C_Container and C_Container.GetContainerNumSlots)       or GetContainerNumSlots
ns.GetContainerItemLink       = (C_Container and C_Container.GetContainerItemLink)       or GetContainerItemLink
ns.GetContainerItemID         = (C_Container and C_Container.GetContainerItemID)         or GetContainerItemID
ns.PickupContainerItem        = (C_Container and C_Container.PickupContainerItem)        or PickupContainerItem
ns.UseContainerItem           = (C_Container and C_Container.UseContainerItem)           or UseContainerItem
ns.ContainerIDToInventoryID   = (C_Container and C_Container.ContainerIDToInventoryID)   or ContainerIDToInventoryID
-- C_Container.GetContainerItemInfo returns a TABLE in TBC Anniversary 2.5.5.
-- Legacy GetContainerItemInfo returned a multi-value tuple. Wrap to expose
-- a stable multi-return regardless of which form is available.
ns.GetContainerItemInfo = function(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.iconFileID, info.stackCount, info.isLocked, info.quality,
                   info.isReadable, info.hasLoot, info.hyperlink,
                   info.isFiltered, info.hasNoValue, info.itemID, info.isBound
        end
        return nil
    end
    if GetContainerItemInfo then
        return GetContainerItemInfo(bag, slot)
    end
    return nil
end

-- ============================================================
-- Saved variables: defaults
-- ============================================================
WicksBagsDB = WicksBagsDB or {}
local DB_DEFAULTS = {
    -- All UI state lives nested under `ui`. New scalar keys added by
    -- applyDefaults DO persist when nested (proof: the old code's `bx`/
    -- `by`/`w` writes are still in the saved file). Top-level scalar
    -- additions to WicksBagsDB do NOT persist on this build.
    ui = {
        hidden   = true,
    },
    -- Panel positions stored as flat keys inside each pos table.
    -- These tables are in DB_DEFAULTS so WoW tracks them from first load;
    -- snapPosition() mutates keys in-place (proven pattern for persistence).
    bagPos  = { posPoint = false, posRel = false, posX = 0, posY = 0, panelW = 0 },
    bankPos = { posPoint = false, posRel = false, posX = 0, posY = 0, panelW = 0 },
    avPos   = { posPoint = false, posRel = false, posX = 0, posY = 0, panelW = 0 },
    options = {
        showJunk        = true,
        showHighlights  = true,
        sortMode        = "quality",   -- "quality" | "name" | "quantity"
        qualityMin      = 0,           -- 0=show all, 1=Common+, 2=Uncommon+, 3=Rare+, 4=Epic+
        showSearch      = true,
        showBagBar      = true,
        showHonor       = true,
        showArena       = true,
        showMarks       = true,        -- all four BG Marks of Honor
        showBadges      = true,        -- Badge of Justice + Apexis tokens
        showShards      = true,        -- Spirit Shard
        showRep         = true,        -- faction commendations / tokens
        borderIntensity = 1.0,         -- 0.0 (off) -> 1.0 (full); scales ALL quality-color borders uniformly
        showItemLevel   = true,        -- top-left ilvl text on equipment slots
        slotScale       = 1.0,         -- 0.8 .. 1.5 multiplier on slot size
        useItemRack     = true,        -- when ItemRack is loaded, bucket items by set name
        hideDefaultBank = true,        -- suppress Blizzard's BankFrame; show only Wick's Bank
        suppressAutoBags = true,       -- close Blizzard's default bag UI when it auto-opens at bank/vendor
        autoOpenBags = true,           -- auto-open Wick's Bags at mailbox/vendor/bank/AH/tradeskill
        activeSourceId  = "auto",
    },
    -- User-defined category overrides. Editable directly in saved variables;
    -- a UI for managing these lands in v0.4. Resolution order in Categories.lua:
    -- byItemId (exact) -> patterns (substring on name) -> auto -> Misc.
    customRules = {
        byItemId = {},      -- [itemID] = "My Custom Category"
        patterns = {},      -- ordered list: { { match = "Mageweave", category = "Mageweave Set" }, ... }
    },
}

local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            applyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

-- IMPORTANT: WoW's TBC Anniversary build loads SavedVariables AFTER addon
-- file-scope code runs (proven via the DEBUG trace — bagPos was nil at
-- file-scope but populated by PLAYER_LOGIN time). So we cannot apply
-- defaults at file-scope; we'd be applying them to a fresh empty table
-- that gets replaced when WoW loads the file. Defer to ADDON_LOADED.
local function initSavedVars()
    WicksBagsDB  = WicksBagsDB  or {}
    WicksBagsAlts = WicksBagsAlts or {}
    -- Migrate pre-split altSnapshots from WicksBagsDB to WicksBagsAlts.
    if WicksBagsDB.altSnapshots and next(WicksBagsDB.altSnapshots) then
        for key, snap in pairs(WicksBagsDB.altSnapshots) do
            if not WicksBagsAlts[key] then WicksBagsAlts[key] = snap end
        end
        WicksBagsDB.altSnapshots = nil
    end
    applyDefaults(WicksBagsDB, DB_DEFAULTS)
    -- Rebind WB.db so any later function calls hit the loaded global.
    if WicksBags then
        WicksBags.db    = WicksBagsDB
        WicksBags.altDB = WicksBagsAlts
    end
end

WicksBagsCharDB = WicksBagsCharDB or { version = 1 }

-- ============================================================
-- Namespace
-- ============================================================
WicksBags = WicksBags or {}
local WB = WicksBags
ns.WB = WB
WB.ADDON = ADDON
-- WB.db / WB.altDB are set by initSavedVars() on ADDON_LOADED, after WoW
-- actually loads the saved file. Setting them here at file-scope would
-- cache a reference to a fresh-empty table that gets replaced when the
-- file loads, leaving WB.db stale.
WB.db    = WicksBagsDB   or {}    -- placeholder; rebound on ADDON_LOADED
WB.altDB = WicksBagsAlts or {}    -- placeholder; rebound on ADDON_LOADED
WB.charDB = WicksBagsCharDB or { version = 1 }

-- ============================================================
-- Pub/sub event bus (internal events between modules)
-- ============================================================
WB._listeners = {}
function WB:On(event, fn)
    self._listeners[event] = self._listeners[event] or {}
    table.insert(self._listeners[event], fn)
end
function WB:Emit(event, ...)
    local list = self._listeners[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then
            print(("|cff4FC778Wick's Bags|r error in %s: %s"):format(event, tostring(err)))
        end
    end
end

-- ============================================================
-- WoW event frame
-- ============================================================
local f = CreateFrame("Frame")
WB.eventFrame = f
local EVENTS = {
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "BAG_UPDATE",
    "BAG_UPDATE_DELAYED",
    "ITEM_LOCK_CHANGED",
    "GET_ITEM_INFO_RECEIVED",
    "PLAYER_MONEY",
    "BAG_UPDATE_COOLDOWN",
    "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED",
    "PLAYERBANKBAGSLOTS_CHANGED",
    "MERCHANT_SHOW",
    "MERCHANT_CLOSED",
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_CLOSE",
    "PLAYER_LOGOUT",
}

-- Track whether we auto-opened the bag panel — used to avoid closing
-- bags the user opened manually before walking up to a mailbox/vendor.
local autoOpenedBag = false

local function suppressBlizzBags()
    if WB.db and WB.db.options and WB.db.options.suppressAutoBags == false then return end
    -- Schedule on a tick so we run after Blizzard's own auto-open.
    C_Timer.After(0.05, function()
        if CloseAllBags then CloseAllBags() end
    end)
end

local function autoOpenBag()
    if not WB.db or not WB.db.options then return end
    if WB.db.options.autoOpenBags == false then return end
    if not WB.Bag then return end
    if not WB.db.ui.hidden then return end  -- already open; user opened it, don't track
    autoOpenedBag = true
    WB.Bag:Show()
end

local function autoCloseBag()
    if not autoOpenedBag then return end
    autoOpenedBag = false
    if WB.Bag and WB.Bag.Hide then WB.Bag:Hide() end
end
for _, e in ipairs(EVENTS) do
    pcall(f.RegisterEvent, f, e)
end

-- BAG_UPDATE fires per-bag and many times in a row. Coalesce via a short
-- timer that fires at most every 0.05s. BAG_UPDATE_DELAYED is Blizzard's
-- own coalesced event, but it doesn't always fire. Use both.
local refreshDirty = false
local function scheduleRefresh()
    if refreshDirty then return end
    refreshDirty = true
    C_Timer.After(0.05, function()
        refreshDirty = false
        WB:Emit("BAGS_DIRTY")
    end)
end

local bankDirty = false
local function scheduleBankRefresh()
    if bankDirty then return end
    bankDirty = true
    C_Timer.After(0.05, function()
        bankDirty = false
        WB:Emit("BANK_DIRTY")
    end)
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local arg1 = ...
        if arg1 == ADDON then
            -- Saved variables are now loaded. Apply defaults, run
            -- migrations, and (re)bind WB.db / WB.altDB to the loaded
            -- globals. This is the canonical "saved vars ready" event
            -- on this build; doing it earlier (file-scope) misses the
            -- file content entirely.
            initSavedVars()
        end
    elseif event == "PLAYER_LOGIN" then
        WB:Emit("LOGIN")
        print("|cff4FC778Wick's Bags|r loaded. /wbags to toggle.")
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED" then
        scheduleRefresh()
        -- ITEM_LOCK_CHANGED also fires on bank slots; nudge bank too
        if event == "ITEM_LOCK_CHANGED" then scheduleBankRefresh() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        scheduleRefresh()
        scheduleBankRefresh()
    elseif event == "PLAYER_MONEY" then
        WB:Emit("MONEY_CHANGED")
    elseif event == "BAG_UPDATE_COOLDOWN" then
        WB:Emit("COOLDOWN_CHANGED")
    elseif event == "BANKFRAME_OPENED" then
        WB:Emit("BANK_OPENED")
        suppressBlizzBags()
        autoOpenBag()
    elseif event == "BANKFRAME_CLOSED" then
        WB:Emit("BANK_CLOSED")
        autoCloseBag()
    elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        scheduleBankRefresh()
    elseif event == "MERCHANT_SHOW"
        or event == "MAIL_SHOW"
        or event == "AUCTION_HOUSE_SHOW"
        or event == "TRADE_SKILL_SHOW" then
        suppressBlizzBags()
        autoOpenBag()
    elseif event == "MERCHANT_CLOSED"
        or event == "MAIL_CLOSED"
        or event == "AUCTION_HOUSE_CLOSED"
        or event == "TRADE_SKILL_CLOSE" then
        autoCloseBag()
    elseif event == "PLAYER_LOGOUT" then
        -- Snap all panel positions before the game serializes SavedVariables.
        if WB.Bag and WB.Bag.panel and WB.Bag.panel._snapPosition then
            WB.Bag.panel._snapPosition()
        end
        if WB.Bank and WB.Bank.panel and WB.Bank.panel._snapPosition then
            WB.Bank.panel._snapPosition()
        end
        if WB.AltViewer and WB.AltViewer.panel and WB.AltViewer.panel._snapPosition then
            WB.AltViewer.panel._snapPosition()
        end
    end
    WB:Emit(event, ...)
end)

-- ============================================================
-- Slash command
-- ============================================================
-- Multiple aliases: /wbags is the primary unique slug, /wicksbags the long
-- form. /wb is kept as a convenience but may conflict with other addons
-- (WeakAuras and others register it). If /wb doesn't respond to our
-- subcommands, use /wbags instead.
SLASH_WICKSBAGS1 = "/wbags"
SLASH_WICKSBAGS2 = "/wicksbags"
SLASH_WICKSBAGS3 = "/wb"
SlashCmdList.WICKSBAGS = function(input)
    input = (input or ""):gsub("^%s*(.-)%s*$", "%1"):lower()
    if input == "" or input == "toggle" then
        if WB.Bag and WB.Bag.Toggle then WB.Bag:Toggle() end
        return
    end
    if input == "show" and WB.Bag then WB.Bag:Show()  return end
    if input == "hide" and WB.Bag then WB.Bag:Hide()  return end
    if input == "reset" and WB.Bag then WB.Bag:ResetPosition()  return end
    if input == "help" or input == "?" then
        print("|cff4FC778Wick's Bags|r")
        print("  /wbags                 toggle the panel")
        print("  /wbags show            show")
        print("  /wbags hide            hide")
        print("  /wbags reset           reset position")
        print("  /wbags autoopen on|off auto-open at mailbox/vendor/bank")
        print("  /wbags dump            dump saved-variable state")
        return
    end
    if input:match("^autoopen") then
        local arg = input:match("^autoopen%s+(%S+)")
        if arg == "off" or arg == "false" or arg == "0" then
            WB.db.options.autoOpenBags = false
            print("|cff4FC778Wick's Bags|r: auto-open disabled.")
        elseif arg == "on" or arg == "true" or arg == "1" then
            WB.db.options.autoOpenBags = true
            print("|cff4FC778Wick's Bags|r: auto-open enabled.")
        else
            print(("|cff4FC778Wick's Bags|r: auto-open is %s. Use /wbags autoopen on|off."):format(
                WB.db.options.autoOpenBags == false and "off" or "on"))
        end
        return
    end
    if input == "dump" then
        print("|cff4FC778Wick's Bags|r DB dump:")
        local pos = WB.db.bagPos or {}
        print(("  bagPos.posPoint = %s"):format(tostring(pos.posPoint)))
        print(("  bagPos.posRel   = %s"):format(tostring(pos.posRel)))
        print(("  bagPos.posX     = %s"):format(tostring(pos.posX)))
        print(("  bagPos.posY     = %s"):format(tostring(pos.posY)))
        print(("  bagPos.panelW   = %s"):format(tostring(pos.panelW)))
        print(("  bankPos exists  = %s"):format(tostring(WB.db.bankPos ~= nil)))
        print(("  avPos exists    = %s"):format(tostring(WB.db.avPos ~= nil)))
        print(("  ui.hidden       = %s"):format(tostring(WB.db.ui.hidden)))
        if WB.Bag and WB.Bag.panel and WB.Bag.panel:IsShown() then
            local lp, _, lrp, lx, ly = WB.Bag.panel:GetPoint()
            print(("  panel live pos  = %s/%s x=%s y=%s"):format(tostring(lp), tostring(lrp), tostring(lx), tostring(ly)))
            print(("  panel live w    = %s"):format(tostring(WB.Bag.panel:GetWidth())))
        else
            print("  panel not shown")
        end
        return
    end
    print("|cff4FC778Wick's Bags|r: unknown command. Try /wb help")
end

-- Hide the default bag UI when ours is open? Optional v0.1 polish, deferred.
