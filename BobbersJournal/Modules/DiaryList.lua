local _, ns = ...
local BJ, Flavor, Skill = ns.BJ, ns.Flavor, ns.Skill
local L = BJ.L
-- Retail only: the pages of the game's fishing journal (profession window) that Blizzard leaves empty (all but Midnight). When one is opened,
-- two categories (common / uncommon fish) with the fish of that expansion (our catalogue) are inserted into the list's data provider, built like
-- Blizzard's own nodes (see Professions.GenerateCraftingDataProvider). Hooks only (hooksecurefunc / callbacks).
-- Our entries are no real recipes: their click does nothing, so the Blizzard recipe page is never asked about them.
-- Inserted one frame after the list was set, because Blizzard selects the first recipe at once. Not tested in the game.
local M = BJ:RegisterModule("DiaryList")

local GROUP_FAVORITE, GROUP_LEARNED = 1, 2 -- Blizzard: Group = Favorite 1, Learned 2, UnlearnedDivider 3, Unlearned 4
local hooked

local function frame() return ProfessionsFrame and ProfessionsFrame.CraftingPage end

--- Expansion level (0 Classic, 1 Burning Crusade ...) of the fishing skill line that is open, nil for any other page.
local function openLevel()
  local page = frame()
  local info = page and page.professionInfo
  if type(info) ~= "table" then return nil end
  for index, id in ipairs(Skill.LINE_IDS) do
    if id == info.professionID then return index - 1 end
  end
end

-- fallback for the quality: the colour of the first tooltip line (the item name) is the quality colour
local function firstLineQuality(id)
  local lines = BJ.DB:ItemTooltip(id)
  local c = lines and lines[1]
  if not c then return nil end
  for q = 0, 8 do
    local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if qc and math.abs(qc.r - c.r) < 0.02 and math.abs(qc.g - c.g) < 0.02 and math.abs(qc.b - c.b) < 0.02 then return q end
  end
end

local function fishIDs(level)
  local ids = {}
  for id, mask in pairs(ns.Catalog.fish) do
    if ns.Catalog.fishExp[id] == level and Flavor.Matches(mask, Flavor.RETAIL) and not BJ.API.IsJunk(id) then ids[#ids + 1] = id end
  end
  return ids
end

local function fish(level)
  local list, search = {}, ""
  local page = frame()
  if page and page.RecipeList and page.RecipeList.SearchBox then search = (page.RecipeList.SearchBox:GetText() or ""):lower() end
  -- only the fish of the open expansion (catalogue level); the item data is loaded at this point (see prepare)
  for _, id in ipairs(fishIDs(level)) do
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or BJ.DB:ItemName(id)
    if name and (search == "" or name:lower():find(search, 1, true)) then
      list[#list + 1] = {kind = "fish", id = id, name = name, uncommon = BJ.DB:ItemQuality(id) == 2 or firstLineQuality(id) == 2,
        caught = BJ.API.GetCaught(id, true) > 0}
    end
  end
  table.sort(list, function(a, b) return strcmputf8i(a.name, b.name) < 0 end)
  return list
end

--- The zones of the open expansion where we have catches: list of { kind = "zone", id, name }.
local function zones(level)
  local list, search = {}, ""
  local page = frame()
  if page and page.RecipeList and page.RecipeList.SearchBox then search = (page.RecipeList.SearchBox:GetText() or ""):lower() end
  local levelOf = BJ.modules.Tooltip and BJ.modules.Tooltip.ZoneLevel
  if not levelOf then return list end
  for _, z in ipairs(BJ.API.GetZoneList(Flavor.RETAIL)) do
    if levelOf(z.zone) == level and (search == "" or z.name:lower():find(search, 1, true)) then
      list[#list + 1] = {kind = "zone", id = z.zone, name = z.name}
    end
  end
  table.sort(list, function(a, b) return strcmputf8i(a.name, b.name) < 0 end)
  return list
end

local ZONE_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local function sortRoot(l, r)
  local a, b = l:GetData(), r:GetData()
  if a.group ~= b.group then return a.group < b.group end
  return (a.categoryInfo and a.categoryInfo.uiOrder or 0) < (b.categoryInfo and b.categoryInfo.uiOrder or 0)
end

local function sortCategory(l, r)
  local a, b = l:GetData(), r:GetData()
  if a.order ~= b.order then return a.order < b.order end
  local x, y = a.recipeInfo, b.recipeInfo
  if x and y then return strcmputf8i(x.name, y.name) < 0 end
  return false
end

local function addCategory(root, id, order, name, entries, group, collapsed)
  if #entries == 0 then return nil end
  group = group or GROUP_LEARNED
  local info = {name = name, categoryID = id, uiOrder = order, group = group, unlearned = false, hasProgressBar = false}
  local node = root:Insert({categoryInfo = info, group = group})
  node:SetSortComparator(sortCategory, false, false)
  node:Insert({topPadding = true, order = -1})
  for _, f in ipairs(entries) do
    -- all entries are "learned" dummy recipes (an unlearned one makes the game load the recipe page, which fails for our
    -- entries); a fish never caught is greyed by prepareButtons
    local isFish = f.kind == "fish"
    local icon = isFish and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(f.id) or ZONE_ICON
    node:Insert({order = 0, bjKey = f.kind .. ":" .. f.id, bjMissing = isFish and not f.caught, recipeInfo = {recipeID = isFish and -f.id or -(10000000 + f.id),
      name = f.name, icon = icon, learned = true, disabled = false, canSkillUp = false, numSkillUps = 0, favorite = false,
      isDummyRecipe = true}})
  end
  node:Insert({bottomPadding = true, order = 1})
  if collapsed then node:SetCollapsed(true) end
  return node
end

--- The filter menu of the list ("Show learned", "Show unlearned", "Have materials") as the game keeps it. For our fish "learned"
--- means caught at least once and "materials" means in the bags or the bank. Missing functions count as "everything shown".
local function filters()
  local T = C_TradeSkillUI
  local function get(name, default)
    local f = T and T[name]
    if type(f) ~= "function" then return default end
    local ok, v = pcall(f)
    if ok and v ~= nil then return v end
    return default
  end
  return {learned = get("GetShowLearned", true), unlearned = get("GetShowUnlearned", true), materials = get("GetOnlyShowMakeableRecipes", false)}
end

local function passes(f, flt)
  if f.caught and not flt.learned then return false end
  if not f.caught and not flt.unlearned then return false end
  if flt.materials then
    local stock = ns.Stock and ns.Stock.Counts(f.id)
    if not (stock and stock.bags + stock.bank + stock.warband > 0) then return false end
  end
  return true
end

-- the list we filled (provider and expansion level), so that the star can rebuild it
local current

--- Builds (or rebuilds) our categories: favourites (bookmarked fish), common, uncommon. Collapse states are kept.
local function build()
  local provider, level = current and current.provider, current and current.level
  if not provider then return end
  local root = provider:GetRootNode()
  local collapsed = current.collapsed
  for _, entry in ipairs(current.nodes) do
    collapsed[entry.id] = entry.node:IsCollapsed()
    root:Remove(entry.node)
  end
  current.nodes = {}
  root:SetSortComparator(sortRoot, false, false)
  local favorites, common, uncommon, missing = {}, {}, {}, {}
  local flt = filters()
  for _, f in ipairs(fish(level)) do
    if passes(f, flt) then
      if BJ.API.IsBookmarked("fish", f.id) then table.insert(favorites, f) end
      if f.caught then table.insert(f.uncommon and uncommon or common, f) else table.insert(missing, f) end -- not caught: own heading
    end
  end
  local zoneEntries = zones(level)
  for _, z in ipairs(zoneEntries) do
    if BJ.API.IsBookmarked("zone", z.id) then table.insert(favorites, z) end
  end
  table.sort(favorites, function(a, b) return strcmputf8i(a.name, b.name) < 0 end)
  local function add(id, order, name, entries, group)
    local node = addCategory(root, id, order, name, entries, group, collapsed[id])
    if node then current.nodes[#current.nodes + 1] = {id = id, node = node} end
  end
  add(-9000, 0, PROFESSIONS_CATEGORY_FAVORITE or FAVORITES, favorites, GROUP_FAVORITE)
  add(-9003, 1, L["Zones"], zoneEntries) -- order like in the game: favourites, zones, fish
  add(-9001, 2, L["Common fish"], common)
  add(-9002, 3, L["Uncommon fish"], uncommon)
  add(-9004, 4, L["Not caught yet"], missing) -- its own heading, sorted last
  -- Blizzard showed "no results" because the list was empty at that moment
  local page = frame()
  local noResults = page and page.RecipeList and page.RecipeList.NoResultsText
  if noResults and #current.nodes > 0 then noResults:Hide() end
end

--- Calls done() once the item data of all ids is loaded (at the latest after 2 seconds).
local function loadItems(ids, done)
  local pending, finished = #ids, false
  local function finish()
    if finished then return end
    finished = true
    for _, id in ipairs(ids) do BJ.DB:ItemTooltip(id) end -- saved once per item ID; later clicks read the database
    done()
  end
  if pending == 0 or not (Item and Item.CreateFromItemID) then finish() return end
  for _, id in ipairs(ids) do
    Item:CreateFromItemID(id):ContinueOnItemLoad(function()
      pending = pending - 1
      if pending <= 0 then finish() end
    end)
  end
  C_Timer.After(2, finish)
end

local function onProvider(_, provider)
  if not BJ.settings.diaryList or type(provider) ~= "table" or provider.bjDone then return end
  if not (provider.IsEmpty and provider:IsEmpty()) then return end
  local level = openLevel()
  if not level then return end
  if level ~= selectedLevel then selected = nil end -- another expansion page: the old fish page is gone
  provider.bjDone = true
  -- Blizzard selects the first recipe of the list right after it was set; our entries must not exist yet at that moment
  -- (they are no real recipes), so they are inserted later: one frame at the earliest, and once the item data (name,
  -- quality, tooltip) of the fish is loaded, because the quality decides the category.
  local function insert()
    BJ.Protected("diarylist insert", function()
      current = {provider = provider, level = level, nodes = {}, collapsed = {}}
      build()
    end)
  end
  C_Timer.After(0, function() loadItems(fishIDs(level), insert) end)
end

-- Right side: the tooltip of the fish in the style of a recipe page (own frame over the schematic form)
local pane, selected, selectedLevel -- selected = "fish:123" or "zone:2393"

local function hidePane()
  if pane and pane:IsShown() then pane:Hide() end
end

local function layoutPane()
  if not (pane and pane.scroll) then return end
  local width = pane.scroll:GetWidth()
  if width and width > 1 then pane.content:SetWidth(width) end
  pane.content:SetHeight(28 + 47 + 12 + (pane.body:GetStringHeight() or 0) + 24)
  pane.scroll:UpdateScrollChildRect()
end

--- TomTom routes of the zone pages (only when TomTom is loaded)
local function tomtom() return _G.TomTom and _G.TomTom.AddWaypoint and _G.TomTom end

local function fishSpots(zone, itemID)
  local list = BJ.API.GetZoneSpots(zone, itemID, Flavor.RETAIL)
  table.sort(list, function(a, b) return a.count > b.count end)
  return list
end

local function addWaypoint(zone, spot, title)
  tomtom():AddWaypoint(zone, spot.x, spot.y, {title = title, persistent = false, minimap = true, world = true})
end

--- Waypoints for the spots in nearest-neighbour order, starting at the player when on this map, else at the richest spot.
local function route(zone, list, title)
  local tt = tomtom()
  if not tt or #list == 0 then return end
  if tt.ClearAllWaypoints then tt:ClearAllWaypoints() end
  local px, py
  if C_Map and C_Map.GetPlayerMapPosition then
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, zone, "player")
    if ok and pos and pos.GetXY then px, py = pos:GetXY() end
  end
  local rest = {unpack(list)}
  local cx, cy = px, py
  while #rest > 0 do
    local best, bi = nil, 1
    for i, sp in ipairs(rest) do
      local d = cx and ((sp.x - cx) ^ 2 + (sp.y - cy) ^ 2) or -sp.count
      if not best or d < best then best, bi = d, i end
    end
    local sp = table.remove(rest, bi)
    addWaypoint(zone, sp, title)
    cx, cy = sp.x, sp.y
  end
  if tt.SetClosestWaypoint then pcall(tt.SetClosestWaypoint, tt) end
end

--- Tooltip over a fish name or its coordinates on the zone pages: what the clicks do.
function M.RouteTip(owner, zone, itemID)
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
  GameTooltip:AddLine(ns.Colors.Paint("aqua", BJ.DB:ItemName(itemID) or "Bobber's Journal"))
  local spot = fishSpots(zone, itemID)[1]
  if spot then GameTooltip:AddLine(format("%.1f / %.1f", spot.x * 100, spot.y * 100), 1, 0.82, 0) end
  GameTooltip:AddLine(L["Left click: set waypoint"], 1, 1, 1)
  GameTooltip:AddLine(L["Right click: menu"], 0.26, 0.69, 1)
  GameTooltip:Show()
end

function M.RouteClick(owner, zone, itemID, button)
  if not tomtom() then return end
  local title = BJ.DB:ItemName(itemID) or "Bobber's Journal"
  local list = fishSpots(zone, itemID)
  if #list == 0 then return end
  if button ~= "RightButton" then addWaypoint(zone, list[1], title) return end
  local entries = {
    {L["Set waypoint (TomTom)"], function() addWaypoint(zone, list[1], title) end},
    {L["Route to all spots of this fish"], function() route(zone, list, title) end},
    {L["Route to the best 5 spots"], function()
      local top = {}
      for i = 1, math.min(5, #list) do top[i] = list[i] end
      route(zone, top, title)
    end},
  }
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner, function(_, menu)
      for _, e in ipairs(entries) do menu:CreateButton(e[1], e[2]) end
    end)
  end
end

local function ensurePane()
  if pane then return pane end
  local page = frame()
  pane = CreateFrame("Frame", nil, page)
  pane:SetAllPoints(page.SchematicForm)
  pane:SetFrameLevel(page.SchematicForm:GetFrameLevel() + 5)
  pane:Hide()
  -- long texts scroll with Blizzard's own scroll frame template (scroll bar included)
  pane.scroll = CreateFrame("ScrollFrame", nil, pane, "ScrollFrameTemplate")
  pane.scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
  pane.scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -24, 4)
  if pane.scroll.ScrollBar and pane.scroll.ScrollBar.SetHideIfUnscrollable then pane.scroll.ScrollBar:SetHideIfUnscrollable(true) end
  pane.content = CreateFrame("Frame", nil, pane.scroll)
  pane.content:SetSize(10, 10)
  pane.scroll:SetScrollChild(pane.content)
  pane.scroll:HookScript("OnSizeChanged", layoutPane)
  -- like the output icon of a recipe: round item button; title in gold, star = bookmark of the fish
  local ok, icon = pcall(CreateFrame, "Button", nil, pane.content, "ProfessionsOutputButtonTemplate")
  if not ok then icon = CreateFrame("Button", nil, pane.content) icon:SetSize(54, 54) icon.Icon = icon:CreateTexture(nil, "ARTWORK") icon.Icon:SetAllPoints() end
  pane.icon = icon
  icon:SetScript("OnEnter", function(self)
    if not pane.entryID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if pane.kind == "fish" then
      GameTooltip:SetItemByID(pane.entryID)
    else
      GameTooltip:AddLine(pane.title:GetText() or "", 1, 0.82, 0)
      for _, text in ipairs(pane.tipLines or {}) do GameTooltip:AddLine(text, 1, 1, 1) end
    end
    GameTooltip:Show()
  end)
  icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
  icon:SetScale(44 / 47) -- 3 px smaller than the original size
  icon:SetPoint("TOPLEFT", 28 / (44 / 47), -28 / (44 / 47)) -- position of the output icon in Blizzard's recipe form (not minimized)
  pane.title = pane.content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  pane.title:SetPoint("LEFT", icon, "RIGHT", 14, 17) -- like OutputText of the form
  pane.title:SetJustifyH("LEFT")
  pane.star = CreateFrame("CheckButton", nil, pane.content)
  pane.star:SetSize(20, 18)
  pane.star:SetPoint("LEFT", pane.title, "RIGHT", 4, 1) -- like FavoriteButton of the form
  pane.star.tex = pane.star:CreateTexture(nil, "ARTWORK")
  pane.star.tex:SetAllPoints()
  pane.star.high = pane.star:CreateTexture(nil, "HIGHLIGHT")
  pane.star.high:SetAllPoints()
  pane.star.high:SetBlendMode("ADD")
  pane.star.high:SetAlpha(0.4)
  pane.star:SetScript("OnClick", function(self)
    if not pane.entryID then return end
    BJ.API.SetBookmark(pane.kind, pane.entryID, not BJ.API.IsBookmarked(pane.kind, pane.entryID))
    pane.refreshStar()
    BJ.Protected("diarylist favourites", build)
  end)
  pane.refreshStar = function()
    local on = pane.entryID and BJ.API.IsBookmarked(pane.kind, pane.entryID)
    local atlas = on and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off"
    pane.star.tex:SetAtlas(atlas)
    pane.star.high:SetAtlas(atlas)
  end
  -- fish name and coordinates of the zone pages (TomTom loaded): left click = waypoint at the best spot, right click = menu
  pane.content:SetHyperlinksEnabled(true)
  pane.content:SetScript("OnHyperlinkEnter", function(self, link)
    local map, id = link:match("^bjroute:(%d+):(%d+)")
    if map then BJ.Protected("diarylist route tip", M.RouteTip, self, tonumber(map), tonumber(id)) end
  end)
  pane.content:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  pane.content:SetScript("OnHyperlinkClick", function(self, link, _, button)
    local map, id = link:match("^bjroute:(%d+):(%d+)")
    if not map then return end
    BJ.Protected("diarylist route", M.RouteClick, self, tonumber(map), tonumber(id), button)
  end)
  pane.body = pane.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall2")
  pane.body:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -1, -12) -- like the description of the form (width 460)
  pane.body:SetWidth(460)
  pane.body:SetJustifyH("LEFT")
  pane.body:SetJustifyV("TOP")
  pane.body:SetSpacing(3)
  -- right column (coordinates): same font, width and line spacing, so its lines sit level with the lines of the body
  pane.right = pane.content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall2")
  pane.right:SetPoint("TOPLEFT", pane.body, "TOPLEFT")
  pane.right:SetWidth(460)
  pane.right:SetJustifyH("RIGHT")
  pane.right:SetJustifyV("TOP")
  pane.right:SetSpacing(3)
  return pane
end

local Paint = ns.Colors.Paint
local HEADING = "|cff33bb66" -- green of the headings on the game's fish pages (information from the game)
local AQUA = ns.Colors.aquaHex -- headings of our own data

--- Text of one tooltip line (with its colour), or nil. A "Use:" line becomes the heading "Special use:" with the text in
--- white below it, like on the game's fish pages.
local function lineText(line)
  local left = line.text
  local prefix = ITEM_SPELL_TRIGGER_ONUSE
  if type(prefix) == "string" and prefix ~= "" and left:sub(1, #prefix) == prefix then
    local rest = left:sub(#prefix + 1):gsub("^%s+", "")
    return HEADING .. L["Special use:"] .. "|r\n" .. rest
  end
  left = ns.Colors.Wrap(line.r, line.g, line.b, left)
  if line.right then left = left .. "    " .. line.right end
  return left
end

local function isGold(line)
  return math.abs(line.r - 1) < 0.05 and math.abs(line.g - 0.82) < 0.05 and line.b < 0.1
end

--- Fills the common part of the page: ring icon, title, star. ring: Blizzard's own output icon set-up.
local function setHead(p, kind, id, title, texture, itemID)
  local quality = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0
  -- the pages of the journal have no output item, so Blizzard passes quality 0: the grey ring for every entry
  local done = Professions and Professions.SetupOutputIconCommon
    and pcall(Professions.SetupOutputIconCommon, p.icon, 1, 1, texture, itemID or id, quality)
  if not done and p.icon.Icon then p.icon.Icon:SetTexture(texture) end
  p.kind, p.entryID = kind, id
  p.refreshStar()
  p.title:SetText(title)
  -- width of the name itself, so the star sits right behind it (long names wrap at 300)
  p.title:SetWidth(0)
  if p.title:GetStringWidth() > 300 then p.title:SetWidth(300) end
  p.title:SetTextColor(1, 0.82, 0) -- gold like the recipe titles
end

local function showPane(p)
  -- the schematic form stays (its frame border "NineSlice" and the background art belong to it); on these pages it is empty
  p:Show()
  p.scroll:SetVerticalScroll(0)
  layoutPane()
end

-- sequence like the game's fish pages: general lines, description, special use, zones, (fish schools,) rates
local showFish
function showFish(id)
  local page = frame()
  if not page then return end
  local p = ensurePane()
  local lines = BJ.DB:ItemTooltip(id)
  local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or BJ.DB:ItemName(id) or "?"
  local raw = BJ.DB.raw
  local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (raw and raw.items[id] and raw.items[id].i)
  setHead(p, "fish", id, name, icon)
  if not lines and Item and Item.CreateFromItemID then
    -- not delivered yet (and not saved): ask the client and draw the page again when it arrives, if it is still the open one
    Item:CreateFromItemID(id):ContinueOnItemLoad(function()
      if selected == "fish:" .. id and pane and pane:IsShown() and BJ.DB:ItemTooltip(id) then BJ.Protected("diarylist fish", showFish, id) end
    end)
  end
  local info, description, use = {}, {}, {}
  for i, line in ipairs(lines or {}) do
    if i > 1 then
      local text = lineText(line)
      if text then
        if text:find("^" .. HEADING) then use[#use + 1] = text
        elseif isGold(line) then description[#description + 1] = line.text:gsub('^"', ""):gsub('"$', "")
        else info[#info + 1] = text end
      end
    end
  end
  local parts = {}
  if #info > 0 then parts[#parts + 1] = table.concat(info, "\n") end
  if #description > 0 then parts[#parts + 1] = HEADING .. L["Description:"] .. "|r\n" .. table.concat(description, "\n") end
  if #use > 0 then parts[#parts + 1] = table.concat(use, "\n") end
  local Diary = BJ.modules.Diary
  local zonesPart = Diary and Diary.Zones and Diary.Zones(id)
  local ratesPart = Diary and Diary.Rates and Diary.Rates(id)
  local recipesPart = Diary and Diary.Recipes and Diary.Recipes(id)
  local morePart = Diary and Diary.Sections and Diary.Sections(id) -- stock and value per hour, as in the journal
  -- our own data below the information of the game, under our heading (like on the pages of the game)
  if zonesPart or recipesPart or ratesPart or morePart then parts[#parts + 1] = Diary.Label() end
  if zonesPart then parts[#parts + 1] = zonesPart end
  if recipesPart then parts[#parts + 1] = recipesPart end
  if morePart then parts[#parts + 1] = morePart end
  if ratesPart then parts[#parts + 1] = ratesPart end
  p.tipLines = nil
  p.right:SetText("")
  p.body:SetText(table.concat(parts, "\n\n"))
  showPane(p)
end

--- Page of a zone: the fish caught there and the statistics.
local function showZone(zone)
  local page = frame()
  if not page then return end
  local p = ensurePane()
  local API = BJ.API
  setHead(p, "zone", zone, API.GetZoneName(zone), ZONE_ICON)
  -- the zone and its sub maps added up
  local data = BJ.modules.Diary.ZoneData(zone)
  local hasTomTom = _G.TomTom and _G.TomTom.AddWaypoint
  local fishLines, tip, coordLines = {}, {}, {"", "", ""} -- coordLines: one entry per body line (heading, blank line, heading)
  for _, f in ipairs(data.fish) do
    local name = BJ.DB:ItemName(f.itemID) or ("#" .. f.itemID)
    local r, g, b = BJ.DB:ItemColor(f.itemID)
    local colored = ns.Colors.Wrap(r, g, b, name)
    local coordText = ""
    local spot = f.spot
    if spot then
      coordText = format("|cffffd100[%.1f, %.1f]|r", spot.x * 100, spot.y * 100)
      if hasTomTom then
        local link = format("|Hbjroute:%d:%d|h", spot.key, f.itemID)
        coordText = link .. coordText .. "|h"
        colored = link .. colored .. "|h"
      end
    end
    fishLines[#fishLines + 1] = format("- %s: %s", colored, ns.Format.Value(f.drops, f.chance))
    coordLines[#coordLines + 1] = coordText
    tip[#tip + 1] = name
  end
  local totals = data
  local parts = {BJ.modules.Diary.Label()}
  if #fishLines > 0 then parts[#parts + 1] = AQUA .. L["Fish in this zone:"] .. "|r\n" .. table.concat(fishLines, "\n") end
  parts[#parts + 1] = AQUA .. L["Rates:"] .. "|r\n" .. format(L["Casts: %d"], totals.cast) .. "\n" .. format(L["Catches: %d"], totals.catch)
  p.tipLines = tip
  p.body:SetText(table.concat(parts, "\n\n"))
  p.right:SetText(#fishLines > 0 and table.concat(coordLines, "\n") or "")
  showPane(p)
end

local function showEntry(key)
  local kind, id = key:match("^(%a+):(%d+)$")
  id = tonumber(id)
  if kind == "fish" then showFish(id) elseif kind == "zone" then showZone(id) end
end

local function selectEntry(button, key)
  selected, selectedLevel = key, openLevel()
  showEntry(key)
  local box = frame().RecipeList.ScrollBox
  box:ForEachFrame(function(b, node)
    local data = node and node.GetData and node:GetData()
    if data and data.bjKey and b.SetSelected then b:SetSelected(data.bjKey == key) end
  end)
end

local function greyOut(button)
  if button.bjMissing and button.Label and button.Label.SetTextColor then button.Label:SetTextColor(0.55, 0.55, 0.55) end
end

-- Set after Blizzard's own initializer, every time the list is updated: our entries are no recipes, a click shows the fish.
local function prepareButtons(scrollBox)
  scrollBox:ForEachFrame(function(button, node)
    local data = node and node.GetData and node:GetData()
    if data and data.bjKey then
      local key = data.bjKey
      button:SetScript("OnClick", function(self, mouse)
        if mouse == "LeftButton" then BJ.Protected("diarylist select", selectEntry, self, key) end
      end)
      if button.SetSelected then button:SetSelected(selected == key and pane and pane:IsShown()) end
      -- a fish never caught is grey (the game's own colours apply to the others); the game recolours the label on mouse over
      -- and when the mouse leaves, so the grey is set again after both
      button.bjMissing = data.bjMissing == true
      greyOut(button)
      if not button.bjGreyHooked then
        button.bjGreyHooked = true
        button:HookScript("OnEnter", greyOut)
        button:HookScript("OnLeave", greyOut)
      end
    elseif button.bjMissing then
      button.bjMissing = false -- the button is reused for a row of the game
    end
  end)
end

local function hook()
  if hooked then return end
  local page = frame()
  local box = page and page.RecipeList and page.RecipeList.ScrollBox
  if not (box and box.SetDataProvider and box.RegisterCallback and ScrollBoxListMixin) then return end
  hooked = true
  if page.SchematicForm and page.SchematicForm.Init then
    -- A real recipe replaces our page. Init(nil) only means "the list was rebuilt" (item data arrived, filter changed):
    -- then the page of the selected fish is shown again.
    hooksecurefunc(page.SchematicForm, "Init", function(_, recipeInfo)
      if recipeInfo then
        selected = nil
        hidePane()
      elseif selected then
        BJ.Protected("diarylist reshow", showEntry, selected)
      end
    end)
  end
  page:HookScript("OnHide", function() selected = nil hidePane() end)
  hooksecurefunc(box, "SetDataProvider", function(...) BJ.Protected("diarylist", onProvider, ...) end)
  box:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, function() BJ.Protected("diarylist click", prepareButtons, box) end, M)
end

function M:OnEnable()
  if Flavor.current ~= Flavor.RETAIL then return end
  hook()
  BJ:RegisterEvent("ADDON_LOADED", "diarylist", function(_, addon)
    if addon == "Blizzard_Professions" then hook() end
  end)
end
