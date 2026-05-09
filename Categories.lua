-- Wick's Bags
-- Categories.lua: pluggable category resolver.
--
-- Item -> category lookup chain:
--   1. User custom override (per-itemID; v0.2)
--   2. Active CategorySource (auto / tsm / outfit / etc.)
--   3. "Misc" fallback
--
-- Category sources implement a small interface:
--   source:GetCategoryFor(itemId, itemLink) -> string | nil
--   source:GetCategoryList() -> { "Cat1", "Cat2", ... }   (optional, for UI)
--   source:OnRegister(WB)                                  (optional setup)
--
-- New sources register themselves at file-load time:
--   WB.Categories:RegisterSource("foo", { GetCategoryFor = ..., ... })

local ADDON, ns = ...
local WB = WicksBags

WB.Categories = {}
local CT = WB.Categories

-- ============================================================
-- Source registry
-- ============================================================
CT.sources = {}
CT.sourceOrder = {}   -- registration order, for the options UI dropdown

function CT:RegisterSource(id, source)
    if not source or type(source.GetCategoryFor) ~= "function" then
        print(("|cff4FC778Wick's Bags|r: bad source registration: %s"):format(tostring(id)))
        return
    end
    self.sources[id] = source
    table.insert(self.sourceOrder, id)
    if source.OnRegister then
        pcall(source.OnRegister, source, WB)
    end
end

function CT:ActiveSourceId()
    return WB.db.options.activeSourceId or "auto"
end

function CT:SetActive(id)
    if not self.sources[id] then return end
    WB.db.options.activeSourceId = id
    WB:Emit("CATEGORY_SOURCE_CHANGED", id)
    WB:Emit("BAGS_DIRTY")
end

-- ============================================================
-- Auto-categorize by item type (the always-available default source)
-- ============================================================
-- TBC item class IDs (returned by GetItemInfoInstant as `classID`):
--   0=Consumable, 1=Container, 2=Weapon, 3=Gem, 4=Armor, 5=Reagent,
--   6=Projectile, 7=Trade Goods, 9=Recipe, 11=Quiver, 12=Quest,
--   13=Key, 15=Miscellaneous
--
-- Some subclasses get their own bucket so the user can find them quickly:
--   Class 4 / Sub 11  = Totem  (shaman casting reagent)
--   Class 15 / Sub 5  = Mount
--   Class 15 / Sub 2  = Pet    (companion / vanity pet)
local AUTO_BY_CLASS = {
    [0]  = "Consumable",
    [1]  = "Container",
    [2]  = "Equipment",
    [3]  = "Gem",
    [4]  = "Equipment",
    [5]  = "Trade Goods",
    [6]  = "Projectile",
    [7]  = "Trade Goods",
    [9]  = "Recipe",
    [11] = "Quiver",
    [12] = "Quest",
    [13] = "Key",
    [15] = "Misc",
}

-- Specific (classID, subClassID) overrides take precedence over AUTO_BY_CLASS.
-- This is the bulk of the granular categorization.
local AUTO_BY_CLASS_SUB = {
    -- Consumable (class 0)
    [0] = {
        [1] = "Potion",
        [2] = "Elixir",
        [3] = "Flask",
        [4] = "Scroll",
        [5] = "Food",
        [7] = "Bandage",
        -- 0 (generic), 6 (item enhancement), 8 (other) fall through to "Consumable"
    },
    -- Armor (class 4): break out shaman totems; rest falls through to Equipment
    [4]  = { [11] = "Totem" },
    -- Trade Goods (class 7)
    [7] = {
        [4]  = "Jewelcrafting",
        [5]  = "Cloth",
        [6]  = "Leather",
        [7]  = "Metal & Stone",
        [8]  = "Cooking",       -- meat, fish
        [9]  = "Herb",
        [10] = "Elemental",
        [12] = "Enchanting",    -- dust, essences, shards
    },
    -- Misc (class 15): mounts and pets
    [15] = { [5] = "Mount", [2] = "Pet" },
}

local AUTO_CATEGORY_LIST = {
    "Equipment",
    "Totem",
    "Potion",
    "Elixir",
    "Flask",
    "Scroll",
    "Food",
    "Bandage",
    "Consumable",
    "Cloth",
    "Leather",
    "Metal & Stone",
    "Herb",
    "Elemental",
    "Enchanting",
    "Jewelcrafting",
    "Cooking",
    "Trade Goods",
    "Mount",
    "Pet",
    "Quest",
    "Recipe",
    "Gem",
    "Container",
    "Projectile",
    "Quiver",
    "Key",
    "Junk",
    "Misc",
}

local function autoGet(self, itemId, itemLink)
    if not itemId then return nil end
    -- GetItemInfo: ..., quality, ..., bindType, ...
    -- bindType: 0=none, 1=soulbound, 2=onEquip, 3=onUse, 4=quest
    local _, _, quality, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemId)
    -- Quest-bound items override class entirely. Many quest items live in
    -- class 0 (Consumable) or 15 (Misc) but are gameplay-quest items —
    -- the Demonic Stone in a Hellfire quest is class 0 but logically Quest.
    if bindType == 4 then return "Quest" end
    if quality == 0 then return "Junk" end
    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemId)
    -- Subclass override first
    local subTable = AUTO_BY_CLASS_SUB[classID]
    if subTable and subTable[subClassID] then return subTable[subClassID] end
    return AUTO_BY_CLASS[classID] or "Misc"
end

local function autoList(self)
    return AUTO_CATEGORY_LIST
end

CT:RegisterSource("auto", {
    name = "Auto (by item type)",
    GetCategoryFor = autoGet,
    GetCategoryList = autoList,
})

-- ============================================================
-- ItemRack source: pulls categories from ItemRack's gear sets.
-- ============================================================
-- Each item that belongs to an ItemRack set gets bucketed under that set's
-- name. Items that aren't in any set return nil here so the resolver chain
-- falls through to the auto categorizer.
--
-- ItemRack stores its sets in `ItemRackUser.Sets`. Each set has an `equip`
-- field that's a slot-keyed table of itemstrings ("itemID:enchantID:...").
-- We extract the leading numeric itemID and reverse-map item -> set name.

local itemRackMap = nil          -- [itemID] = setName, lazily built
local itemRackSetNames = {}      -- [setName] = true, used by GetParent so set names route under Equipment
local function buildItemRackMap()
    local map = {}
    wipe(itemRackSetNames)
    if not ItemRackUser or type(ItemRackUser.Sets) ~= "table" then return map end
    for setName, setData in pairs(ItemRackUser.Sets) do
        -- Skip pseudo-sets (ItemRack uses some keys that start with "~")
        if type(setName) == "string"
           and setName:sub(1, 1) ~= "~"
           and type(setData) == "table"
           and type(setData.equip) == "table"
        then
            for _, itemstring in pairs(setData.equip) do
                local s = tostring(itemstring or "")
                local id = tonumber(s:match("^(%d+)"))
                if id and id > 0 and not map[id] then
                    map[id] = setName
                    itemRackSetNames[setName] = true
                end
            end
        end
    end
    return map
end

-- Public refresh hook so the resolver picks up new/edited ItemRack sets
-- without requiring a /reload. Call from a slash command or event hook.
function CT:RefreshItemRack()
    itemRackMap = buildItemRackMap()
end

-- Returns true if the given category name is the name of an ItemRack set.
-- Used by Bag.lua to keep set blocks anchored under the Equipment parent
-- container even when the set is the only Equipment-family block in view.
function CT:IsItemRackSetName(cat)
    if not cat then return false end
    if not itemRackMap then itemRackMap = buildItemRackMap() end
    return itemRackSetNames[cat] == true
end

-- Returns true if the given itemID is part of any ItemRack gear set.
-- Used by Bag.lua to exempt set gear from the Recent bucket: swapping
-- specs/sets bumps bag counts every time gear comes off the body, and
-- those items shouldn't churn through Recent on each swap.
function CT:IsItemRackTracked(itemID)
    if not itemID then return false end
    if not ItemRackUser then return false end
    if WB.db.options.useItemRack == false then return false end
    if not itemRackMap then itemRackMap = buildItemRackMap() end
    return itemRackMap[itemID] ~= nil
end

CT:RegisterSource("itemrack", {
    name = "ItemRack sets",
    GetCategoryFor = function(self, itemID, itemLink)
        if not itemID then return nil end
        if not itemRackMap then itemRackMap = buildItemRackMap() end
        return itemRackMap[itemID]
    end,
})

-- ============================================================
-- Main resolver: called by Bag.lua for every item slot
-- ============================================================
-- Resolution order:
--   1. customRules.byItemId (exact item override)
--   2. customRules.patterns (substring match on item name, in declared order)
--   3. Active CategorySource (auto / tsm / outfit / etc.)
--   4. "Misc" fallback
function CT:GetCategory(itemId, itemLink)
    if not itemId then return "Empty" end

    local rules = WB.db.customRules
    if rules then
        -- 1. Exact item override
        local byId = rules.byItemId
        if byId and byId[itemId] then return byId[itemId] end

        -- 2. Name pattern (substring, case-insensitive)
        local patterns = rules.patterns
        if patterns and itemLink then
            local name = itemLink:match("%[(.-)%]")
            if name then
                local lname = name:lower()
                for _, rule in ipairs(patterns) do
                    if rule.match and rule.category and lname:find(rule.match:lower(), 1, true) then
                        return rule.category
                    end
                end
            end
        end
    end

    -- 3. ItemRack sets (if ItemRack is loaded). Items in user-defined gear
    -- sets bucket under the set name; everything else falls through to auto.
    if ItemRackUser and self.sources["itemrack"] and WB.db.options.useItemRack ~= false then
        local cat = self.sources["itemrack"]:GetCategoryFor(itemId, itemLink)
        if cat then return cat end
    end

    -- 4. Active source
    local source = self.sources[self:ActiveSourceId()] or self.sources["auto"]
    if source then
        local cat = source:GetCategoryFor(itemId, itemLink)
        if cat then return cat end
    end

    -- 5. Fallback
    return "Misc"
end

-- Display ordering: a fixed roster so categories don't jiggle frame-to-frame.
-- Sources can extend or override via GetCategoryList(); for v0.1 we use the
-- auto list as the canonical order.
local DISPLAY_ORDER = {
    "Recent",         -- new items rebucketed here; cleared by Mark-all-seen
    "Equipment",
    "Totem",
    "Potion",
    "Elixir",
    "Flask",
    "Scroll",
    "Food",
    "Bandage",
    "Consumable",     -- generic consumables that don't match a subclass
    "Cloth",
    "Leather",
    "Metal & Stone",
    "Herb",
    "Elemental",
    "Enchanting",
    "Jewelcrafting",
    "Cooking",
    "Trade Goods",    -- generic trade goods
    "Mount",
    "Pet",
    "Quest",
    "Recipe",
    "Gem",
    "Container",
    "Projectile",
    "Quiver",
    "Key",
    "Junk",
    "Misc",
    "Free",
}

-- ============================================================
-- Parent-class grouping (visual containers in Bag.lua)
-- ============================================================
-- A category whose `PARENT_OF[cat]` points at a *different* parent name is
-- treated as a sub-category of that parent. When 2+ siblings of the same
-- parent are in view, the layout draws an outer border around them with
-- the parent name as a header.
--
-- Categories not in this map (Quest, Recipe, Gem, Container, Projectile,
-- Quiver, Key, Junk, Free) are their own parent — no wrapping container.
local PARENT_OF = {
    -- Equipment family
    ["Equipment"]      = "Equipment",
    ["Totem"]          = "Equipment",

    -- Consumable family
    ["Potion"]         = "Consumable",
    ["Elixir"]         = "Consumable",
    ["Flask"]          = "Consumable",
    ["Scroll"]         = "Consumable",
    ["Food"]           = "Consumable",
    ["Bandage"]        = "Consumable",
    ["Consumable"]     = "Consumable",

    -- Trade Goods family
    ["Cloth"]          = "Trade Goods",
    ["Leather"]        = "Trade Goods",
    ["Metal & Stone"]  = "Trade Goods",
    ["Herb"]           = "Trade Goods",
    ["Elemental"]      = "Trade Goods",
    ["Enchanting"]     = "Trade Goods",
    ["Jewelcrafting"]  = "Trade Goods",
    ["Cooking"]        = "Trade Goods",
    ["Trade Goods"]    = "Trade Goods",

    -- Misc family
    ["Mount"]          = "Misc",
    ["Pet"]            = "Misc",
    ["Misc"]           = "Misc",
}

function CT:GetParent(cat)
    if PARENT_OF[cat] then return PARENT_OF[cat] end
    -- ItemRack gear-set names route under the Equipment parent so the set
    -- shows up as a sub-block inside the EQUIPMENT container alongside the
    -- "Equipment" auto-cat sub-block (items not in any set).
    if itemRackSetNames[cat] then return "Equipment" end
    return cat
end

function CT:OrderedCategories()
    -- Always lead with "Recent" so items rebucketed there render at the top.
    local out, seen = { "Recent" }, { ["Recent"] = true }

    local source = self.sources[self:ActiveSourceId()]
    if source and source.GetCategoryList then
        local list = source:GetCategoryList()
        if type(list) == "table" and #list > 0 then
            for _, c in ipairs(list) do
                if not seen[c] then
                    out[#out + 1] = c
                    seen[c] = true
                end
            end
            for _, c in ipairs({ "Junk", "Misc", "Free" }) do
                if not seen[c] then out[#out + 1] = c end
            end
            return out
        end
    end
    -- Fallback: DISPLAY_ORDER (already starts with "Recent")
    return DISPLAY_ORDER
end
