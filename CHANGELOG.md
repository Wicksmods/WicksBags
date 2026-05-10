# Wick's Bags — Changelog

## 0.8.1 — 2026-05-10

- (edit this entry with the actual changes)

# Changelog

## 0.8.0 - 2026-05-10

Alt inventory viewer + window-position persistence.

- **Alt inventory viewer** — view any of your other characters' bags and bank side-by-side with your own. New title-bar button opens the AltViewer; pick a character from the dropdown to see what they've got. Snapshots capture each time you log in to that character and open your bags/bank, so you'll need to visit each alt once after this update before they show up.
- **Window positions persist across sessions and reloads** for bags, bank, and alt viewer. Previously the panels would reset to default on every `/reload` because of a saved-variable load-timing quirk on TBC Anniversary — saved data loads AFTER the addon's file-scope code runs, so any reference cached at file-scope was stale. Now the addon rebinds those references on ADDON_LOADED, when the saved file content is actually available.
- **Alt snapshots isolated to their own saved variable** (`WicksBagsAlts`). If anything in the snapshot data ever causes a corrupted file write, positions and options stay intact in `WicksBagsDB`.

## 0.7.2 - 2026-05-09

Bank tooltip fix.

- **Bank items now show their tooltip** when hovered in the main bank window. Bank bag slots already worked; the main bank container needed a different API path in TBC.

## 0.7.1 - 2026-05-09

Bag-fullness warning + keyring count fix.

- **FREE tile stays visible at 0** instead of disappearing when bags fill up. Border + count text turn red so you notice immediately.
- **Red warning strip** above the bottom bar when bags are full — discreet 2px line, only shows at 0 free.
- **Keyring no longer inflates the FREE count.** Empty keyring slots (up to 32 on a fully upgraded keyring) were being counted as free bag slots, making the FREE tile show 29+ open even when you had nothing draggable left. Keys still show under the **Key** category as before; only the FREE accounting is fixed.

## 0.7.0 - 2026-05-08

First public release. Bank panel, secure click for combat use, ItemRack-as-Equipment subclass, layout polish.

- **Bank panel** (`Wick's Bank`). Fires when you visit a banker. Categorized layout with the same brand chrome as the bag panel. Hides Blizzard's default BankFrame so you only see one window. Right-click a bank slot to shuttle items back to your bags. Bottom bar shows a Buy-slot button (with cost tooltip), individual bank-bag icons, and your gold.
- **Default bag UI suppressed at bank/vendor**. When a banker or merchant opens, Blizzard's auto-pop of the default bag windows is closed automatically — only Wick's Bags remains.
- **Bag opens automatically with bank**. Visiting a banker pops Wick's Bags too so you can drag items between. Bag panel returns to its prior state when you walk away.
- **Right-click items to use them**. Bag slots now use Blizzard's `ContainerFrameItemButtonTemplate` for click handling, so right-click works for potions, food, bandages, scrolls, mounts, equip-on-use, and container-open items — including in combat for combat consumables.
- **ItemRack sets as Equipment subclasses**. When ItemRack is loaded, gear sets show up as labeled sub-blocks inside the Equipment container alongside non-set gear. Items in any set are exempt from the Recent bucket so spec swaps don't churn.
- **Smart layout packing**. The masonry packer now tries multiple orderings (natural, tallest-first, widest-first, largest-area) per refresh and picks the one with the smallest total height for your current panel width. As you drag wider/narrower the layout reflows to whatever heuristic packs tightest.
- **Sub-block masonry inside containers**. Sub-categories (POTION, ELIXIR, SCROLL inside CONSUMABLE, etc.) now masonry-pack within their parent container instead of flowing in fixed rows. Short sub-blocks no longer leave a void waiting for a tall sibling.
- **Sub-cat headers center over their slot grid**. Block widths size to the wider of the slot row or the header text, and slot grids center horizontally below the header.
- **Filter on bag and bank bottom bars**. Right-click a bag/bank-bag icon to filter the panel to just that bag's items. Right-click empty space on the bottom bar to clear. Tooltip on each icon includes "click again to clear".
- **Recent container** with subtle muted-green accent ring so new items stand out without being loud. Mark-all-seen icon in the title bar; baseline persists across `/reload` per character via SavedVariablesPerCharacter.
- **Right-click bank slot** sends to first empty bag slot (uses Blizzard's `UseContainerItem`-while-bank-open shuttle).
- **Item-level overlay** on equipment slots, **cooldown spiral** on items, **slot-scale slider** in Options, **border-intensity** with Bright tier (lifts RGB toward white for a blown-out pop on quality colors).
- Keyring contents (`-2` container) included in the bag scan, so quest keys and dungeon keys show under the **Key** category.
- **Known limitation**: panel position and size don't currently round-trip across `/reload` on TBC Anniversary 2.5.5. Saved-variable serializer behaves differently than Classic/Retail for new keys; tracking for a future release. Position survives within a session (open/close), just resets on `/reload` or login.

## 0.6.0 - 2026-05-07

Title-bar polish and a bottom bar that owns the gold + PvP currencies.

- **Real icons** for the title-bar quick toggles. Junk uses a coin texture, Highlights uses a sparkle, Bag bar uses a bag, Mark-all-seen uses an eye. The Sort cycle keeps its `Q` / `A` / `#` letter (the letter conveys the active mode at a glance).
- **Mark-all-seen icon added** to the title bar — same effect as the Options panel button, one click instead of cog → button.
- **Title bar reflowed**: Search now sits immediately to the right of the title. Gold moved off the title bar entirely.
- **Bottom bar holds gold + TBC PvP currencies**. When the bag-bar toggle is on, the bottom strip shows: 5 bag icons (left), gold (middle), and currency tiles on the right for Honor Points, Arena Points, and the four Marks of Honor (Alterac Valley, Warsong Gulch, Arathi Basin, Eye of the Storm). Currency tiles hide themselves when their count is 0, so a non-PvP character sees a clean strip.
- **Bag bar now ON by default** since it carries the gold display.
- Hover any bag icon → tooltip with the bag's contents shown via Blizzard's `SetInventoryItem`. Hover any currency tile → its tooltip.

## 0.5.0 - 2026-05-07

Sorting, filtering, new-items-first, bag bar.

- **Sort modes** in Options. Pick Quality (high to low, default), Name (A-Z), or Quantity (high stack count first). Cycle through with the Sort button.
- **Min quality filter** in Options. Show all (default), Common+, Uncommon+, Rare+, or Epic+. Hides anything below the threshold across every category. Stacks with the existing "Show junk" toggle.
- **New items pulled to the front** of each category. Within a bucket, items that arrived since the last panel close sort first regardless of the active mode (quality/name/quantity is a tiebreaker after newness). Combined with the green pulse, new items are unmissable.
- **Toggleable bag bar** at the bottom of the panel. Off by default. When enabled, shows the backpack + 4 bag-slot icons with their textures, plus tooltips on hover. Visual-only in v0.5; click handlers (open bag, drag-to-swap) come later.
- Drop-on-Free-tile bug fixed (was returning early because the aggregate has no specific bag/slot). Free tile now routes drops to the first empty slot in your bags.
- Drag-resize feel improved: panel height locks during active drag instead of snapping with every reflow, and gains a 14px breathing buffer below the last row when not dragging.
- Common (white) and Poor (grey) quality borders dropped to ~50% alpha so Uncommon/Rare/Epic/Legendary borders pop.

## 0.4.0 - 2026-05-07

Resizable window, two-level masonry, parent-class containers, uniform group chrome.

- **Every category group now wraps in a bordered container** for visual uniformity. When a group has 2+ sub-categories (e.g. Consumable with Potion + Food + Bandage), the container header is the parent class name in centered fel green and each sub-block keeps its own small label. When a group has only 1 sub-block (Cloth alone, Quest, Free), the container header IS the cat name and the redundant inner label is suppressed.
- **Sub-cat labels** dropped to 8pt and clipped at block width via `SetWordWrap(false)`, so long names like JEWELCRAFTING no longer bleed into adjacent sub-blocks.
- **Quest-bound items take priority** over class-based categorization. Items with `bindType == 4` (the Blizzard "Quest Item" binding) bucket into Quest regardless of their item class. Fixes the case where a Demonic Stone (class Consumable) shows up under Consumables instead of Quest.
- **Two-level masonry layout.** Sub-blocks pack horizontally within each group AND groups themselves pack horizontally across rows. Small groups can sit side-by-side instead of each taking a full row.
- **Resizable panel.** Drag the BOTTOMRIGHT L-bracket. Width persists across sessions; height auto-fits to the packed content. Live reflow during drag (throttled to ~20Hz).
- **Auto-fit width logic removed** in favor of user-controlled width — the panel respects whatever you set it to.

## 0.3.0 - 2026-05-07

Granular auto-categories, custom-rules engine foundation, header polish.

- **Granular auto-categories.** The auto categorizer now uses both `classID` and `subClassID` from `GetItemInfoInstant`. Consumables split into Potion / Elixir / Flask / Scroll / Food / Bandage / Consumable. Trade Goods split into Cloth / Leather / Metal & Stone / Herb / Elemental / Enchanting / Jewelcrafting / Cooking / Trade Goods. No user config needed.
- **Custom rules engine (saved-variable editable, no UI yet).** Two override paths added at the top of the resolver chain:
  - `WicksBagsDB.customRules.byItemId[itemID] = "My Category"` — exact item overrides.
  - `WicksBagsDB.customRules.patterns = { { match = "Mageweave", category = "Mageweave Set" } }` — name substring matches, evaluated in order.
  - Both are case-insensitive on the name match. UI for managing these arrives in v0.4.
- **Header reverted to full-size fonts** (title 13pt, gold 11pt, search 110px, close/cog 20px). `MIN_PANEL_W` raised to 400 to fit. With the granular categories there are usually enough blocks to fill the panel anyway.

## 0.2.0 - 2026-05-07

Item interaction, new-item highlights, options panel, masonry layout, visual polish.

- **Drag** items between slots (out of combat). Pick up from any slot, drop onto another.
- **Right-click** uses the item in that exact slot (vs left-click which uses any instance of the itemID).
- **New-item highlighting**: items that arrived since the last time you closed the panel pulse with a fel-green glow. Closing the panel marks everything as seen. Toggle via Options. "Mark all items seen" button in Options for manual reset.
- **Options panel** opened via a cog icon in the header. Toggles for: show junk, highlight new items, show gold, show search box.
- **Masonry layout**: small categories pack horizontally instead of each category taking a full row. Each category sizes to its contents up to 5 columns wide; categories flow left-to-right and wrap to the next row when out of width. The panel auto-fits its height to the packed content.
- **Free slots condensed**: empty bag slots collapse into a single "Free" tile at the end of the layout with a count overlay (e.g. `47` if you have 47 empty slots), so you see free space at a glance without 47 visually-noisy empty squares.
- **Visual fixes**: removed a stray full-cover overlay that was dimming every item icon. Close-X glyph now renders correctly (Lua 5.1 escape syntax). Section dividers removed and inter-category spacing tightened.

## 0.1.0 - 2026-05-07

Initial scaffold. MVP feature set.

- Single window replacing the bag clutter view. Auto-categorizes inventory by item type into Equipment, Consumable, Trade Goods, Quest, Recipe, Gem, Container, Projectile, Quiver, Key, Junk, Misc.
- Quality-color borders per slot.
- Live search across all bags.
- Gold display in the header.
- Cooldown spirals on items with active cooldowns (potions, trinkets).
- Use-on-click via secure action template (left-click).
- Slash commands: `/wb`, `/wb show`, `/wb hide`, `/wb reset`.
- Keybinding: Toggle panel via `Esc to Key Bindings to AddOns to Wick's Bags`.
- Pluggable category-source architecture: external sources (TSM, future outfit addon, etc.) can register at load time and be swapped from options.

Roadmap:
- v0.2: TSM groups as a category source. Custom user-defined rules. Drag and right-click container actions. Bag-bar strip. New-item highlighting. Currency tracking.
- v0.3: Outfit addon integration. Sort modes (alpha, type, count). Hide-default-bags option.
