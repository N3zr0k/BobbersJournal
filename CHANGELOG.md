# Changelog

## 0.2.0-beta.1
- First beta: no code changes against 0.1.112-alpha.1, only the version label (alpha to beta)

## 0.1.112-alpha.1
- Maps and lists: the symbol of a vendor is the vendor purse of the game instead of the ore-like reagent icon

## 0.1.111-alpha.1
- Vendor page of the journal: the vendor type ("Fishing vendor" / "Fishing teacher") is a heading like "Sold", same colour and indent, no blank line between name and title

## 0.1.110-alpha.1
- Vendor page of the journal: "Fishing vendor" / "Fishing teacher" in the addon's turquoise
- Vendor page of the journal: the title of the NPC stands in brackets directly under the name, vendor or teacher and the place follow after a gap
- Internal: the price chart reads the price series once instead of twice, the vendor goods are sorted with names looked up once, the page turn sound lives in one helper

## 0.1.109-alpha.1
- Journal: whenever the right page has more than one page (fish: Info, Map, Sales; lures and vendors: two pages) the pages also have tabs below the right page, in addition to the page arrows
- Sales page of the journal: under the auction price stands the date of the last scan (Auctionator tells it; other price addons do not, then the day this price first showed up here is shown, labelled so)

## 0.1.108-alpha.1
- Vendor page of the journal: a recipe that is in the bags, the bank or the warband bank (not learned yet) shows only the green check; its tooltip says where it is
- Vendor page of the journal: the heading "Sold" has no colon and the line runs through the middle of the text
- Vendor page of the journal: the title of the NPC stands directly under the name; coordinates are written in brackets and in the same colour as elsewhere in the addon (also in the map pin tooltip)

## 0.1.107-alpha.1
- Vendor page of the journal: the tooltip of a good shows no extra requirement lines any more (the item tooltip names them itself)

## 0.1.106-alpha.1
- Vendor page of the journal: the tooltip of a good no longer repeats "Already known" (the item tooltip says it)
- Vendor page of the journal: a recipe already learned has a green background (the red "Already known" tooltip line no longer counts as a shortcoming, also for vendors saved before)

## 0.1.105-alpha.1
- Journal: the line "Fish species caught" stands level with the paging buttons
- Vendors and teachers can be bookmarked (they appear in the Bookmarks tab) and have a button for a TomTom route when TomTom is installed
- Vendor page of the journal: the picture of the NPC stands higher (head level with the title); the goods have the heading "Sold:" and are listed like in the vendor window, icon with name and price beside it, in two columns

## 0.1.104-alpha.1
- Journal rebuilt: the left page lists and turns (fish, junk, lures, zones, vendors and teachers), the right page has its own pages
  - Fish: Info, Map (the zone where the fish was caught most, only its spots) and Sales (vendor and auction price, stock and its value, recipes, price chart)
  - Lures: Info and Sales (prices, stock, vendors that sell it)
  - Zones: only the map, with the bookmark button
  - Vendors and teachers: name, place, picture of the NPC and what it sells as icons with tooltips (red = cannot be bought yet, green = recipe already learned), second page the map
- Price history: the auction price from a price addon (Auctionator, TSM, Auctioneer) is noted once a day range (lowest, highest, last) at login, after an auction house visit and when a fish page is opened; the sales page shows one year as a chart with minimum, maximum, average, change in 30 days and the best weekday to sell. Starts empty, no history is read from other addons

## 0.1.103-alpha.1
- Vendors: the oversized bobber is also found when the vendor sells it under another item ID than the toy (item 136377, or the same name as the toy); with debug on, every merchant item that is not recognised is logged with ID, class and name
- Fixed (vendors): price and requirement reading can no longer stop the recipe detection; the 30 second pause between scans of one vendor is gone
- Journal and diary: the fish pages show what the quantity owned is worth to a vendor and, with a price addon, at the auction house (bank and warband bank count once they were read)

## 0.1.102-alpha.1
- Vendors: the price (with extra costs such as items or currency), stack size and limited stock of every saved fishing item are recorded and shown in the journal and the map pins; items the character cannot buy yet show what is missing (red tooltip lines) under "Requirements"
- Vendors: a vendor that repairs gear is marked
- Teachers: the fishing services of the trainer window are saved with skill rank, character level and cost and shown as "Teaches"
- Fixed (Retail diary): a fish never caught turned white under the mouse; it stays grey now

## 0.1.101-alpha.1
- Fixed (Retail diary): a Blizzard error in the recipe page ("currentRecipeInfo" is nil) after the filter and group change of 0.1.100; our fish entries are "learned" dummy recipes again, the grey colour is set on the list buttons and "Not caught yet" is a normal category sorted last
- Stock on the fish pages: as long as the bank was not opened in this login, the bank line says "not read yet, please visit the bank" instead of a possibly wrong number

## 0.1.100-alpha.1
- Diary (Retail): the filter menu of the list works for our fish ("Show learned" = caught, "Show unlearned" = not caught yet, "Have materials" = in bags or bank); fish never caught stand under their own heading "Not caught yet"
- Diary (Retail): fish never caught are grey in the list of the fishing journal, the caught ones white (untested in the game)
- Diary (Retail): the fish pages show the same as the journal: stock in bags and bank, fish and value per hour of the character

## 0.1.99-alpha.1
- Journal, fish page: how many of the fish are in the bags and in the bank (and the warband bank on Retail)
- Journal, fish page: fish per hour and what they are worth per hour (vendor, auction house with a price addon) over all sessions of the character (only the total, no session value)
- Bobber display: the third column shows the fish per hour as well ("Ø 12.3/h" and the gold per hour behind it); it shows the rate even when no price is known; the display is 50 px wider again

## 0.1.98-alpha.1
- Fish tooltip: the auction value only appears when Auctionator, TradeSkillMaster or Auctioneer is installed (the option text names them). The per-hour values carry the average sign and are the session average only (over all catches since the login), no totals. The session is saved, so a /reload keeps it; only a new login starts a new one
- Bobber display: a third column with the value per hour (average sign) behind every fish of the zone list, from the session average and the auction house price (price addon) or else the vendor price; the display gets wider and the columns stay aligned
- Colour escapes no longer pass fractions to string.format

## 0.1.97-alpha.1
- Fish tooltip: fish caught per hour and what they are worth per hour, for the character's totals and for this session; sold to a vendor (sell price of the game) and at the auction house (price from Auctionator, TradeSkillMaster or Auctioneer when one is installed). Option "Show income per hour on fish". Untested in the game

## 0.1.96-alpha.1
- Database format 2 (older saved data is not read; tools/migrate_v1_to_v2.py converts a saved file once): one container per client (BobbersJournal_DB.retail / .forever), so no entry needs a flavor flag
- Fishing spots are saved like GatherMate2 does: points[map][position code] = { fish = catches }, positions rounded to 0.5 % of the map; the sub zone is no longer saved per spot
- Sub zones are saved by a number per zone, the names live in the language store (text), which a language change clears completely
- Recipes with a fish ingredient: recipes[recipeID].fish, one entry per recipe; names in the language store
- Item texts (name, tooltip, catch rank) moved into the language store; item class and icon stay language free
- Fixed: two more places lost the second and third return value (item tooltip colours in the journal; the equipment bonus when checking the skill a lure needs)
- Fixed: the vendor and teacher pins on the minimap failed with an error (the map height was lost, same cause as before with the position)

## 0.1.95-alpha.1
- /bob probe also prints the sub zone text and, where the client has them, the IDs and names of the explored areas at the player position (to check whether an area ID can replace the sub zone name)
- Fishing skill: clients without the profession list (GetProfessions) read the skill from the skill list (GetSkillLineInfo), like Glimpse Professions did; /bob probe no longer fails when the skill is unknown
- Recipe items are marked as learned by their ID: the tooltip of the item (by ID) says "Already known" (the client's own text, any language); no name matching
- /bob export also lists the data behind each tooltip line (to find the ID of the item a recipe item makes)
- Recipe items list: every Classic recipe item now names the fish it needs (read from the item tooltips of the export)

## 0.1.94-alpha.1
- /bob export also lists the spell an item triggers (maybe the recipe a recipe item teaches)
- Vendor recipes get the green check when the item name without its prefix ("Recipe: X") is the name of a learned recipe (the recipe items carry no ingredients in their tooltip); no tooltip scan

## 0.1.93-alpha.1
- 20 Classic recipe items with fish added to the list of recipe items (they count as fishing recipes at vendors by ID)
- New developer tool /bob export: lists name, spell and tooltip of any item IDs (or of all saved vendor recipes) as text to copy, for building the static recipe database
- Fixed: fishing poles at vendors were listed under "Other" on Retail (poles are profession tools there); they are recognised as poles now
- Vendors: the scan only looks at item IDs (fishing poles, lures, fish, recipe classes and the new list of recipe items, Core/Helper/RecipeItems.lua); the tooltip scan of every item is gone, so a vendor visit is fast. Learned recipes are matched to vendor recipes by ID

## 0.1.92-alpha.1
- Recipes: a learned recipe with a fish ingredient (profession window, or newly learned) is saved once and marked as learned for the character; a vendor recipe gets the green check when its tooltip lists all ingredients of a learned recipe, also when no vendor has been seen before
- Vendors and teachers: a new visit finds wrong entries (vendor without fishing items, teacher without fishing offers, items that no longer count) and asks first whether to remove them; declined once means not asked again until the next login
- Vendors: other items count as fishing items only when their tooltip names the skill in full (no stems, the item's own name is ignored); the debug line shows the matching tooltip line

## 0.1.91-alpha.1
- Vendors: every recipe whose ingredients (vendor tooltip) name one of the known fish is saved as a fishing recipe, not only cooking and fishing recipes

## 0.1.90-alpha.1
- Vendors: recipes the character already knows ("Already known" in the vendor tooltip) are saved as learned and shown with a green check in the vendor lists of the journal and the map pins
- Vendors: the Reusable Oversized Bobber is recognised and saved as its own category "Oversized bobber" (vendor tooltips on the map and in the journal); vendors saved earlier need a new visit

## 0.1.89-alpha.1
- Fishing teachers are recognised by every known name of the skill and its stem (case does not matter), in the NPC title and the trainer window; matches only count at the start of a word, the NPC's own name is ignored, and a conversation alone no longer saves a teacher

## 0.1.88-alpha.1
- Fish and zone pages of the fishing journal: narrower text and a statistics panel next to it (look of the crafting details, heading Bobber's Journal) with catches, zones and account values
- Fixed: vendor and teacher pins on the minimap never appeared (the player position lost its second value); the debug line no longer repeats with every step
- Code cleanup: one central colour helper (Colors.Wrap, Colors.Escape) instead of eight copies, removed unused pieces (old single bonus piece of the skill bar, two unused locals)

## 0.1.87-alpha.1
- Fixed: our scroll area follows the anchor the game gives its description on every page (the text started over the title)

## 0.1.86-alpha.1
- Fixed: the page of the game stood still while scrolling because the layout of the game anchored its description to the form again; it is tied to our content now

## 0.1.85-alpha.1
- The skill bar of the screen shows lure, equipment and every buff as own pieces in their colours, separated by a 1 px gap that is part of the calculation
- Mouse over the skill bar of the bobber display shows the split of the value, too (shared with the skill bar of the screen)

## 0.1.84-alpha.1
- Fixed: the length of our scroll content now counts the text of the game itself and is measured again after the layout, so the scrollbar appears for long pages
- Mouse over the skill bar: higher strata, protected build, debug line

## 0.1.83-alpha.1
- Mouse over the skill bar shows the split (skill line, lure, buffs, equipment) in the colours of the bar and the total score
- Fixed: the equipment bonus was missing from the bars when a buff gave more than the modifier of the game
- Catch rank column: the width of a space is measured correctly now

## 0.1.82-alpha.1
- Fixed: the border panel of the profession window swallowed the clicks on our scrollbar (own strata); debug lines for wheel and thumb

## 0.1.81-alpha.1
- Pages of the game that have a scroll frame of their own: our block is added into that frame, so one scrollbar scrolls everything
- Catch ranks in the fish lists stand in one column like a table
- Scrolling of our block on the pages of the game is done by hand (clipped frame and moved content) instead of a ScrollFrame
- Debug line "recipes: ..." with a sample description text of a fish page, to check the catch rank reading

## 0.1.80-alpha.1
- Retail: the catch rank of Midnight fish is read from the fish page of the fishing journal and shown behind the fish name in the lists of the bobber display and the tooltip; it is also read in the background when the profession window lists its recipes
- The oversized bobber section of the tooltips is hidden when the option is off or neither toy nor item is available
- Skill bar segments in the tooltip and bobber display are separated by a 1 px gap that is part of the bar calculation (one shared function)
- Skill bar and bobber display show every bonus in the colour of its segment (equipment, lure, buffs)

## 0.1.79-alpha.1
- New option: hide the lists of catches and junk in the bobber display
- Fixed: the oversized bobber toy was only used after the first cast because its name was not loaded yet (requested at login)
- Fixed: scrollbar of our block on the pages of the game did not move the page (own scrollbar and mouse wheel)

## 0.1.78-alpha.1
- New central number display (Core/Helper/Format.lua): counts and percentages look the same in tooltips, diary and journal
- Tooltips show counts in white and percentages in Bobber beige, in the order value (percent)
- Fish pages of the diary: section "Caught:" with the zones and "Account values:" with every character in its class colour

## 0.1.77-alpha.1
- Rates on the zone pages of the game add up the casts and catches of all characters, like the fish data

## 0.1.76-alpha.1
- Fixed: casts and catches of a zone page counted all zones together when a sub map had no data
- Catches are checked before they count as fish: crafting materials need the word for fish in their tooltip (all client languages), other materials and consumables are listed under junk as "Crafting materials & others"

## 0.1.75-alpha.1
- Our list pages (fish and zones) show our data under the same heading with the bobber icon as the pages of the game, so both look alike
- Fishing journal: our block on the pages of the game has its own text fields below the game's text; on zone pages the coordinates stand right aligned like on our own pages
- Zone pages (fishing journal and our list): fish, chances, casts and catches of the sub maps below a zone are added up with the zone
- Zone pages: a tooltip over the fish name and the TomTom coordinates shows the spot and the hints for the left and right click
- Fishing journal: the heading of our block shows the small bobber icon of the minimap button

## 0.1.74-alpha.1
- Fishing journal: the description keeps its full height when our block is added (it was cut off at the height of the game's own text)

## 0.1.73-alpha.1
- Fishing journal: the scroll frame with our block lies above the frames of the form, so the text is visible

## 0.1.72-alpha.1
- Fishing journal: zone pages are recognised by the zone maps of the game too (not only zones with our data) and show "Rates: Not caught yet."

## 0.1.71-alpha.1
- Fishing journal: our block is also added after the page was built (second trigger), only once; /bob probe shows the state of the journal hook, what the open page was matched to and our zones with data

## 0.1.70-alpha.1
- Skill bar: new option "Hide the bar at the maximum skill" (shown with the bar option); the tooltip keeps the values
- Journal tab "Vendors": the right page shows the map of the zone with its vendors and teachers; a right click on a symbol offers the TomTom waypoint
- Journal tab "Vendors": vendors and teachers are listed by region and zone as a folding tree like the zones, with the NPCs below their zone
- Map symbols: the aqua ring is a round 3 px line around the icon (symbols a little larger); the minimap takes the map size from C_Map.GetMapWorldSize and logs in debug mode why it shows nothing

## 0.1.69-alpha.1
- Fishing journal: pages of fish we have no data for yet are recognised by name too and show "Rates: Not caught yet."
- Journal tab "Vendors": lists the saved fishing vendors and teachers with place, coordinates, title and what they sell

## 0.1.68-alpha.1
- Teachers: profession trainers whose list is empty are recognised by the profession shown above the list (the "step" of the trainer window)

## 0.1.67-alpha.1
- Saved vendors and teachers now keep everything the client tells about the NPC: tooltip lines, title, creature type, level, faction, place, conversation options and trainer services

## 0.1.66-alpha.1
- Teachers are recognised by the title of the NPC and by conversation options too (the trainer list of a fishing teacher is empty in the game); the fishing journal logs what it sees in debug mode

## 0.1.65-alpha.1
- Fishing journal: our information below the game's text now scrolls when the page gets long
- Fishing journal: the zone pages of the game also show our data (fish caught there with the best spot and a TomTom click, casts and catches)

## 0.1.64-alpha.1
- Teachers are now saved for characters that have not learned fishing yet (the skill name came only from the learned profession); the trainer list is read again when it arrives late; debug lines show what the scans see

## 0.1.63-alpha.1
- Vendors/teachers: a chat line confirms when a new fishing vendor or teacher was saved; /bob probe shows how many are saved and whether the map provider is attached

## 0.1.62-alpha.1
- New option "Show vendors and teachers on the maps": the saved fishing teachers and vendors appear on the world map and the minimap with the game's own icons in an aqua ring; the tooltip lists place and offers by category
- Shipped lists moved into separate files per client: Modules/Data/Retail and Modules/Data/Forever (Fishs.lua, Vendors.lua, Recipes.lua); vendors and recipes of these files are merged with the saved data
- New module Recipes: when a profession window opens, the recipes that use a fish are read and their recipe IDs are saved on the fish; the fish pages of the fishing journal and the journal list them under "Used in recipes:"
- New module Vendors: merchants selling fishing items (poles, lures, fishing and cooking recipes, fish, items that mention the fishing skill) and fishing teachers are saved in the database with NPC ID, name, map and coordinates
- Zone page: with TomTom loaded a click on a fish name or its coordinates sets a waypoint at the best spot, a right click opens the menu (waypoint, route to all spots, route to the best 5 spots)
- Headings: information from the game keeps the green heading, our own data ("Rates:", "Fish in this zone:", "Zones with catches:") uses the aqua of the addon
- Zone page: the coordinates are yellow and right-aligned (also without TomTom), the percentages use the parchment colour

## 0.1.61-alpha.1
- Journal: the tooltip of each fish is saved once in the database under its item ID (lines, colours, icon) and read from there; no more empty pages when clicking quickly, and a page that arrives late is redrawn
- Zone page: the coordinates are yellow

## 0.1.60-alpha.1
- Journal zone pages list every caught fish with the spot where most were caught; clicking the coordinates starts a TomTom route
- Journal list: new category "Zones" (zones of the open expansion where we have catches) between favourites and the fish; a click shows the zone page (fish caught there, casts and catches); zones can be favourites too
- Fish page: sections in the order of the game's pages (general lines, description, special use, zones, rates)
- Fish pages: our statistics stand under the heading "Rates:" (caught totals and per zone); the zone name list is only added on our own pages, the game's pages have their own
- Fish page: the "Use:" line of the item becomes the green heading "Special use:" with the text in white below
- German: the zone list heading of the fish pages reads "Verbreitungsgebiete:" like the original
- Fish page: grey ring (quality 0) like the original fish pages; icon 3 px smaller

## 0.1.59-alpha.1
- Fish page: the icon and its ring are set up with Blizzard's own output icon function (ring by item quality, as in Midnight); icon at 28/-28, star right behind the title

## 0.1.58-alpha.1
- Fish page: hovering the fish icon shows the original item tooltip
- Fish page: positions and sizes taken from Blizzard's recipe form (output icon at 28/-33, title beside it, description 460 wide)
- Fish page: the schematic form is no longer hidden, so its frame (NineSlice) and background stay
- Fish page: the favourite star sits right behind the name

## 0.1.57-alpha.1
- Fish list in the journal: favourites (the star on the fish page = bookmark) appear as the category "Favourites" at the top of the list and update at once
- Fish page on the right: round item icon with quality ring, gold title with a star (bookmark of the fish), smaller body text, green heading for the zone list
- Fish list in the journal: the fish page on the right stays when Blizzard rebuilds the list (item data arriving); it only goes away for a real recipe or another expansion page

## 0.1.56-alpha.1
- Fish list in the journal: the tooltip page on the right scrolls with the game's own scroll frame when the text is long
- Fish list in the journal: item data is loaded before the list is filled (quality decides the category); a click on a fish shows its tooltip on the right in the style of a recipe page, with our catch data
- Fish list in the journal: the "no results" text of the list is hidden once our fish are inserted

## 0.1.55-alpha.1
- Fish list in the journal: every empty fishing page lists the fish of its own expansion (Classic page: Classic fish only; pages Blizzard fills itself are left alone)
- Fish list in the journal: inserted one frame after the list is set, so Blizzard no longer selects one of our entries as a recipe (fixes the GetRecipeSchematic error)

## 0.1.54-alpha.1
- Retail: the empty Classic Fishing page of the game's fishing journal lists our fish (common / uncommon fish categories, alphabetical); option in the Minimap section
- Retail: the fish pages of the game's fishing journal show your catches and the zones with catch chance below the description (option in the Minimap section)

## 0.1.53-alpha.1
- Skill lines: known IDs for Dragon Isles, Khaz Algar and Midnight added (used when the client has not filled the lines yet)
- Fish tracking (Find Fish) is switched on by default; a saved choice is kept
- Skill bar: the bonus is a blue segment behind the filled part (at least 2 px wide)

## 0.1.52-alpha.1
- Removed the developer option "Measure bite signals": the measurement showed that a bite cannot be detected
- Skill bar: own rounded mask instead of the experience bar flipbook mask, which hid the fill; ends stay round, bar visible again

## 0.1.51-alpha.1
- Skill bar: fill, shine and bonus are cut with the experience bar mask (rounded ends, no overhang on the left); bonus drawn additive so it is visible
- Developer option "Measure bite signals": prints the game signals around a bite with timestamps, to find out whether a bite highlight is possible

## 0.1.50-alpha.1
- Bobber display: switching the option shows or hides the display at once (no reload needed)
- Oversized bobber: used as the toy (Retail) when collected and usable, otherwise as the item from the bags (Retail and Forever); buff and cooldown in the tooltip work for both
- Skill bar: much brighter fill in the main colour, text 2 px higher
- Options: "Switch on fish tracking automatically" moved from Casting to the Minimap section
- Journal: the grey of poor items is darker on the parchment

## 0.1.49-alpha.1

- Journal: each tab remembers its last selected entry when you switch tabs
- Journal zone list: sub zones use the same font size as the zones, the fish below stay smaller

## 0.1.48-alpha.1

- Journal zone list: all sub items (sub zones and fish) in the same font size, dot before sub zones removed
- Journal: dark outline of the item names removed again
- Minimap button: icon a little larger and 4 px higher


## 0.1.47-alpha.1

- Lure inventory: filled once after login/reload, read again at the first cast or lure of the session (also forgets wrong "no lure" verdicts from unloaded tooltips)
- Journal: item names in quality colours get a dark outline (readable on the parchment)
- Journal zone list: regions and zones with sub zones can be opened and closed (saved), region headers with a hairline, sub zones with a branch dot
- Journal zone list: the search works as zone filter (a zone or region match shows the whole zone with its sub zones)


## 0.1.46-alpha.1

- Without the bobber display the fishing figures appear in the tooltip of the bobber while fishing

## 0.1.45-alpha.1

- Cleanup: one shared menu helper (BJ.Menu: choice dropdown and popup menu for Retail and Forever) used by the options, the lure list and the journal filter; one shared atlas check (BJ.HasAtlas), tooltip item colours use the database helper, unused code removed
- Sub zone highlight uses the main colour of the addon

## 0.1.44-alpha.1

- Sub zone highlight glows like the fish spots (additive) and fades out at the rim

## 0.1.43-alpha.1

- Performance: skill bar redraws once per burst of aura/inventory events, the journal redraws once per burst of item data and bag events, the fish statistic reuses the list instead of building it twice
- Sub zone highlight is colour BB843A with 70 % transparency

## 0.1.42-alpha.1

- Fix: Lua error in the journal list caused by the quality colours (0.1.41-alpha.1)
- Sub zone highlight uses the shaped exploration overlays of the game's map instead of a rectangular block
- Journal: filter dropdown moved to the left page
- Sub zone highlight is bluish and transparent

## 0.1.41-alpha.1

- Journal: fish tab shows "Fish species caught: x/y"
- Item names (fish, junk, lures) are shown in the colour of their item quality in the journal and the map tooltip; quality is saved in the database
- Double click: debug log names the frame under the mouse at the second click
- Sub zone highlight uses the game's map exploration data (whole explored area), catch glows only as fallback

## 0.1.40-alpha.1

- Journal: selecting a sub zone shows the zone map with the sub zone highlighted (spots and glow from its catches) and lists its fish like a zone; odd arrow symbol removed
- Spots remember the sub zones they were caught in
- Journal: filter dropdown next to the search box (show all / only collected)
- Skill bar rebuilt like the experience bar: StatusBar with the original fill atlas (only recoloured), original geometry, buff bonus as prediction bar with pip

## 0.1.39-alpha.1

- Statistics: aborted casts are counted only as aborted (no casts, catch rate, day, lure or fishing time)
- Skill bar: coloured bar moved 5 px left and 2 px up

## 0.1.38-alpha.1

- Skill bar: original frame graphic lies on top of the bar like the experience bar, own divisions removed, text prefixed with "Fishing:"
- Oversized bobber: buff detection also matches by name and icon, so an active buff is no longer shown as inactive

## 0.1.37-alpha.1

- Skill bar: divisions at 75, 150, 225 for a maximum of 300, otherwise every 25 points (both flavours)

## 0.1.36-alpha.1

- Lures are green: lure part of the skill bar legend, frame of lures in the bags and lure names in the journal

- Tooltip: the oversized bobber section sits at the bottom; opening the profession window no longer counts as choosing a skill line

- Skill bar: no dark base behind the bar background, it looks like the experience bar

## 0.1.35-alpha.1

- Skill bar and tooltip follow the fishing skill line picked by hand in the profession window until the zone changes

- Fishing skill lines: known skill line IDs are tried and the last values are remembered per character, so the zone skill also shows before the profession window was opened

- Skill bar: the whole original frame sits behind the bar (rim and rounded ends as on the experience bar), the bar covers its divisions

## 0.1.34-alpha.1

- Skill bar: divisions are thin light lines through the whole bar height like on the experience bar; Fishing lines are recognised by parent skill line and name too

## 0.1.33-alpha.1

- Fix: the oversized bobber toy is used by name (/usetoy needs the name, not the ID); without a loaded name /use item:ID

## 0.1.32-alpha.1

- /bob probe lists the fishing skill lines with names and IDs and the zone assignment; fallback source for the skill lines
- Skill bar takes its size from the original frame

## 0.1.31-alpha.1

- Skill bar: the divisions are made from a slice of the original frame graphic

- Sub zones are recorded with their fish and listed under their zone in the zone list (Elwynn Forest -> Mirror Lake) with their own page

- Skill bar: original frame of the experience bar; its own divisions are cut away (only the border pieces are shown)

- New: optional fishing skill bar in the style of the experience bar (addon colour, divisions every 10 points on Retail and every 75 on Forever, movable in Edit Mode, default above the experience bars)

- Bobber HUD: shows the skill bar of the zone (level and expansion/rank in the bar)

- Retail: fishing tooltip and bobber HUD show the oversized bobber toy with buff (active, time left) and cooldown

- Bobber HUD (detached tooltip): 50 px wider (330 instead of 280)

## 0.1.30-alpha.1

- Tooltip: minimum width from the widest left/right pair, so long names and percentages never overlap

- Retail tooltip: the skill bar shows the skill line of the zone (expansion of the zone, from the fish caught there), not the general one

- Tooltip: the skill bar is as wide as the tooltip

- Tooltip: the skill bar shows level and what is levelled (Retail: expansion of the skill line, Forever: rank such as Apprentice)

- Zone map: the best spot is centred left/right on opening; spots near an edge get up to 3x zoom for this; the map still cannot be moved beyond its edges

- Zone map: opens centred on the spot with the most catches (of the chosen fish) and follows the choice

## 0.1.29-alpha.1

- Names of items caught earlier are loaded and saved in the background 5 s after login; the fishing tooltip refreshes when a name arrives

- Item names are saved in the database (per client language) and used when the client has not loaded them yet; no more bare IDs in lists and tooltips

- Tooltip: the width is recalculated after our lines were added (long fish names overlapped the percentages)

## 0.1.28-alpha.1

- Retail: fishing poles of the profession tool slot (item class Profession) are recognised as poles; this was why lures were not applied

- Journal, zone map: transparency of the page picture and the map tiles is set with SetAlpha, so it also works with the mask textures

## 0.1.27-alpha.1

- Journal: page picture has alpha 0.6 and sits at y=-90 without the page offset

- Fix: skill requirement of lures is read correctly on clients with positional format strings (German "%1$s (%2$d)"); error "invalid capture index"

## 0.1.26-alpha.1

- Debug: toy tooltips (toy box) show the item ID

- Debug: tooltips of journal entries, tabs, favourite slot and map spots also show the IDs (item, enchant, zone, spot)

## 0.1.25-alpha.1

- Zone map: fish markers use the original yellow of the game icon, green on mouse over

- Zone map: all fish are chosen by default; with no fish chosen the map shows no spots

- Journal: lures in the bags that need a higher fishing skill get a red frame and a red name

- Auto lure: lures that demand a higher fishing skill than the character has are skipped (favourite and best lure)

## 0.1.24-alpha.1

- Journal: lure pages show the description text of the lure item

- Journal: the lure currently applied to the pole gets a gold frame in the list; favourite slot frame is bag grey

- Journal: lure favourite hint text is grey without shadow; favourite marker uses Crosshair_Fishing; fish page icon uses the given colour and position

- Journal: fish page icon and zone map are tinted with FF9B3E

- Retail: the pole is also found in the fishing tool slot (28); auto lure applies the lure to it and detects an existing lure there

## 0.1.23-alpha.1

- Journal: paging controls of the left page mirror the right page (70 px from the left edge, text to the right of the buttons)
- Auto lure on Retail: the lure is applied when its buff is not active (no pole in the main hand needed); debug messages say why a lure or the toy was skipped
- Options: favourite lure as a bag slot (drag a lure onto it, right click removes it, mouse over shows the tooltip) left click opens the list of the lures in the bags; the button to the journal is gone
- Journal: Lures settings are shown on the right page (the list stays on the left); the sub tabs hang below the window like the tabs of the Retail spell book (checked against the Retail UI code)
- Zone map: warmer brown tint so the map sits closer to the colour of the paper
- Journal: main text of the item page is darker (between light sepia and the title colour)
- Journal: the picture on the right page is twice as big and lies behind the text

## 0.1.22-alpha.1

- Journal: the picture on the right page is 50 % transparent (was 70 %)

## 0.1.21-alpha.1

- Fix: item names that were still loading showed as [ID] for good; the journal now waits for the item data and redraws, and asks again after 5 seconds if nothing came
- Zone map: dragging with the left mouse button also works at zoom 1 (the map is wider than the page) and stops when the button is released outside the map
- Journal: lures in the bags are listed first on the Lures overview, with stack count and the original bag slot look; the original frame is tinted by state (bags aqua, used gold, unseen grey); a fish hook marks the favourite lure
- Journal: Lures page with sub tabs "Overview" and "Settings"; settings (favourite lure, auto lure, best lure) stacked on the left page; the lure slot looks like a bag slot
- Journal: the Frameless logo is the window icon again

## 0.1.20-alpha.1

- Journal: new 64 px icon for the Junk tab
- Journal: own icon for the Lures tab
- Fix: the selected tab was drawn black (highlight frame needs additive blending)
- Journal: fish, junk and lure tabs: the left page turns through the list (14 per page), the right page turns only through the entries of the current left page

## 0.1.19-alpha.1

- Journal: own icon for the Junk tab
- Journal: tabs in the original spell book style (SkillLineTab frame art), stacked at the right edge of the book

## 0.1.18-alpha.1

- Data: fish of Wrath of the Lich King up to Midnight added (Retail)
- Data: fish blocks carry an expansion level; the journal shows grey fish only up to the expansion that is active on the client
- Data: fish list per expansion (Classic for both, Burning Crusade for Retail); the unsorted Retail test list was removed

## 0.1.17-alpha.1

- Data: Retail fish list (66 items from Wowhead) as grey "Rumour" entries until caught
- Data: first shipped fish list (9 Classic fish, shown grey as "Rumour" until caught)
- Journal: fish and lure lists as a grid of framed icons; entries not seen yet are grey (shipped catalogue and scanned lures)
- Lures: count how often each lure was applied and how long you fished with it (saved in the data base), shown on the lure page
- Journal: "Confirmed" / "Rumour" label on fish and lure pages (confirmed = seen in game)
- Lure scan: reads all lures out of the game (module LureScan), saved as lure catalogue
- Options: own page "Lures" with the favourite lure (shown only), a button to the journal page, "Apply lures automatically" (moved here) and "Best lure as fallback"
- Journal: auto lure on/off checkbox on the Lures page
- Journal: favourite lure field on the Lures page (drag a lure from the bags, right click removes); the auto lure uses the favourite from the bags first
- Options: own page "Bobber" (display and position); new Retail option to always use the toy Reusable Oversized Bobber when casting
- Fix: zone map functions (SetZone, zoom, pan) were missing, error in the zone list
- Fish page: text starts below a two-line title and ends 10 px earlier; fish picture with a round soft mask, lighter, 70 % transparent

## 0.1.16-alpha.1

- Zones: list clustered by region (e.g. Quel'Thalas > Eversong Woods, Silvermoon)
- Zone map fills the whole right book page, always zoomed so the height is filled, centred on the area with the most catches; rectangular edge fade
- Docs: header images (light for the README, dark for CurseForge) and a CurseForge description draft
- Auto lure: option "Apply lures automatically" (Casting); with the pole in hand and no lure the next click applies the best lure from the bags, the one after casts
- Lures remembered per enchant (lure item behind the pole enchant); skill bar tooltip names the lure and shows its time left
- Journal: new tab "Lures" with casts, catches, catch rate per lure, the rate without lure and the skill bonus
- Find Fish: after switching it on the minimap tracking menu is told to re-read its state (check mark now matches)

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
