# Changelog

## 0.1.15-alpha.1

- Zones: the fish of the selected zone unfold under it in the list (accordion, one zone at a time); clicking fish filters the spots on the map, several can be chosen and stay in colour
- Zone map: zoom with the mouse wheel (towards the cursor), pan with the left mouse button held; mask fades a little more
- Zone map: legend under the map removed, map larger (max. 330 px high)

## 0.1.14-alpha.1

- Fish page: main text and title in the same ink colour at full opacity
- Zone map: mask reaches 5 % beyond the map edge (softer fade)
- Journal: empty-page message 80 px higher than before
- Zone map: spot marker uses the fish glyph of the minimap tracking (atlas Professions_Tracking_Fish)

## 0.1.13-alpha.1

- Journal: empty right page message larger and centred
- Fish page: title in the ink colour of the zone titles, game text in light sepia (item type line keeps its colour)
- Zone page: title lower, counters further right; map fades out less; Blizzard fishing glyph as spot marker (own fish symbol as fallback)
- Zone page: legend as ink stamps (round, dark, slightly transparent); more than six fish scroll with the mouse wheel
- Journal: right page content 25 px lower (zone map max. height 265 px)

## 0.1.12-alpha.1

- Fix: skill bar tooltip showed nothing (helper defined too late)
- New option: slider for the double click speed
- Journal: page texts in printed look (dark brown ink, game colours darkened)
- Zone map larger (full book page width)
- Zone map: transparent soft edge, sepia colour; spots shown as fish symbols; larger painted legend icons
- Journal: portrait book icon slightly larger
- Journal: fish icon painted on the parchment (desaturated, sepia, half transparent, soft edge mask)
- Journal: page curl moved another 2 px left and 2 px up

## 0.1.11-alpha.1

- Skill bar: total and legend values coloured like their bar segments
- Skill bar: details hint in blue below the cast hint
- Journal: page curl moved 4 px left and 2 px up
- Journal: fish page rows wrap and no longer overlap
- Journal: portrait icon smaller
- New option: switch on Find Fish tracking automatically
- Journal: zone page with map (ink style), fishing spots as fish icons, tooltip, right click menu with TomTom waypoint and routes
- Minimap and compartment tooltips: click bindings in blue
- Minimap and compartment tooltips: cast click hint shown at the bottom

## 0.1.10-alpha.1
- Journal: junk catches have their own tab and no longer appear under Fish.
- Journal: fish page with a 96 px icon, the item's original game tooltip lines and our fishing data below it (headers with rule, values right-aligned).
- Journal: title in the addon colour, black disc behind the portrait, Book icon as portrait.

## 0.1.9-alpha.1
- Minimap button tooltip: the click hints at the bottom start with the blue info icon.
- Fishing tooltip: the cast shortcut hint (with the info icon) is the last line.

## 0.1.8-alpha.1
- Journal: own tabs with 48 px icons (the Blizzard tab templates were too small for them).
- Journal: smaller page-curl texture, anchored in the corner of the right page.
- Fishing tooltip: segmented skill bar (skill, lure, equipment, buffs, rest to maximum) with a legend shown always or only while a chosen key is held.
- Info icon in front of the cast shortcut is desaturated and tinted blue (real texture instead of inline markup).

## 0.1.7-alpha.1
- Journal: tabs show only icons (Fish, Zones, Equipment, Book); the name is a tooltip.
- Journal: fix the search hint text staying visible while typing.
- Journal: move the page selection 25 px to the left.
- Options: modifier key and mouse button are dropdowns (Retail dropdown button, classic dropdown menu as fallback).
- Addon compartment entry now comes from the TOC (coloured title, Icon_Bobber) instead of LibDBIcon.

## 0.1.6-alpha.1
- Journal: standard panel frame with title bar and portrait, search centred in the header strip, tabs below the book, one page per entry with page counter, arrows and the page-curl animation of the spell book.
- Use Blizzard's blue info icon (FriendsFrame\InformationIcon, 16 px) in front of the cast shortcut line.
- Show fishing skill, rank (where the client has one) and the totals of the character over all zones in the minimap button tooltip.

## 0.1.5-alpha.1
- Write debug lines to BugLab or an own chat window BobbersJournal_Debug (created once, only while Debug mode is on); raise a Lua error if neither works.
- Add fishing data to item tooltips (where, how often, coordinates, average quantity); fish rows in the journal show the item tooltip.
- Put Blizzard's info icon in front of the cast shortcut line in the Fishing tooltip.

## 0.1.4-alpha.1
- Tooltip and bobber display: headers get a rule in the header colour to their right, the content below is indented.
- Show values of the bobber display in a right-aligned column.
- Leave one empty line above the addon section in the Fishing tooltip.

## 0.1.3-alpha.1
- Colour the category name and add the Bobber icon in the options list; use the stacked logo (128 px) on the overview page.
- Show failed and aborted casts in the zone figures (tooltip and bobber display).
- Add Debug mode option with "Delete all data" (confirmation) in the Developer section.
- Add tooltip header with icon and rule (as in Binds).
- Record junk catches always; list them in the tooltip under "Clean the waters" only if enabled (off by default).
- Use Icon_Bobber as addon list icon.

## 0.1.2-alpha.1
- Add addon category Professions to the TOC.
- Rebuild the options pages in the style of Binds (scrolling page, sections with rule, descriptions, switch for the grey texts).
- Place the bobber display in Blizzard Edit Mode (options window closes, Edit Mode opens); plain drag mode with Done button where no Edit Mode exists.
- Fix casts counted twice on Retail (duplicate cast event settled the open cast as a miss).

## 0.1.1-alpha.2
- Repo ZIP now has the top folder BobbersJournal/ with addon, documentation and repo files.

## 0.1.1-alpha.1
- Add X-Website and X-Curse-Project-ID to the TOC.
- Move Libs.xml into Libs/.

## 0.1.0-alpha.1
- Initial skeleton.
- Add fishing tracker, database (v1) and public API.
- Add double-click dispatcher and cast-by-double-click (off by default).
- Add journal window skeleton (tabs, search, bookmarks, /bob).
- Add options page, key binding for casting, fishing spell tooltip and bobber display with drag mode.
- Record full cast log, lure statistics, subzones, hours and fishing time.
- Record fishing buffs with source (item, quest, spell) via aura events.
- Add icon set (TGA) and use it in journal, options, bobber display and addon list.
- Add minimap button and addon compartment entry.
- Embed LibStub, CallbackHandler, LibDataBroker and LibDBIcon; minimap icon and compartment now run through LibDBIcon.
