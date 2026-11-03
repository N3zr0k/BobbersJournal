local _, ns = ...
local BJ = ns.BJ
local L = BJ.L
-- Journal window in the look of the Blizzard spell book (two pages, header, bookmark ribbon).
-- Left page: tabs + search + list. Right page: details of the selected entry.
-- Art: Retail book atlases when the client has them, otherwise the classic spell book page textures
-- (Interface\Spellbook\Spellbook-Page-1/2). Layout values are derived from Blizzard_SpellBookFrame.xml
-- (wow-ui-source); written for this addon, not copied.
local M = BJ:RegisterModule("Journal")

local WIDTH, HEIGHT = 940, 640
local ROWS, ROW_H = 14, 28
local CURL_W, CURL_H = 100, 103 -- page-curl animation (Blizzard uses 150x155 in its much larger window)
local TABS = {"fish", "junk", "lures", "zones", "vendors", "bookmarks"}
local TAB_ICON = {fish = "Fish", junk = "Muell", lures = "Koeder", zones = "Zones", vendors = "Equipment", bookmarks = "Book"}
local TAB_TEXT = {fish = "Fish", junk = "Junk", lures = "Lures", zones = "Zones", vendors = "Vendors", bookmarks = "Bookmarks"}
-- Tabs without an icon of our own use a game icon.
local TAB_TEXTURE = {}
-- Texture size per tab where it is not 128 (the junk icon is made for 64).
local TAB_ICON_PX = {junk = 64}

-- Tabs shown as a grid of framed icons (like the toy box): collected = gold frame, not yet seen = grey.
local GRID = {fish = true, junk = true, lures = true}
local COLS, CELL_W, CELL_H = 2, 200, 56
local GRID_ROWS = 7
local state = {tab = "fish", sub = "overview", search = "", offset = 0, selected = nil}
local frame

-- Pages of the right page per kind of entry; the arrows at the bottom right turn through them (the left page lists).
local PAGES = {fish = {"info", "map", "sales"}, lure = {"info", "sales"}, npc = {"info", "map"}}
local PAGE_LABEL = {info = "Info", map = "Map", sales = "Sales"}
local function pagesOf(sel)
  if not sel then return {"info"} end
  if sel.kind == "zone" or sel.kind == "subzone" or sel.kind == "vzone" then return {"map"} end
  return PAGES[sel.kind] or {"info"}
end

--- The sound of a page being turned.
local function pageSound()
  if PlaySound and SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
end

local MODEL_W, MODEL_H, MODEL_TOP = 140, 140, 100 -- the head of the model stands level with the title
local hasAtlas = BJ.HasAtlas

-- Item names arrive late (the client loads item data on request). The Item mixin calls back when the data is there;
-- the list is redrawn once for a whole batch of items. A request that never answers is repeated after a few seconds.
local asked, redrawQueued = {}, false

local function redrawLater()
  if redrawQueued or not C_Timer then return end
  redrawQueued = true
  C_Timer.After(0.3, function()
    redrawQueued = false
    if frame and frame:IsShown() then M.Refresh() end
  end)
end

--- " - 2g 50s" after an item name when the vendor's price is known
local function vendorPrice(n, itemID)
  local text = n.offers and n.offers[itemID] and ns.Prices.OfferText(n.offers[itemID]) or ""
  return text ~= "" and ("  |cffaaaaaa" .. text .. "|r") or ""
end

local function itemName(id)
  local name = BJ.DB:ItemName(id) -- live name (saved in the database) or the saved one
  if name then return name end
  if not asked[id] then
    asked[id] = true
    if Item and Item.CreateFromItemID then
      Item:CreateFromItemID(id):ContinueOnItemLoad(function() asked[id] = nil redrawLater() end)
    elseif C_Item and C_Item.RequestLoadItemDataByID then
      C_Item.RequestLoadItemDataByID(id)
    end
    if C_Timer then C_Timer.After(5, function() asked[id] = nil end) end
  end
  return "[" .. id .. "]"
end

local function itemIcon(id)
  local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  return getInfo and select(5, getInfo(id)) or nil
end

-- Region of a zone for the zone list: the name of its parent map (continent or zone level), e.g. Quel'Thalas for
-- Silvermoon. nil when the client has no map data or the parent is the whole world.
local function regionOf(zone)
  if type(zone) ~= "number" or zone <= 0 or not (C_Map and C_Map.GetMapInfo) then return nil end
  local info = C_Map.GetMapInfo(zone)
  local parent = info and info.parentMapID
  if not parent or parent == 0 then return nil end
  local p = C_Map.GetMapInfo(parent)
  local t = Enum and Enum.UIMapType
  if not p or not p.name or (t and p.mapType and p.mapType < t.Continent) then return nil end
  return p.name
end

-- Quality colour of an item for the parchment: the grey of poor items is darkened (the game grey is too light here).
local function qualityInk(id)
  local r, g, b = BJ.DB:ItemColor(id)
  if r and BJ.DB:ItemQuality(id) == 0 then return 0.36, 0.33, 0.30 end
  return r, g, b
end

-- Folding of the zone list (saved): regions and zones can be opened and closed.
local function fold()
  local s = BJ.settings
  s.journalFold = s.journalFold or {}
  s.journalFold.regions = s.journalFold.regions or {}
  s.journalFold.zones = s.journalFold.zones or {}
  return s.journalFold
end

-- Entry lists per tab: { kind, id, text, icon, sub }
local function buildEntries()
  local A, out = BJ.API, {}
  local function add(kind, id, text, icon, sub)
    local q = state.search
    if q ~= "" and not text:lower():find(q, 1, true) then return end
    out[#out + 1] = {kind = kind, id = id, text = text, icon = icon, sub = sub}
    return out[#out]
  end
  local tab = state.tab
  if tab == "fish" or tab == "junk" or tab == "bookmarks" then
    for _, f in ipairs(A.GetFishList()) do
      -- Junk has its own tab; the fish tab only lists what is no junk.
      local junk = A.IsJunk(f.itemID)
      if (tab == "fish" and not junk) or (tab == "junk" and junk) or (tab == "bookmarks" and A.IsBookmarked("fish", f.itemID)) then
        add("fish", f.itemID, itemName(f.itemID), itemIcon(f.itemID), f.caught)
      end
    end
    -- shipped catalogue: fish not caught yet (grey, "rumour")
    if tab == "fish" then
      local have = {}
      for _, e in ipairs(out) do have[e.id] = true end
      for id, mask in pairs(ns.Catalog and ns.Catalog.fish or {}) do
        if not have[id] and ns.Flavor.Matches(mask, nil) and (ns.Catalog.fishExp[id] or 0) <= ns.Catalog.ActiveExpansion() and not A.IsJunk(id) then
          local e = add("fish", id, itemName(id), itemIcon(id), 0)
          if e then e.unseen = true end
        end
      end
    end
  end
  if tab == "vendors" then
    -- by zone (map of the NPC), clustered by region like the zones; the NPCs of a zone are its children
    local q, byMap, maps = state.search, {}, {}
    for _, n in ipairs(A.GetNPCs()) do
      local map = n.map or 0
      if not byMap[map] then byMap[map] = {} maps[#maps + 1] = map end
      byMap[map][#byMap[map] + 1] = n
    end
    for _, map in ipairs(maps) do
      local info = map ~= 0 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
      local zoneName = info and info.name or L["Other"]
      local region = regionOf(map) or L["Other"]
      local zoneMatch = q == "" or zoneName:lower():find(q, 1, true) ~= nil or region:lower():find(q, 1, true) ~= nil
      local shown = {}
      for _, n in ipairs(byMap[map]) do
        if zoneMatch or (n.name or ""):lower():find(q, 1, true) then shown[#shown + 1] = n end
      end
      if #shown > 0 then
        out[#out + 1] = {kind = "vzone", id = map, text = zoneName, sub = #shown, sortKey = zoneName, region = region, subCount = #shown}
        for _, n in ipairs(shown) do
          out[#out + 1] = {kind = "npc", id = n.id, text = n.name or ("#" .. n.id), sub = n.trainer and L["Fishing teacher"] or L["Fishing vendor"],
            icon = n.trainer and ns.Icons.teacher or ns.Icons.vendor, npc = n, zone = map, region = region,
            sortKey = zoneName .. "\1" .. (n.name or "")}
        end
      end
    end
  end
  if tab == "bookmarks" then
    -- bookmarked vendors and teachers
    for _, n in ipairs(A.GetNPCs()) do
      if A.IsBookmarked("npc", n.id) then
        local e = add("npc", n.id, n.name or ("#" .. n.id), n.trainer and ns.Icons.teacher or ns.Icons.vendor, n.trainer and L["Fishing teacher"] or L["Fishing vendor"])
        if e then e.npc, e.zone, e.flat = n, n.map or 0, true end
      end
    end
  end
  if tab == "lures" then
    local usedItem = {}
    local bags = ns.Lures and ns.Lures.BagCounts() or {}
    -- lures in the bags are confirmed by the game itself
    for id, b in pairs(bags) do if BJ.DB.raw and BJ.DB.raw.lureCatalog then BJ.DB.raw.lureCatalog[id] = b.bonus end end
    for enchantID, v in pairs(A.GetLureStats()) do
      local text = v.itemID and itemName(v.itemID) or format(L["Lure #%d"], enchantID)
      local e = add("lure", enchantID, text, v.itemID and itemIcon(v.itemID) or "Interface\\Icons\\INV_Misc_Orb_01", v.cast)
      if e then
        e.itemID = v.itemID
        e.count = v.itemID and bags[v.itemID] and bags[v.itemID].count or nil
        e.locked = v.itemID and bags[v.itemID] and bags[v.itemID].usable == false or nil
        e.unseen = v.cast == 0 and v.applied == 0 and not e.count
      end
      if v.itemID then usedItem[v.itemID] = true end
    end
    -- lures known from the game or the shipped list that were never used: grey
    for itemID in pairs(ns.Catalog and ns.Catalog.Lures() or {}) do
      if not usedItem[itemID] then
        local e = add("lure", "i" .. itemID, itemName(itemID), itemIcon(itemID), 0)
        if e then
          e.itemID = itemID
          e.count = bags[itemID] and bags[itemID].count or nil
          e.locked = bags[itemID] and bags[itemID].usable == false or nil
          e.unseen = not e.count
        end
      end
    end
  end
  if tab == "zones" or tab == "bookmarks" then
    local q = state.search
    for _, z in ipairs(A.GetZoneList()) do
      if tab == "zones" then
        -- The search is the zone filter: a match on the zone or its region shows the whole zone with its sub zones,
        -- a match on a sub zone shows that sub zone below its zone.
        local region = regionOf(z.zone) or L["Other"]
        local zoneMatch = q == "" or z.name:lower():find(q, 1, true) ~= nil or region:lower():find(q, 1, true) ~= nil
        local subs = A.GetSubZones(z.zone)
        local shown = {}
        for _, sz in ipairs(subs) do
          if zoneMatch or sz.name:lower():find(q, 1, true) then shown[#shown + 1] = sz end
        end
        if zoneMatch or #shown > 0 then
          out[#out + 1] = {kind = "zone", id = z.zone, text = z.name, sub = z.catches, sortKey = z.name, region = region, subCount = #subs}
          for _, sz in ipairs(shown) do
            out[#out + 1] = {kind = "subzone", id = z.zone .. ":" .. sz.name, text = sz.name, sub = sz.catches, zone = z.zone,
              subName = sz.name, zoneName = z.name, region = region, sortKey = z.name .. "\1" .. sz.name}
          end
        end
      elseif A.IsBookmarked("zone", z.zone) then
        add("zone", z.zone, z.name, nil, z.catches)
      end
    end
  end
  if tab == "zones" or tab == "vendors" then
    -- clustered by region, regions alphabetically, "Other" last
    local other = L["Other"]
    table.sort(out, function(a, b)
      if a.region ~= b.region then
        if a.region == other then return false elseif b.region == other then return true end
        return a.region < b.region
      end
      return (a.sortKey or a.text) < (b.sortKey or b.text)
    end)
    return out
  end
  if tab == "lures" then
    -- lures in the bags first
    table.sort(out, function(a, b)
      if (a.count ~= nil) ~= (b.count ~= nil) then return a.count ~= nil end
      return a.text < b.text
    end)
    return out
  end
  table.sort(out, function(a, b) return a.text < b.text end)
  return out
end

local function detailLines(entry)
  local A, lines = BJ.API, {}
  if not entry then return {L["Select an entry on the left page."]} end
  if entry.kind == "lure" then
    local v = A.GetLureStats()[entry.id] or {cast = 0, catch = 0, time = 0, applied = 0, itemID = entry.itemID}
    local t = A.GetTotals()
    local plainCast, plainCatch = math.max(t.cast - v.cast, 0), 0
    local lured = 0
    for _, s in pairs(A.GetLureStats()) do lured = lured + s.catch end
    plainCatch = math.max(t.catch - lured, 0)
    lines[1] = format("%s: %d", L["Casts"], v.cast)
    lines[2] = format("%s: %d", L["Catches"], v.catch)
    lines[#lines + 1] = format("%s: %d", L["Applied"], v.applied)
    lines[#lines + 1] = format("%s: %s", L["Time fished"], v.time >= 3600 and format("%dh %dm", v.time / 3600, v.time % 3600 / 60) or format("%dm %ds", v.time / 60, v.time % 60))
    lines[#lines + 1] = format("%s", v.itemID and (A.IsConfirmed("lure", v.itemID) and L["Confirmed"] or L["Rumour"]) or L["Confirmed"])
    if v.cast > 0 then lines[3] = format("%s: %s", L["Catch rate"], ns.Format.Percent(v.catch / v.cast, true)) end
    if plainCast > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = format("%s: %s  (%d)", L["Without lure"], ns.Format.Percent(plainCatch / plainCast, true), plainCast)
    end
    local bonus = v.itemID and ns.Catalog and ns.Catalog.Lures()[v.itemID]
    if bonus then lines[#lines + 1] = "" lines[#lines + 1] = format("%s: +%d", L["Skill bonus"], bonus) end
    return lines
  end
  if entry.kind == "vzone" then
    lines[1] = format("%s: %d", L["Vendors"], entry.subCount or 0)
    for _, n in ipairs(A.GetNPCs()) do
      if (n.map or 0) == entry.id then lines[#lines + 1] = (n.name or ("#" .. n.id)) .. " (" .. (n.trainer and L["Fishing teacher"] or L["Fishing vendor"]) .. ")" end
    end
    return lines
  end
  if entry.kind == "npc" then
    local n = entry.npc
    if not n then return {L["Select an entry on the left page."]} end
    lines[1] = n.trainer and L["Fishing teacher"] or L["Fishing vendor"]
    local place = n.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(n.map)
    local where = place and place.name or (n.details and n.details.zoneText) or ""
    if n.x and n.y then where = format("%s  |cffffd100[%.1f, %.1f]|r", where, n.x * 100, n.y * 100) end
    lines[2] = where
    if n.details and n.details.title then lines[#lines + 1] = n.details.title end
    local cats = {{"pole", "Fishing poles"}, {"bobber", "Oversized bobber"}, {"lure", "Lures"}, {"recipe", "Recipes"}, {"fish", "Fish"}, {"other", "Other"}}
    for _, cat in ipairs(cats) do
      local names = {}
      for itemID, c in pairs(n.items or {}) do if c == cat[1] then names[#names + 1] = itemName(itemID) .. vendorPrice(n, itemID) .. ((c == "recipe" and BJ.DB:RecipeKnown(itemID)) and " |TInterface\\RaidFrame\\ReadyCheck-Ready:14|t" or "") end end
      if #names > 0 then
        table.sort(names)
        lines[#lines + 1] = ""
        lines[#lines + 1] = L[cat[2]]
        for _, name in ipairs(names) do lines[#lines + 1] = name end
      end
    end
    -- what the character lacks to buy an item (reputation, level ...): red lines under the list
    local needs = {}
    for itemID, o in pairs(n.offers or {}) do
      local missing = ns.Prices.Needs(o)
      if #missing > 0 then needs[#needs + 1] = itemName(itemID) .. ": |cffff6060" .. table.concat(missing, "; ") .. "|r" end
    end
    if #needs > 0 then
      table.sort(needs)
      lines[#lines + 1] = ""
      lines[#lines + 1] = L["Requirements"]
      for _, l in ipairs(needs) do lines[#lines + 1] = l end
    end
    if n.lessons and #n.lessons > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = L["Teaches"]
      for _, l in ipairs(n.lessons) do lines[#lines + 1] = ns.Prices.LessonText(l) end
    end
    if n.repair then lines[#lines + 1] = "" lines[#lines + 1] = L["Repairs equipment"] end
    return lines
  end
  if entry.kind == "subzone" then
    -- like a zone: the fish are unfolded in the list, the map shows the area
    lines[1] = format(L["Catches: %d"], entry.sub or 0)
    return lines
  end
  if entry.kind == "fish" then
    lines[1] = format(L["Caught: %d"], A.GetCaught(entry.id)) .. "   " .. (A.IsConfirmed("fish", entry.id) and L["Confirmed"] or L["Rumour"])
    lines[2] = A.ItemCategory(entry.id) == "material" and ("|cff999999" .. L["Crafting materials & others"] .. "|r") or ""
    lines[3] = L["Where to catch it"]
    for _, z in ipairs(A.GetFishZones(entry.id)) do
      lines[#lines + 1] = format("%s  %s", A.GetZoneName(z.zone), ns.Format.Value(z.drops, z.chance, true))
    end
    -- stock and the value per hour: the same sections as on the diary pages
    for _, section in ipairs(BJ.modules.Tooltip and BJ.modules.Tooltip.FishSections(entry.id) or {}) do
      lines[#lines + 1] = ""
      lines[#lines + 1] = section[1]
      for _, l in ipairs(section[2]) do lines[#lines + 1] = l end
    end
    local recipes = A.GetFishRecipes(entry.id)
    if #recipes > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = L["Used in recipes:"]
      for _, r in ipairs(recipes) do lines[#lines + 1] = r.name end
    end
  else
    lines[1] = format(L["Catches: %d"], A.GetZoneCatches(entry.id))
    lines[2] = format(L["Fishing spots: %d"], #A.GetZoneSpots(entry.id))
  end
  return lines
end

-- Lines of the item's own game tooltip (name, type, flavour text, price ...), as the game delivers them.
-- C_TooltipInfo where the client has it, else a hidden tooltip of our own. Values that are secret count as missing.
local scanTip
local function blizzardItemLines(id)
  local out = {}
  local function add(left, right, r, g, b)
    left, right = BJ.Clean(left), BJ.Clean(right)
    if type(left) ~= "string" then left = nil end
    if type(right) ~= "string" then right = nil end
    if (left and left ~= "") or (right and right ~= "") then
      out[#out + 1] = {left = left, right = right, r = tonumber(BJ.Clean(r)) or 1, g = tonumber(BJ.Clean(g)) or 1, b = tonumber(BJ.Clean(b)) or 1}
    end
  end
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, line in ipairs(data.lines) do
        local c = line.leftColor
        add(line.leftText, line.rightText, c and c.r, c and c.g, c and c.b)
      end
      return out
    end
  end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "BobbersJournalScanTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  if pcall(scanTip.SetItemByID, scanTip, id) then
    for i = 1, scanTip:NumLines() do
      local left, right = _G["BobbersJournalScanTipTextLeft" .. i], _G["BobbersJournalScanTipTextRight" .. i]
      local r, g, b -- (an "and" would cut g and b off)
      if left then r, g, b = left:GetTextColor() end
      add(left and left:GetText(), right and right:GetText(), r, g, b)
    end
  end
  return out
end

-- Printed look: dark brown ink instead of the game's light text; the game's own colours (item lines) are darkened so
-- they stay readable and recognisable on the parchment.
local SEPIA_LIGHT = {0.46, 0.32, 0.18}
local SEPIA_MAIN = {0.33, 0.22, 0.12} -- main text of the item page: darker than light sepia, lighter than the title
local INK_TEXT, INK_HEAD = {0.20, 0.12, 0.06}, {0.06, 0.30, 0.30}
local function darken(r, g, b)
  local f = 0.55
  return r * f, g * f, b * f
end
local function colored(text, r, g, b)
  r, g, b = darken(r, g, b)
  return ns.Colors.Wrap(r, g, b, text)
end
local function plain(text) return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Rows of the right page: {text=..., right=...} or {header=...}; `beside` rows stand next to the big icon.
local BODY_X, BODY_W, ICON_SIZE, LINE_H = 40, 400, 96, 16
local PAGE_BASE = 25 -- the content of the right page starts this far lower
local FAV_H = 230 -- height of the settings block of the Lures page (right page)
local function pageDY() return PAGE_BASE end

local function detailRow(i)
  local row = frame.detailRows[i]
  if row then return row end
  row = {}
  row.left = frame.page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.left:SetJustifyH("LEFT")
  row.right = frame.page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.right:SetJustifyH("RIGHT")
  for _, fs in ipairs({row.left, row.right}) do fs:SetShadowOffset(0, 0) fs:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3], 1) end
  row.rule = frame.page:CreateTexture(nil, "ARTWORK")
  row.rule:SetColorTexture(INK_HEAD[1], INK_HEAD[2], INK_HEAD[3], 0.75)
  row.rule:SetHeight(1)
  frame.detailRows[i] = row
  return row
end

local function layoutDetail(rows, beside, hasIcon, titleH)
  local book = frame.book
  local y = hasIcon and -(80 + pageDY() + ICON_SIZE + 18) or -(130 + pageDY() + 12)
  local count = 0
  local besideY = -(80 + pageDY() + math.max(30, (titleH or 0) + 10)) -- below the title, also when it has two lines -- next free spot beside the icon (rows there wrap, so heights are measured)
  for i, entry in ipairs(rows) do
    local row = detailRow(i)
    local x, top = BODY_X + (hasIcon and 0 or 24), y -- pages without a big icon (zone): counters a bit to the right
    if entry.flush then x = BODY_X end -- a heading that starts at the left edge of the page like "Sold"
    if i <= beside then
      x = BODY_X + ICON_SIZE + 14
      top = besideY
    else
      if entry.header and i > 1 then y = y - 8 top = y end
      if entry.gap then y = y + entry.gap top = y end -- extra space before the row (negative = closer to the row above)
    end
    local width = BODY_W - (x - BODY_X)
    if i <= beside then width = width - 10 end -- text beside the icon ends 10 px earlier
    row.left:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", book, "TOP", x, top)
    if entry.header then
      row.left:SetText(plain(entry.header))
      row.left:SetTextColor(INK_HEAD[1], INK_HEAD[2], INK_HEAD[3], 1)
    else
      row.left:SetText(entry.keep and (entry.text or "") or plain(entry.text))
      row.left:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3], 1)
    end
    row.left:SetWidth(entry.right and width * 0.62 or width)
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", book, "TOP", BODY_X + BODY_W, top)
    row.right:SetText(plain(entry.right))
    row.left:Show() row.right:Show()
    row.rule:ClearAllPoints()
    if entry.header then
      row.rule:SetPoint("LEFT", row.left, "RIGHT", 8, 0)
      row.rule:SetPoint("RIGHT", book, "TOP", BODY_X + BODY_W - (entry.short and (MODEL_W + 14) or 0), 0) -- (short: ends before the model)
      row.rule:SetPoint("TOP", row.left, "TOP", 0, -8)
      row.rule:Show()
    else
      row.rule:Hide()
    end
    local h = math.max(LINE_H, row.left:GetStringHeight() or LINE_H, row.right:GetStringHeight() or LINE_H)
    if i <= beside then
      besideY = top - h - 2
      -- the rows below start under the icon or under the last row beside it, whichever is lower
      if i == beside then y = math.min(y, besideY - 10) end
    else
      y = top - h - (entry.header and 2 or 0)
    end
    count = i
  end
  for i = count + 1, #frame.detailRows do
    local row = frame.detailRows[i]
    row.left:Hide() row.right:Hide() row.rule:Hide()
  end
  return y -- the next free spot (negative, below the book top)
end

--- Builds the right page of an entry: title, icon and rows.
local function buildDetail(sel, fallbackLines)
  local rows, beside, title, color = {}, 0, nil, nil
  if sel and sel.kind == "fish" then
    local lines = blizzardItemLines(sel.id)
    if #lines > 0 then
      title, color = lines[1].left, {lines[1].r, lines[1].g, lines[1].b}
      for i = 2, #lines do
        local l = lines[i]
        -- Item type line (blue in the game, e.g. crafting material) keeps its colour, darkened; the rest is light sepia.
        local blue = l.b > l.r + 0.25 and l.b > l.g
        local text = l.left
        if text then
          if blue then text = colored(text, l.r, l.g, l.b)
          else text = colored(plain(text), SEPIA_MAIN[1] / 0.55, SEPIA_MAIN[2] / 0.55, SEPIA_MAIN[3] / 0.55) end
        end
        rows[#rows + 1] = {text = text or "", right = l.right, keep = true}
      end
      beside = math.min(#rows, 5)
    end
    local T = BJ.modules.Tooltip
    if T and T.ItemLines then
      for _, l in ipairs(T.ItemLines(sel.id, true)) do
        if l.header then rows[#rows + 1] = {header = l.header}
        else rows[#rows + 1] = {text = l[1], right = l[2]} end
      end
    end
  end
  if sel and sel.kind == "lure" and sel.itemID then
    -- description of the lure item (tooltip lines after the name), light sepia like the fish pages, then the statistics
    local lines = blizzardItemLines(sel.itemID)
    for i = 2, #lines do
      local l = lines[i]
      if l.left and l.left ~= "" then
        rows[#rows + 1] = {text = colored(plain(l.left), SEPIA_MAIN[1] / 0.55, SEPIA_MAIN[2] / 0.55, SEPIA_MAIN[3] / 0.55), right = l.right, keep = true}
      end
    end
    beside = math.min(#rows, 5)
    if #rows > 0 then rows[#rows + 1] = {text = ""} end
    for _, l in ipairs(fallbackLines) do rows[#rows + 1] = {text = l} end
  end
  if #rows == 0 then
    for _, l in ipairs(fallbackLines) do rows[#rows + 1] = {text = l} end
  end
  if sel and sel.kind == "subzone" then title = (sel.zoneName or "") .. " - " .. sel.text end -- zone - sub zone
  return rows, beside, title, color
end

local function pageText(pages)
  local n = #pages
  if not state.selected or n < 2 then return "" end
  local i = state.rpage or 1
  return format("%s  %s", L[PAGE_LABEL[pages[i]] or "Info"], format(L["Page %d/%d"], i, n))
end

-- ---- right page contents -------------------------------------------------------------------------------------------

local function placeOf(n)
  local place = n.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(n.map)
  local where = place and place.name or (n.details and n.details.zoneText) or ""
  if n.x and n.y then where = format("%s  |cffffd100[%.1f, %.1f]|r", where, n.x * 100, n.y * 100) end
  return where
end

--- Map page of a fish: the zone where it was caught most often, only its spots.
local function fishMapRows(sel)
  local A = BJ.API
  local zones = A.GetFishZones(sel.id)
  if #zones == 0 then return {{text = L["No catches yet, so there is no map."]}}, nil end
  local z = zones[1]
  return {{text = format(L["Most caught in: %s"], A.GetZoneName(z.zone)), right = tostring(z.drops)}}, z.zone
end

--- Sales page of a fish or a lure: prices, stock, recipes (fish) or vendors (lures); the price chart goes below the rows.
local function salesRows(sel)
  local A, P, T = BJ.API, ns.Prices, BJ.modules.Tooltip
  local itemID = sel.kind == "lure" and sel.itemID or sel.id
  if not itemID then return {{text = L["No item data for this entry."]}}, nil end
  local rows = {}
  local vendor = P.Vendor(itemID)
  rows[#rows + 1] = {text = L["Vendor price"], right = vendor and P.Money(vendor) or "-"}
  if P.HasAuctionAddon() then
    local price, source
    price, source = P.Auction(itemID)
    rows[#rows + 1] = {text = source and format(L["Auction price (%s)"], source) or L["Auction price"], right = price and P.Money(price) or "-"}
    if price and ns.PriceHistory then ns.PriceHistory.Record(itemID) end
    local stamp, exact = P.AuctionStamp(itemID)
    if price and stamp then
      rows[#rows + 1] = {text = exact and L["Last scan"] or L["Price first seen"], right = date("%d.%m.%Y", stamp)}
    end
  end
  for _, sec in ipairs(T and T.FishSections(itemID) or {}) do
    if sec.key == "stock" or sec.key == "value" then
      rows[#rows + 1] = {header = sec[1]}
      for i, l in ipairs(sec[2]) do
        if not (sec.key == "value" and i == 1) then rows[#rows + 1] = {text = l} end -- (the counted quantity is not repeated)
      end
    end
  end
  if sel.kind == "fish" then
    local recipes = A.GetFishRecipes(itemID)
    if #recipes > 0 then
      rows[#rows + 1] = {header = L["Used in recipes:"]}
      for i = 1, math.min(#recipes, 3) do rows[#rows + 1] = {text = recipes[i].name} end
      if #recipes > 3 then rows[#rows + 1] = {text = format(L["%d more"], #recipes - 3)} end
    end
  else
    local sellers = {}
    for _, n in ipairs(A.GetNPCs()) do
      if n.items and n.items[itemID] then
        local offer = n.offers and n.offers[itemID]
        sellers[#sellers + 1] = {text = n.name or ("#" .. n.id), right = offer and P.OfferText(offer) or ""}
      end
    end
    if #sellers > 0 then
      table.sort(sellers, function(x, y) return x.text < y.text end)
      rows[#rows + 1] = {header = L["Sold by"]}
      for i = 1, math.min(#sellers, 5) do rows[#rows + 1] = sellers[i] end
      if #sellers > 5 then rows[#rows + 1] = {text = format(L["%d more"], #sellers - 5)} end
    end
  end
  return rows, itemID
end

--- rows, beside, title, colour and extras (fishZone, chartItem, vendor) for the page `mode` of the selected entry
local function buildPage(sel, mode, lines)
  if not sel then return buildDetail(sel, lines) end
  local k = sel.kind
  if k == "fish" and mode == "map" then
    local rows, zone = fishMapRows(sel)
    return rows, 0, nil, nil, {fishZone = zone}
  elseif (k == "fish" or k == "lure") and mode == "sales" then
    local rows, item = salesRows(sel)
    return rows, 0, nil, nil, {chartItem = item}
  elseif k == "npc" and sel.npc then
    local n = sel.npc
    -- under the name: the title the NPC has (e.g. "(Fishing Supplies)"), then vendor or teacher, then the place; the
    -- coordinates carry their colour (keep) like everywhere else in the addon
    local rows = {}
    local hasTitle = mode == "info" and n.details and n.details.title
    -- "(Title)" hangs directly under the name, then a gap before vendor/teacher and the place
    if hasTitle then rows[#rows + 1] = {text = "(" .. n.details.title .. ")", gap = 24} end
    -- vendor / teacher as a heading like "Sold": same colour and indent, the line stops before the model
    rows[#rows + 1] = {header = n.trainer and L["Fishing teacher"] or L["Fishing vendor"], flush = true, short = true, gap = hasTitle and -10 or nil}
    rows[#rows + 1] = {text = placeOf(n), keep = true}
    return rows, 0, sel.text, nil, mode == "info" and {vendor = n} or {}
  elseif k == "zone" or k == "subzone" then
    local _, _, title = buildDetail(sel, lines)
    return {}, 0, title, nil, {}
  end
  return buildDetail(sel, lines)
end

local function selectTabs()
  for _, tab in ipairs(frame.tabs) do tab:Select(tab.key == state.tab) end
end

-- Corner page-curl of the book (flip book animation like the spell book): curls while the mouse is on a paging
-- button, plays once when a page is turned.
local function curl(reverse)
  if frame.curl then frame.curl.anim:Play(reverse and true or false) end
end

local function turn(delta)
  local pages = pagesOf(state.selected)
  if #pages < 2 then return end
  state.rpage = math.min(math.max((state.rpage or 1) + delta, 1), #pages)
  pageSound()
  curl(false)
  M.Refresh()
end

local function refresh()
  if not (frame and frame:IsShown()) then return end
  -- Lures: sub tab "Settings" shows the favourite lure and the options on the RIGHT page; the list stays on the left
  local settingsMode = state.tab == "lures" and state.sub == "settings"
  local entries = buildEntries()
  local unfiltered = entries -- before the "collected only" filter (for the statistic)
  if BJ.settings.journalFilter == "collected" then
    -- only what was caught / used / owned: the grey "not yet" entries drop out
    local kept = {}
    for _, e in ipairs(entries) do if not e.unseen then kept[#kept + 1] = e end end
    entries = kept
  end
  state.entries = entries
  -- Every entry has its own page: the selected entry decides the page number.
  -- Grid tabs (fish, junk, lures): the LEFT page turns through the list (PER_PAGE entries per page, state.offset = page
  -- index from 0); the RIGHT page turns only through the entries of the current left page.
  local grid = GRID[state.tab] == true
  local per = COLS * GRID_ROWS
  state.page = nil
  local found, foundIndex
  if state.selected then
    for i, e in ipairs(entries) do
      if e.kind == state.selected.kind and e.id == state.selected.id then found, foundIndex = e, i break end
    end
    state.selected = found
  end
  state.pageList = entries
  if grid then
    local pages = math.max(math.ceil(#entries / per), 1)
    if foundIndex then state.offset = math.floor((foundIndex - 1) / per) end
    state.offset = math.max(math.min(state.offset, pages - 1), 0)
    state.leftPages = pages
    state.pageList = {}
    for i = state.offset * per + 1, math.min(state.offset * per + per, #entries) do state.pageList[#state.pageList + 1] = entries[i] end
  end
  if found then
    for i, e in ipairs(state.pageList) do if e == found then state.page = i break end end
  end
  -- Visible list rows: the entries; under a selected zone its fish are unfolded (accordion, one zone at a time).
  local map = BJ.modules.ZoneMap
  local visible, selIndex = {}, nil
  local lastRegion, regionFolded
  local fo, searching = fold(), state.search ~= ""
  local selEntry = state.selected
  for _, e in ipairs(entries) do
    if e.region and e.region ~= lastRegion then
      lastRegion = e.region
      regionFolded = not searching and fo.regions[e.region] == true
      visible[#visible + 1] = {kind = "region", text = e.region, folded = regionFolded}
    end
    local hidden = e.region and regionFolded
    if e.kind == "zone" or e.kind == "subzone" then
      local zoneId = e.kind == "zone" and e.id or e.zone
      -- sub zones are shown while searching, when their zone is opened, or when the zone or one of them is selected
      local open = searching or fo.zones[zoneId] == true
        or (selEntry and ((selEntry.kind == "zone" and selEntry.id == zoneId) or (selEntry.kind == "subzone" and selEntry.zone == zoneId)))
      if e.kind == "zone" then e.expanded = open and true or false end
      if e.kind == "subzone" and not open then hidden = true end
    end
    if (e.kind == "vzone" or e.kind == "npc") and state.tab == "vendors" then
      local zoneId = e.kind == "vzone" and e.id or e.zone
      local open = searching or fo.zones["v" .. zoneId] == true
        or (selEntry and ((selEntry.kind == "vzone" and selEntry.id == zoneId) or (selEntry.kind == "npc" and selEntry.zone == zoneId)))
      if e.kind == "vzone" then e.expanded = open and true or false end
      if e.kind == "npc" and not open then hidden = true end
    end
    if not hidden then
    visible[#visible + 1] = e
    local selZone = state.selected and state.selected.kind == "zone" and e.kind == "zone" and e.id == state.selected.id
    local selSub = state.selected and state.selected.kind == "subzone" and e.kind == "subzone" and e.id == state.selected.id
    if selZone or selSub then
      selIndex = #visible
      if map then
        map.SetZone(selSub and e.zone or e.id)
        map.SetSubZone(selSub and e.subName or nil)
      end
      local fishList = selSub and BJ.API.GetSubZoneFish(e.zone, e.subName) or BJ.API.GetZoneFish(e.id)
      for _, f in ipairs(fishList) do
        if not BJ.API.IsJunk(f.itemID) then
          visible[#visible + 1] = {kind = "zonefish", id = f.itemID, text = itemName(f.itemID), icon = itemIcon(f.itemID),
            sub = ns.Format.Percent(f.chance, true), zone = selSub and e.zone or e.id}
        end
      end
    end
    end
  end
  if state.selected and not selIndex then
    for i, e in ipairs(visible) do if e.kind == state.selected.kind and e.id == state.selected.id then selIndex = i break end end
  end
  -- keep the selected entry visible
  if not grid then
    if selIndex and not state.free then
      if selIndex <= state.offset then state.offset = selIndex - 1
      elseif selIndex > state.offset + ROWS then state.offset = selIndex - ROWS end
    end
    local maxOffset = math.max(#visible - ROWS, 0)
    state.offset = math.max(math.min(state.offset, maxOffset), 0)
  end

  frame.list:SetHeight(grid and GRID_ROWS * CELL_H or ROWS * ROW_H)
  -- Statistic of the fish tab: fish species caught / species in the list (independent of search and filter)
  if state.tab == "fish" then
    local all, caught = unfiltered, 0
    if state.search ~= "" then -- while searching the list is cut: count the whole list separately
      local keep = state.search
      state.search = ""
      all = buildEntries()
      state.search = keep
    end
    for _, e in ipairs(all) do if not e.unseen then caught = caught + 1 end end
    frame.stat:SetText(format(L["Fish species caught: %d/%d"], caught, #all))
    frame.stat:Show()
  else
    frame.stat:Hide()
  end
  -- left page turning (grid tabs only)
  frame.lprev:Show() frame.lnext:Show() frame.lpageText:Show()
  if grid then
    frame.lpageText:SetText(format(L["Page %d/%d"], state.offset + 1, state.leftPages))
    frame.lprev:SetEnabled(state.offset > 0)
    frame.lnext:SetEnabled(state.offset + 1 < state.leftPages)
  else
    -- lists (zones, vendors, bookmarks): one page = the rows that fit
    local pagesN = math.max(math.ceil(#visible / ROWS), 1)
    state.maxOffset = math.max(#visible - ROWS, 0)
    frame.lpageText:SetText(format(L["Page %d/%d"], math.min(math.floor(state.offset / ROWS) + 1, pagesN), pagesN))
    frame.lprev:SetEnabled(state.offset > 0)
    frame.lnext:SetEnabled(state.offset < state.maxOffset)
  end
  local appliedLure = state.tab == "lures" and BJ.modules.Lures and BJ.modules.Lures.Current and (BJ.modules.Lures.Current()) or nil
  for i, cell in ipairs(frame.cells) do
    local e = grid and entries[state.offset * per + i]
    if e then
      cell.entry = e
      cell.icon:SetTexture(e.icon)
      cell.text:SetText(e.text)
      local unseen = e.unseen == true
      cell.icon:SetDesaturated(unseen)
      cell.icon:SetAlpha(unseen and 0.5 or 1)
      cell.frameTex:SetDesaturated(unseen)
      cell.frameTex:SetVertexColor(unseen and 0.55 or 0.80, unseen and 0.42 or 0.58, unseen and 0.28 or 0.25)
      cell.frameTex:SetAlpha(unseen and 0.55 or 1)
      -- printed ink on the parchment: petrol like the headings, light sepia when not seen yet
      if unseen then cell.text:SetTextColor(SEPIA_LIGHT[1], SEPIA_LIGHT[2], SEPIA_LIGHT[3], 0.75)
      else cell.text:SetTextColor(INK_HEAD[1], INK_HEAD[2], INK_HEAD[3], 1) end
      cell.sel:SetShown(state.selected == e)
      cell.mark:SetShown(e.kind == "fish" and BJ.API.IsBookmarked("fish", e.id))
      -- lures in the bags: original bag look (slot background, stack count)
      local inBag = e.kind == "lure" and e.count ~= nil
      cell.slotBack:SetShown(inBag)
      -- same original frame for all, only the colour tells the state: bags = bright aqua, used = gold, unseen = grey
      -- applied to the pole right now = gold (wins over the others)
      local active = e.kind == "lure" and e.itemID ~= nil and e.itemID == appliedLure
      if active then cell.frameTex:SetDesaturated(false) cell.frameTex:SetVertexColor(1, 0.82, 0) cell.frameTex:SetAlpha(1)
      elseif inBag then cell.frameTex:SetVertexColor(0.25, 0.9, 0.2) cell.frameTex:SetAlpha(1) end
      -- fishing skill too low for the lure in the bags: red frame and red name
      -- lure names are green on the parchment (dark green), not seen yet stays light sepia
      -- names carry the colour of the item quality (fish, junk, lures)
      local qid = e.kind == "lure" and e.itemID or (e.kind == "fish" and e.id) or nil
      local qr, qg, qb
      if qid then qr, qg, qb = qualityInk(qid) end -- (an "and" would cut the 3 values to 1)
      if qr and not unseen then cell.text:SetTextColor(qr, qg, qb, 1) end
      if e.locked then
        cell.frameTex:SetDesaturated(false) cell.frameTex:SetVertexColor(0.9, 0.12, 0.12) cell.frameTex:SetAlpha(1)
        cell.text:SetTextColor(0.75, 0.1, 0.1, 1)
      end
      cell.hook:SetShown(e.kind == "lure" and e.itemID ~= nil and e.itemID == BJ.settings.cast.favoriteLure)
      cell.count:SetShown(inBag and e.count > 1)
      if inBag then cell.count:SetText(e.count) cell.icon:SetAlpha(1) cell.icon:SetDesaturated(false) end
      cell:Show()
    else
      cell:Hide()
    end
  end
  for i, row in ipairs(frame.rows) do
    local e = (not grid) and visible[state.offset + i]
    row.entry = e
    if e then
      local fishRow = e.kind == "zonefish"
      local regionRow = e.kind == "region"
      local on = fishRow and map and map.IsSelected(e.id)
      row.text:SetText(e.text)
      row.text:ClearAllPoints()
      row.icon:ClearAllPoints()
      row.icon:SetShown(not fishRow and not regionRow)
      row.stamp:SetShown(fishRow)
      row.ring:SetShown(fishRow)
      row.toggle:Hide() row.line:Hide()
      if regionRow then
        row.toggle:ClearAllPoints()
        row.toggle:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.toggle:SetNormalTexture(e.folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        row.toggle:Show()
        row.line:Show()
        row.text:SetPoint("LEFT", row, "LEFT", 24, 0)
        row.text:SetFontObject("GameFontHighlight")
        row.text:SetTextColor(ns.Colors.aqua[1], ns.Colors.aqua[2], ns.Colors.aqua[3])
      elseif fishRow then
        -- ink stamp: round, dark and slightly transparent; chosen fish stay in colour
        row.stamp:SetTexture(e.icon)
        row.stamp:SetDesaturated(not on)
        if on then row.stamp:SetVertexColor(1, 1, 1) row.stamp:SetAlpha(1) else row.stamp:SetVertexColor(0.30, 0.28, 0.26) row.stamp:SetAlpha(0.85) end
        row.ring:SetVertexColor(0.04, 0.03, 0.03)
        row.ring:SetAlpha(on and 1 or 0.8)
        row.text:SetPoint("LEFT", row, "LEFT", 62, 0)
        row.text:SetFontObject("GameFontNormalSmall") -- fish stay smaller than zones and sub zones
        local qr, qg, qb = qualityInk(e.id)
        if qr then row.text:SetTextColor(qr, qg, qb)
        elseif on then row.text:SetTextColor(1, 1, 1) else row.text:SetTextColor(1, 0.82, 0) end
      else
        row.icon:SetPoint("LEFT", row, "LEFT", 4 + (e.region and 16 or 0), 0)
        row.icon:SetTexture(e.icon)
        if e.kind == "subzone" or (e.kind == "npc" and not e.flat) then
          -- sub zone / NPC: indented under its zone, no icon
          row.icon:SetShown(false)
          row.text:SetPoint("LEFT", row, "LEFT", 64, 0)
          row.text:SetFontObject("GameFontNormal") -- as large as the zone
          row.text:SetText(e.text)
          row.text:SetTextColor(0.85, 0.7, 0.2)
        else
          if (e.kind == "zone" or e.kind == "vzone") and (e.subCount or 0) > 0 then
            row.toggle:ClearAllPoints()
            row.toggle:SetPoint("LEFT", row, "LEFT", 4 + (e.region and 16 or 0), 0)
            row.toggle:SetNormalTexture(e.expanded and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            row.toggle:Show()
          end
          row.text:SetPoint("LEFT", row.icon, "RIGHT", e.region and 12 or 6, 0)
          row.text:SetFontObject("GameFontNormal")
          row.text:SetTextColor(1, 0.82, 0)
        end
      end
      row.sub:SetText(e.sub or "")
      row.mark:SetShown(not fishRow and not regionRow and e.kind ~= "subzone" and BJ.API.IsBookmarked(e.kind, e.id))
      row.sub:SetShown(not regionRow)
      row.sel:SetShown(state.selected and state.selected.kind == e.kind and state.selected.id == e.id or (on and true or false))
      row:Show()
    else
      row:Hide()
    end
  end

  local lines
  if state.tab == "vendors" and #entries == 0 and state.search == "" then
    lines = {L["No vendors or teachers saved yet. Talk to a fishing vendor or teacher."]}
  elseif #entries == 0 and state.search == "" and state.tab ~= "bookmarks" then
    lines = {L["No data yet. Go fishing!"]}
  else
    lines = detailLines(state.selected)
  end
  local sel = state.selected
  local pages = pagesOf(sel)
  local pageKey = sel and (sel.kind .. ":" .. tostring(sel.id)) or ""
  if state.rpageKey ~= pageKey then state.rpageKey, state.rpage = pageKey, 1 end
  if (state.rpage or 1) > #pages then state.rpage = 1 end
  local mode = pages[state.rpage or 1]
  local rows, beside, title, _, extra = buildPage(sel, mode, lines)
  extra = extra or {}
  local hasIcon = sel ~= nil and sel.icon ~= nil and mode == "info" and sel.kind ~= "npc"
  -- Nothing selected: one larger message in the middle of the right page instead of rows.
  local empty = sel == nil
  frame.emptyText:SetShown(empty and not settingsMode)
  if empty then frame.emptyText:SetText(lines[1] or "") rows = {} end
  local titleH = 0
  if sel then
    frame.title:SetText(title or sel.text)
    titleH = tonumber(frame.title:GetStringHeight()) or 0
  end
  local nextY = layoutDetail(rows, beside, hasIcon, titleH)
  -- map page: zones and sub zones; the zone of a fish with only that fish; the vendors of a zone
  if map then
    if extra.fishZone then
      BJ.Protected("fish map", function()
        map.SetZone(extra.fishZone)
        map.Only(sel.id)
        map.Show(frame.book, extra.fishZone, nextY - 10)
      end)
      state.fishMap = true
    else
      if state.fishMap then map.Clear() state.fishMap = nil end
      if sel and (sel.kind == "vzone" or (sel.kind == "npc" and mode == "map")) then
        -- vendors tab: the map of the zone with its vendors and teachers
        local zoneId = sel.kind == "vzone" and sel.id or sel.zone
        local list = {}
        for _, n in ipairs(BJ.API.GetNPCs()) do if (n.map or 0) == zoneId then list[#list + 1] = n end end
        BJ.Protected("npc map", function() map.ShowNPCs(frame.book, zoneId, -(130 + pageDY() + 12 + #rows * LINE_H + 14), list, sel.kind == "npc" and sel.id or nil) end)
      elseif sel and (sel.kind == "zone" or sel.kind == "subzone") then
        BJ.Protected("zone map", function() map.Show(frame.book, sel.kind == "subzone" and sel.zone or sel.id, -(130 + pageDY() + 12 + 14)) end)
      else
        map.Hide()
      end
    end
  end
  -- sales page: price chart below the rows (only with a price addon)
  local chartModule = BJ.modules.PriceChart
  if extra.chartItem and chartModule and ns.Prices.HasAuctionAddon() then
    BJ.Protected("price chart", function()
      if not frame.chart then frame.chart = chartModule.Create(frame.page) end
      frame.chart:ClearAllPoints()
      frame.chart:SetPoint("TOPLEFT", frame.book, "TOP", BODY_X, nextY - 8)
      chartModule.Draw(frame.chart, extra.chartItem)
      frame.chart:Show()
    end)
  elseif frame.chart then
    frame.chart:Hide()
  end
  -- vendor page: model of the NPC and what it sells as icons
  if extra.vendor then
    BJ.Protected("vendor page", function() M.FillVendor(extra.vendor) end)
  elseif frame.vendor then
    frame.vendor:Hide()
  end
  frame.bookmark:SetShown(sel ~= nil and sel.kind ~= "vzone")
  frame.title:ClearAllPoints()
  frame.pageIcon:ClearAllPoints()
  frame.pageIcon:SetPoint("TOPLEFT", frame.book, "TOP", 16, -90)
  M.UpdateFavorite()
  if sel then
    frame.bookmark:SetText(BJ.API.IsBookmarked(sel.kind, sel.id) and L["Remove bookmark"] or L["Add bookmark"])
    frame.title:SetText(title or sel.text)
    local c = INK_TEXT -- same colour as the title of the zone pages
    frame.title:SetTextColor(c[1], c[2], c[3])
    frame.title:SetShadowOffset(0, 0)
    frame.pageIcon:SetTexture(sel.icon)
    frame.pageIcon:SetDesaturated(true)
    frame.pageIcon:SetVertexColor(1, 0.74, 0.45)
    frame.pageIcon:SetAlpha(0.6)
    frame.pageIcon:SetShown(hasIcon)
    -- the picture is twice the layout size (it may disappear behind the text), so the title does not hang on it
    if hasIcon then frame.title:SetPoint("TOPLEFT", frame.book, "TOP", BODY_X + ICON_SIZE + 14, -(80 + pageDY() + 2))
    else frame.title:SetPoint("TOPLEFT", frame.book, "TOP", BODY_X + 24, -(85 + pageDY() + 12)) end
  else
    frame.title:SetText("")
    frame.pageIcon:Hide()
    frame.title:SetPoint("TOPLEFT", frame.book, "TOP", BODY_X, -(85 + pageDY()))
  end
  selectTabs()
  frame.pageText:SetText(pageText(pages))
  frame.prev:SetEnabled((state.rpage or 1) > 1)
  frame.next:SetEnabled((state.rpage or 1) < #pages)
  -- page tabs below the right page (fish)
  for i, t in ipairs(frame.pageTabs) do
    local show = sel ~= nil and #pages > 1 and i <= #pages and not settingsMode
    if show then
      t.text:SetText(L[PAGE_LABEL[pages[i]] or "Info"])
      t:SetWidth((t.text:GetStringWidth() or 60) + 44)
      t:SetActive(i == (state.rpage or 1))
    end
    t:SetShown(show)
  end
  local ttn = sel and sel.kind == "npc" and sel.npc
  frame.tomtom:SetShown(ttn and ttn.map and ttn.x and ttn.y and _G.TomTom and _G.TomTom.AddWaypoint and true or false)
  local turnable = sel ~= nil and #pages > 1 and not settingsMode
  frame.prev:SetShown(turnable) frame.next:SetShown(turnable) frame.pageText:SetShown(turnable)
  frame.bookmark:SetShown(frame.bookmark:IsShown() and not settingsMode)
  M.UpdateSubTabs()
end
M.Refresh = refresh
M.DetailLines = detailLines -- (for the smoke test)

--- Shows or hides the settings block of the Lures page (favourite lure, options) and fills it.
function M.UpdateFavorite()
  if not (frame and frame.fav) then return end
  local show = state.tab == "lures" and state.sub == "settings"
  frame.fav:SetShown(show)
  if not show then return end
  frame.fav.auto:SetChecked(BJ.settings.cast.autoLure == true)
  frame.fav.best:SetChecked(BJ.settings.cast.autoBest ~= false)
  local id = BJ.settings and BJ.settings.cast and BJ.settings.cast.favoriteLure
  if id then
    frame.fav.slot.icon:SetTexture(itemIcon(id))
    frame.fav.name:SetText(itemName(id))
    local qr, qg, qb = qualityInk(id)
    if qr then frame.fav.name:SetTextColor(qr, qg, qb) end
  else
    frame.fav.slot.icon:SetTexture(nil)
    frame.fav.name:SetText(L["No favorite lure set"])
    frame.fav.name:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3])
  end
end

--- Sub tabs on top of the book (Lures: overview / settings), like the category tabs of the spell book.
function M.UpdateSubTabs()
  if not (frame and frame.subTabs) then return end
  local show = state.tab == "lures"
  for _, t in ipairs(frame.subTabs) do
    t:SetShown(show)
    t:SetActive(t.key == state.sub)
  end
end

-- Every tab remembers its last selected entry; coming back to the tab selects it again (refresh looks it up by kind and id).
local lastSelected = {}

local function setTab(key)
  if state.selected then lastSelected[state.tab] = {kind = state.selected.kind, id = state.selected.id} end
  state.tab, state.offset, state.free = key, 0, nil
  state.selected = lastSelected[key]
  state.sub = "overview"
  refresh()
end

local function createRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(380, ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  row.sel:SetColorTexture(ns.Colors.aqua[1], ns.Colors.aqua[2], ns.Colors.aqua[3], 0.25)
  row.sel:Hide()
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(22, 22)
  row.icon:SetPoint("LEFT", 4, 0)
  -- round stamp for the fish unfolded under a zone
  row.stamp = row:CreateTexture(nil, "ARTWORK")
  row.stamp:SetSize(22, 22)
  row.stamp:SetPoint("LEFT", 32, 0)
  local mask = row:CreateMaskTexture()
  mask:SetAllPoints(row.stamp) mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  row.stamp:AddMaskTexture(mask)
  row.ring = row:CreateTexture(nil, "OVERLAY")
  row.ring:SetAllPoints(row.stamp)
  row.ring:SetTexture(ns.Icons.ringStamp)
  row.stamp:Hide() row.ring:Hide()
  -- fold button (regions and zones with sub zones), hairline under the region headers
  row.toggle = CreateFrame("Button", nil, row)
  row.toggle:SetSize(16, 16)
  row.toggle:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
  row.toggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  row.toggle:Hide()
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetColorTexture(ns.Colors.aqua[1], ns.Colors.aqua[2], ns.Colors.aqua[3], 0.4)
  row.line:SetHeight(1)
  row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 1)
  row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 1)
  row.line:Hide()
  row.text = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.text:SetJustifyH("LEFT")
  row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.sub:SetPoint("RIGHT", -26, 0)
  row.mark = row:CreateTexture(nil, "OVERLAY")
  row.mark:SetSize(16, 16)
  row.mark:SetPoint("RIGHT", -4, 0)
  row.mark:SetTexture("Interface\\COMMON\\ReputationStar")
  row.mark:SetTexCoord(0, 0.5, 0, 0.5)
  row:SetScript("OnClick", function(self)
    if self.entry and self.entry.kind == "region" then
      local fo = fold()
      fo.regions[self.entry.text] = (not fo.regions[self.entry.text]) or nil
      refresh()
      return
    elseif self.entry and self.entry.kind == "zonefish" then
      -- fish under a zone: choose any number, they filter the spots on the map
      local map = BJ.modules.ZoneMap
      if map then map.Toggle(self.entry.id) end
      refresh()
    elseif self.entry then
      state.sub = "overview"
      state.free = nil
      state.selected = self.entry
      pageSound()
      curl(false)
      refresh()
    end
  end)
  row.toggle:SetScript("OnClick", function()
    local e = row.entry
    if not e then return end
    local fo = fold()
    if e.kind == "region" then
      fo.regions[e.text] = (not fo.regions[e.text]) or nil
    elseif e.kind == "vzone" then
      local open = e.expanded
      fo.zones["v" .. e.id] = (not open) or nil
      if open and state.selected and state.selected.kind == "npc" and state.selected.zone == e.id then state.selected = e end
    elseif e.kind == "zone" then
      local open = e.expanded
      fo.zones[e.id] = (not open) or nil
      -- closing a zone whose sub zone is selected would hide the selection: select the zone instead
      if open and state.selected and state.selected.kind == "subzone" and state.selected.zone == e.id then state.selected = e end
    end
    refresh()
  end)
  -- Fish rows show the item tooltip (our own section is appended by the Tooltip module).
  row:SetScript("OnEnter", function(self)
    if self.entry and (self.entry.kind == "fish" or self.entry.kind == "zonefish") then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(self.entry.id)
      GameTooltip:Show()
      BJ:DebugTip(GameTooltip, "Item", self.entry.id)
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

-- One grid cell (fish / lure): framed icon + name; frame and name are grey for entries not seen yet.
local function createCell(parent, i, template)
  local cell = CreateFrame("Button", nil, parent)
  cell:SetSize(CELL_W - 4, CELL_H - 4)
  local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
  cell:SetPoint("TOPLEFT", col * CELL_W, -row * CELL_H)
  cell.sel = cell:CreateTexture(nil, "BACKGROUND")
  cell.sel:SetAllPoints()
  cell.sel:SetColorTexture(0.55, 0.36, 0.14, 0.2)
  cell.sel:Hide()
  cell:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
  cell:GetHighlightTexture():SetVertexColor(0.55, 0.36, 0.14, 0.12)
  cell.icon = cell:CreateTexture(nil, "ARTWORK")
  cell.icon:SetSize(40, 40)
  cell.icon:SetPoint("LEFT", 4, 0)
  cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  cell.slotBack = cell:CreateTexture(nil, "BACKGROUND", nil, 2)
  cell.slotBack:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -3, 3)
  cell.slotBack:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 3, -3)
  if hasAtlas("bags-item-slot64") then cell.slotBack:SetAtlas("bags-item-slot64")
  else cell.slotBack:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled") cell.slotBack:SetTexCoord(0.15, 0.85, 0.15, 0.85) end
  cell.slotBack:Hide()
  -- fish hook: this lure is the favourite
  cell.hook = cell:CreateTexture(nil, "OVERLAY", nil, 3)
  cell.hook:SetSize(20, 20)
  cell.hook:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -15, 12)
  if hasAtlas("Crosshair_Fishing") then cell.hook:SetAtlas("Crosshair_Fishing")
  else cell.hook:SetTexture("Interface\\Cursor\\Fishing") end
  cell.hook:Hide()
  cell.count = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  cell.count:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", -2, 2)
  cell.count:Hide()
  cell.frameTex = cell:CreateTexture(nil, "OVERLAY")
  cell.frameTex:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", -5, 5)
  cell.frameTex:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 5, -5)
  if hasAtlas("collections-itemborder-collected") then cell.frameTex:SetAtlas("collections-itemborder-collected")
  else cell.frameTex:SetTexture("Interface\\Common\\WhiteIconFrame") cell.frameTex:SetVertexColor(1, 0.82, 0) end
  cell.text = cell:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  cell.text:SetPoint("LEFT", cell.icon, "RIGHT", 10, 0)
  cell.text:SetWidth(CELL_W - 70)
  cell.text:SetJustifyH("LEFT")
  cell.text:SetMaxLines(3)
  cell.text:SetShadowOffset(0, 0)
  cell.mark = cell:CreateTexture(nil, "OVERLAY")
  cell.mark:SetSize(14, 14)
  cell.mark:SetPoint("TOPRIGHT", -2, -2)
  cell.mark:SetTexture("Interface\\COMMON\\ReputationStar")
  cell.mark:SetTexCoord(0, 0.5, 0, 0.5)
  cell:SetScript("OnClick", template:GetScript("OnClick"))
  cell:SetScript("OnEnter", function(self)
    local id = self.entry and (self.entry.kind == "fish" and self.entry.id or self.entry.itemID)
    if id then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(id)
      GameTooltip:Show()
      local e = self.entry
      BJ:DebugTip(GameTooltip, "Item", id, "Enchant", e.kind == "lure" and type(e.id) == "number" and e.id or nil)
    end
  end)
  cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return cell
end

-- ---- vendor page: model and goods ---------------------------------------------------------------------------------------

local VENDOR_ORDER = {"pole", "bobber", "lure", "recipe", "fish", "other"}
local GOOD_W, GOOD_H, MAX_GOODS = 196, 46, 12 -- two columns like the vendor window, six rows

--- Tooltip of a good: the item (its own tooltip already names requirements and "already known"), then what the vendor asks.
local function goodTip(b)
  if not b.itemID then return end
  GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(b.itemID)
  local P = ns.Prices
  local text = b.offer and P.OfferText(b.offer) or ""
  if text ~= "" then GameTooltip:AddLine(" ") GameTooltip:AddLine(text, 1, 1, 1) end
  -- a recipe the character carries around (not learned yet): where it is
  if b.owned then
    GameTooltip:AddLine(" ")
    local st = b.owned
    if st.bags > 0 then GameTooltip:AddLine(format("%s: %d", L["In bags"], st.bags), 0.2, 0.9, 0.2) end
    if st.bank > 0 then GameTooltip:AddLine(format("%s: %d", L["In the bank"], st.bank), 0.2, 0.9, 0.2) end
    if st.warband > 0 then GameTooltip:AddLine(format("%s: %d", L["In the warband bank"], st.warband), 0.2, 0.9, 0.2) end
  end
  GameTooltip:Show()
  BJ:DebugTip(GameTooltip, "Item", b.itemID)
end

--- One entry of the list "Sold": icon (frame, stack count, green check for a learned recipe), name and price beside it.
local function goodButton(i)
  local v = frame.vendor
  local b = v.goods[i]
  if b then return b end
  b = CreateFrame("Button", nil, v)
  b:SetSize(GOOD_W - 4, GOOD_H - 4)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0.8, 0.1, 0.1, 0.35) -- red when the character cannot buy it (like the vendor window)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(34, 34)
  b.icon:SetPoint("LEFT", 5, 0)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -4, 4) b.border:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 4, -4)
  if hasAtlas("collections-itemborder-collected") then b.border:SetAtlas("collections-itemborder-collected")
  else b.border:SetTexture("Interface\\Common\\WhiteIconFrame") end
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -2, 2)
  b.check = b:CreateTexture(nil, "OVERLAY", nil, 3)
  b.check:SetSize(16, 16)
  b.check:SetPoint("TOPRIGHT", b.icon, "TOPRIGHT", 5, 5)
  b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  b.name = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, 1)
  b.name:SetWidth(GOOD_W - 62)
  b.name:SetJustifyH("LEFT")
  b.name:SetMaxLines(2)
  b.name:SetShadowOffset(0, 0)
  b.price = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  b.price:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, -1)
  b.price:SetShadowOffset(0, 0)
  b.price:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3])
  b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
  b:GetHighlightTexture():SetVertexColor(0.55, 0.36, 0.14, 0.15)
  b:SetScript("OnEnter", goodTip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  v.goods[i] = b
  return b
end

--- Fills the vendor page: model, the list "Sold" (the fishing goods of the vendor as in the vendor window: icon, name and
--- price, two columns; what the character cannot buy is red, learned recipes are green) and for a teacher the services.
function M.FillVendor(npc)
  if not frame.vendor then
    local v = CreateFrame("Frame", nil, frame.page)
    v:SetAllPoints(frame.book)
    v.goods = {}
    local ok, model = pcall(CreateFrame, "PlayerModel", nil, v)
    if ok then
      v.model = model
      model:SetSize(MODEL_W, MODEL_H)
      model:SetPoint("TOPRIGHT", frame.book, "TOP", BODY_X + BODY_W, -MODEL_TOP)
    end
    v.heading = v:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    v.heading:SetShadowOffset(0, 0)
    v.heading:SetTextColor(INK_HEAD[1], INK_HEAD[2], INK_HEAD[3], 1)
    v.rule = v:CreateTexture(nil, "ARTWORK")
    v.rule:SetColorTexture(INK_HEAD[1], INK_HEAD[2], INK_HEAD[3], 0.75)
    v.rule:SetHeight(1)
    v.more = v:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    v.more:SetJustifyH("LEFT")
    v.more:SetWidth(BODY_W)
    v.more:SetShadowOffset(0, 0)
    v.more:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3])
    frame.vendor = v
  end
  local v = frame.vendor
  if v.model then
    v.model:ClearModel()
    if v.model.SetCreature and type(npc.id) == "number" then pcall(v.model.SetCreature, v.model, npc.id) end
    v.model:Show()
  end
  -- the goods in the order of the categories, by name inside
  local items = {}
  for _, cat in ipairs(VENDOR_ORDER) do
    local ids = {}
    for itemID, c in pairs(npc.items or {}) do if c == cat then ids[#ids + 1] = {id = itemID, name = tostring(itemName(itemID))} end end
    table.sort(ids, function(a, b) return a.name < b.name end) -- (the names are looked up once, not at every comparison)
    for _, e in ipairs(ids) do items[#items + 1] = {id = e.id, cat = cat} end
  end
  local headTop = -(MODEL_TOP + MODEL_H + 6)
  local top = headTop - 24
  v.heading:ClearAllPoints()
  v.heading:SetPoint("TOPLEFT", frame.book, "TOP", BODY_X, headTop)
  v.heading:SetText(#items > 0 and L["Sold"] or "")
  -- the line runs through the middle of the heading's height, from the text to the right edge
  v.rule:ClearAllPoints()
  v.rule:SetPoint("LEFT", v.heading, "RIGHT", 8, 0)
  v.rule:SetWidth(math.max(BODY_W - (v.heading:GetStringWidth() or 0) - 8, 20))
  v.rule:SetShown(#items > 0)
  local n = 0
  for _, it in ipairs(items) do
    if n >= MAX_GOODS then break end
    n = n + 1
    local itemID, cat = it.id, it.cat
    local b = goodButton(n)
    local offer = npc.offers and npc.offers[itemID]
    local known = cat == "recipe" and BJ.DB:RecipeKnown(itemID) or false
    -- a recipe in the bags, the bank or the warband bank that is not learned yet: only the green check, the tooltip says where
    local owned
    if cat == "recipe" and not known then
      local st = ns.Stock.Counts(itemID)
      if st and (st.bags + st.bank + st.warband) > 0 then owned = st end
    end
    local need = not known and not owned and #ns.Prices.Needs(offer) > 0
    b.itemID, b.offer, b.known, b.owned = itemID, offer, known, owned
    b.icon:SetTexture(itemIcon(itemID))
    -- background like the vendor window: green = recipe already learned, red = cannot be bought yet
    b.bg:SetShown(known or need)
    if known then b.bg:SetColorTexture(0.1, 0.7, 0.1, 0.30) elseif need then b.bg:SetColorTexture(0.8, 0.1, 0.1, 0.35) end
    if known then b.border:SetVertexColor(0.2, 0.9, 0.2)
    elseif need then b.border:SetVertexColor(0.9, 0.2, 0.2)
    else b.border:SetVertexColor(0.8, 0.58, 0.25) end
    b.check:SetShown(known or owned ~= nil)
    b.count:SetText(offer and offer.q or "")
    b.name:SetText(plain(itemName(itemID)))
    if known then b.name:SetTextColor(0.1, 0.5, 0.1)
    elseif need then b.name:SetTextColor(0.75, 0.1, 0.1)
    else
      local qr, qg, qb = qualityInk(itemID)
      if qr then b.name:SetTextColor(qr, qg, qb) else b.name:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3]) end
    end
    b.price:SetText(offer and ns.Prices.OfferText(offer) or "")
    local col, row = (n - 1) % 2, math.floor((n - 1) / 2)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", frame.book, "TOP", BODY_X + col * GOOD_W, top - row * GOOD_H)
    b:Show()
  end
  for i = n + 1, #v.goods do v.goods[i]:Hide() end
  local bottom = top - math.ceil(n / 2) * GOOD_H - 4
  -- teacher services and repair below the goods
  local lines = {}
  if #items > n then lines[#lines + 1] = format(L["%d more"], #items - n) end
  if npc.lessons and #npc.lessons > 0 then
    lines[#lines + 1] = L["Teaches"]
    for _, l in ipairs(npc.lessons) do lines[#lines + 1] = plain(ns.Prices.LessonText(l)) end
  end
  if npc.repair then lines[#lines + 1] = L["Repairs equipment"] end
  v.more:ClearAllPoints()
  v.more:SetPoint("TOPLEFT", frame.book, "TOP", BODY_X, bottom)
  v.more:SetText(table.concat(lines, "\n"))
  v:Show()
end

-- Header strip and pages of the book as in the spell book; falls back to the classic page textures.
local function createBook(parent)
  local book = CreateFrame("Frame", nil, parent)
  book:SetPoint("TOPLEFT", 0, -23)
  book:SetPoint("BOTTOMRIGHT", -6, 4)
  local left, right = book:CreateTexture(nil, "BACKGROUND", nil, 1), book:CreateTexture(nil, "BACKGROUND", nil, 1)
  left:SetPoint("TOPLEFT", 0, -51) left:SetPoint("BOTTOMRIGHT", book, "BOTTOM")
  right:SetPoint("TOPLEFT", book, "TOP", 0, -51) right:SetPoint("BOTTOMRIGHT")
  if hasAtlas("spellbook-background-evergreen-left") then
    left:SetAtlas("spellbook-background-evergreen-left") right:SetAtlas("spellbook-background-evergreen-right")
  else
    left:SetTexture("Interface\\Spellbook\\Spellbook-Page-1") right:SetTexture("Interface\\Spellbook\\Spellbook-Page-2")
  end
  local top = book:CreateTexture(nil, "BACKGROUND", nil, 1)
  top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(54)
  if hasAtlas("spellbook-background-evergreen-header") then top:SetAtlas("spellbook-background-evergreen-header")
  else top:SetColorTexture(0.12, 0.08, 0.05, 1) end
  if hasAtlas("spellbook-background-evergreen-ribbon") then
    local ribbon = book:CreateTexture(nil, "BACKGROUND", nil, 2)
    ribbon:SetAtlas("spellbook-background-evergreen-ribbon", true)
    ribbon:SetPoint("TOPRIGHT", left, "TOPRIGHT", 62, 0)
  end
  if hasAtlas("spellbook-corner-flipbook-evergreen") and book.CreateAnimationGroup then
    local tex = book:CreateTexture(nil, "BACKGROUND", nil, 2)
    tex:SetAtlas("spellbook-corner-flipbook-evergreen", false)
    tex:SetSize(CURL_W, CURL_H)
    tex:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -6, 4) -- the page corner of the right page
    local group = tex:CreateAnimationGroup()
    local flip = group:CreateAnimation("FlipBook")
    flip:SetFlipBookRows(2) flip:SetFlipBookColumns(4) flip:SetFlipBookFrames(8)
    flip:SetDuration(0.25) flip:SetSmoothing("NONE")
    group:SetLooping("NONE")
    group:Play() group:Pause() -- rests on the first frame
    parent.curl = {tex = tex, anim = group}
  end
  return book
end

-- Frame tabs below the book. Own simple tabs instead of Blizzard's tab templates: those have a fixed height, and the
-- icon (48 px) is the tab's content. Selected tab: aqua border; the name is a tooltip.
local TAB_SIZE, TAB_GAP = 44, 22

local function createTab(parent, key, i)
  -- Like the side tabs of the classic spell book: a check button with the ornate tab art (SpellBook-SkillLineTab)
  -- behind the icon, stacked at the right edge of the book.
  local tab = CreateFrame("CheckButton", nil, parent)
  tab.key = key
  tab:SetSize(TAB_SIZE, TAB_SIZE)
  tab.art = tab:CreateTexture(nil, "BORDER")
  tab.art:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
  tab.art:SetSize(TAB_SIZE * 2, TAB_SIZE * 2)
  tab.art:SetPoint("TOPLEFT", -TAB_SIZE * 0.09, TAB_SIZE * 0.34)
  tab.icon = tab:CreateTexture(nil, "ARTWORK")
  tab.icon:SetAllPoints()
  tab.icon:SetTexture(TAB_TEXTURE[key] or ns.Icons.Path(TAB_ICON[key], TAB_ICON_PX[key] or 128))
  tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
  -- SetCheckedTexture has no blend mode argument: the black centre of the picture only vanishes with ADD
  tab:GetCheckedTexture():SetBlendMode("ADD")
  function tab.Select(self, selected)
    self:SetChecked(selected and true or false)
    self.icon:SetAlpha(selected and 1 or 0.85)
  end
  tab:Select(false)
  if i == 1 then tab:SetPoint("TOPLEFT", parent, "TOPRIGHT", -2, -90)
  else tab:SetPoint("TOPLEFT", parent.tabs[i - 1], "BOTTOMLEFT", 0, -TAB_GAP) end
  tab:SetScript("OnClick", function(self) self:SetChecked(true) setTab(key) end)
  tab:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L[TAB_TEXT[key]])
    GameTooltip:Show()
    BJ:DebugTip(GameTooltip, "Tab", key)
  end)
  tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return tab
end

local function pagingButton(parent, name, direction, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(32, 32)
  b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "-Up")
  b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "-Down")
  b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "-Disabled")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetScript("OnClick", function() if onClick then onClick() else turn(direction) end end)
  b:SetScript("OnEnter", function() curl(false) end)
  b:SetScript("OnLeave", function() curl(true) end)
  return b
end

local function createFrame()
  local ok
  ok, frame = pcall(CreateFrame, "Frame", "BobbersJournalFrame", UIParent, "PortraitFrameTemplate")
  local framed = ok
  if not ok then frame = CreateFrame("Frame", "BobbersJournalFrame", UIParent) end
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  if framed then
    -- Title bar and portrait of the standard panel frame, like the spell book window.
    if frame.SetTitle then frame:SetTitle(ns.Colors.Paint("aqua", L["ADDON_NAME"])) end
    pcall(function()
      local book = ns.Icons.logo(128)
      if frame.SetPortraitTextureRaw then frame:SetPortraitTextureRaw(book)
      elseif frame.SetPortraitToAsset then frame:SetPortraitToAsset(book) end
    end)
    -- The logo is transparent: a black disc behind it, cut to the round portrait like the portrait itself.
    pcall(function()
      local holder = frame.PortraitContainer or frame
      local portrait = holder.portrait or frame.portrait
      if not portrait then return end
      local disc = holder:CreateTexture(nil, "BACKGROUND", nil, 7)
      disc:SetAllPoints(portrait)
      disc:SetColorTexture(0, 0, 0, 1)
      local mask = holder:CreateMaskTexture()
      mask:SetAllPoints(portrait)
      mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      disc:AddMaskTexture(mask)
      -- The logo is drawn smaller than the portrait so the ring does not cut it off.
      portrait:SetAlpha(0)
      local icon = holder:CreateTexture(nil, "ARTWORK", nil, 2)
      icon:SetPoint("CENTER", portrait, "CENTER", 0, 0)
      local size = (portrait:GetWidth() or 60) * 0.80
      icon:SetSize(size, size)
      icon:SetTexture(ns.Icons.logo(128))
    end)
    if frame.Bg then frame.Bg:Hide() end
    if frame.Inset then frame.Inset:Hide() end
  else
    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(34, 34)
    logo:SetPoint("TOPLEFT", 20, -9)
    logo:SetTexture(ns.Icons.logo(64))
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    title:SetText(L["ADDON_NAME"])
    title:SetTextColor(unpack(ns.Colors.sand))
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end

  local book = createBook(frame)
  frame.book = book
  -- Text layer of the right page: above the zone map (the map lies on the page, level +1).
  frame.page = CreateFrame("Frame", nil, book)
  frame.page:SetAllPoints(book)
  frame.page:SetFrameLevel(book:GetFrameLevel() + 3)
  frame.tabs = {}
  for i, key in ipairs(TABS) do
    frame.tabs[i] = createTab(frame, key, i)
  end

  -- Search: centred in the brown header strip of the book.
  local searchOk, box = pcall(CreateFrame, "EditBox", nil, book, "SearchBoxTemplate")
  if not searchOk then box = CreateFrame("EditBox", nil, book, "InputBoxTemplate") end
  box:SetSize(300, 30)
  box:SetPoint("TOP", book, "TOP", 0, -12)
  box:SetAutoFocus(false)
  -- HookScript, not SetScript: the search box template's own handler hides its "Search" hint text.
  box:HookScript("OnTextChanged", function(self)
    if self.GetText then state.search = (self:GetText() or ""):lower() end
    state.offset, state.free = 0, nil
    refresh()
  end)
  box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
  frame.search = box

  -- Filter at the left of the search box: show all / only collected
  local function setFilter(v)
    BJ.settings.journalFilter = v
    state.offset = 0
    if frame.filter then frame.filter.update() end
    refresh()
  end
  local control, update = BJ.Menu.Choice(book, {
    width = 170, values = {"all", "collected"},
    get = function() return BJ.settings.journalFilter or "all" end, pick = setFilter,
    display = function(v) return v == "collected" and L["Show collected only"] or L["Show all"] end,
  })
  control:SetPoint("RIGHT", box, "LEFT", control:GetObjectType() == "Frame" and 6 or -10, 0)
  update()
  frame.filter = {control = control, update = update}

  -- Text tabs with the frame art of the Blizzard tab system, hanging below the book (sub tabs of the Lures page on the
  -- left, the page tabs of the fish page on the right).
  local function flipped(tex, atlas) tex:SetAtlas(atlas, true) end -- tabs hang below the window: art as it is
  local function tabButton(text)
    local b = CreateFrame("Button", nil, frame)
    b:SetHeight(32)
    b.parts = {}
    local names = {act = {"uiframe-activetab-left", "_uiframe-activetab-center", "uiframe-activetab-right"},
      off = {"uiframe-tab-left", "_uiframe-tab-center", "uiframe-tab-right"}}
    for state_, set in pairs(names) do
      local l, m, r = b:CreateTexture(nil, "BACKGROUND"), b:CreateTexture(nil, "BACKGROUND"), b:CreateTexture(nil, "BACKGROUND")
      flipped(l, set[1]) flipped(m, set[2]) flipped(r, set[3])
      m:SetHorizTile(true)
      l:SetPoint("TOPLEFT") r:SetPoint("TOPRIGHT", 6, 0)
      m:SetPoint("LEFT", l, "RIGHT") m:SetPoint("RIGHT", r, "LEFT") m:SetPoint("TOP")
      b.parts[state_] = {l, m, r}
    end
    b.text = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    b.text:SetPoint("CENTER", 0, 2)
    b.text:SetText(text)
    b:SetWidth((b.text:GetStringWidth() or 60) + 44)
    function b.SetActive(self, on)
      for _, t in ipairs(self.parts.act) do t:SetShown(on) end
      for _, t in ipairs(self.parts.off) do t:SetShown(not on) end
      self.text:SetFontObject(on and "GameFontHighlightSmall" or "GameFontNormalSmall")
    end
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
    b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    b:Hide()
    return b
  end
  frame.subTabs = {}
  for i, def in ipairs({{"overview", L["Overview"]}, {"settings", L["Settings"]}}) do
    local b = tabButton(def[2])
    b.key = def[1]
    b:SetScript("OnClick", function(self)
      state.sub, state.selected, state.offset = self.key, nil, 0
      pageSound()
      refresh()
    end)
    if i == 1 then b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 22, 2)
    else b:SetPoint("LEFT", frame.subTabs[i - 1], "RIGHT", 4, 0) end
    frame.subTabs[i] = b
  end
  -- page tabs below the right page whenever it has more than one page (fish: Info, Map, Sales; lure and vendor: two); the
  -- arrows turn through the same pages. Labels are set in refresh.
  frame.pageTabs = {}
  for i = 1, 3 do
    local b = tabButton("Info")
    b.page = i
    b:SetScript("OnClick", function(self)
      if (state.rpage or 1) == self.page then return end
      state.rpage = self.page
      pageSound()
      curl(false)
      refresh()
    end)
    if i == 1 then b:SetPoint("TOPLEFT", frame, "BOTTOM", 22, 2)
    else b:SetPoint("LEFT", frame.pageTabs[i - 1], "RIGHT", 4, 0) end
    frame.pageTabs[i] = b
  end

  frame.list = CreateFrame("Frame", nil, book)
  frame.list:SetSize(400, ROWS * ROW_H)
  frame.list:SetPoint("TOPLEFT", 40, -80)
  frame.list:EnableMouseWheel(true)
  frame.list:SetScript("OnMouseWheel", function(_, delta)
    if GRID[state.tab] then state.selected = nil state.offset = math.max(state.offset - delta, 0)
    else state.free = true state.offset = math.max(state.offset - delta * 3, 0) end
    refresh()
  end)
  frame.rows = {}
  for i = 1, ROWS do frame.rows[i] = createRow(frame.list, i) end
  frame.cells = {}
  for i = 1, COLS * GRID_ROWS do frame.cells[i] = createCell(frame.list, i, frame.rows[1]) end

  frame.emptyText = frame.page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  frame.emptyText:SetPoint("CENTER", book, "TOP", 240, -330)
  frame.emptyText:SetWidth(380)
  frame.emptyText:SetJustifyH("CENTER")
  frame.emptyText:SetShadowOffset(0, 0)
  frame.emptyText:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3], 0.85)
  frame.pageIcon = frame.page:CreateTexture(nil, "BACKGROUND", nil, 7)
  frame.pageIcon:SetSize(ICON_SIZE * 2, ICON_SIZE * 2)
  frame.pageIcon:SetPoint("TOPLEFT", book, "TOP", 16, -90)
  -- Painted on the parchment: no colour, brown/sepia like the dark parts of the paper, half transparent, and the
  -- edge fades out through a soft mask (own mask texture, Media\\Mask_Soft_128).
  frame.pageIcon:SetDesaturated(true)
  -- Sven's values: colour 1, 0.74, 0.45, alpha 0.6. The alpha goes through SetAlpha (the vertex colour alpha is not
  -- reliable together with a mask texture); it is applied again after every SetTexture.
  frame.pageIcon:SetVertexColor(1, 0.74, 0.45)
  frame.pageIcon:SetAlpha(0.6)
  local fade = frame.page:CreateMaskTexture()
  fade:SetAllPoints(frame.pageIcon)
  fade:SetTexture(ns.Icons.maskRound, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  frame.pageIcon:AddMaskTexture(fade)
  -- Favourite lure (Lures page): drag a lure from the bags onto the field; right click removes it.
  local fav = CreateFrame("Frame", nil, frame.page)
  fav:SetPoint("TOPLEFT", frame.book, "TOP", BODY_X, -(80 + PAGE_BASE))
  fav:SetSize(BODY_W, FAV_H)
  frame.fav = fav
  fav.label = fav:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fav.label:SetPoint("TOPLEFT")
  fav.label:SetText(L["Favorite lure"])
  fav.label:SetTextColor(INK_HEAD[1], INK_HEAD[2], INK_HEAD[3])
  fav.label:SetShadowOffset(0, 0)
  fav.slot = CreateFrame("Button", nil, fav)
  fav.slot:SetSize(48, 48)
  fav.slot:SetPoint("TOPLEFT", fav.label, "BOTTOMLEFT", 0, -10)
  -- looks like an empty bag slot
  fav.slot.back = fav.slot:CreateTexture(nil, "BACKGROUND")
  fav.slot.back:SetAllPoints()
  if hasAtlas("bags-item-slot64") then fav.slot.back:SetAtlas("bags-item-slot64")
  else
    fav.slot.back:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    fav.slot.back:SetTexCoord(0.15, 0.85, 0.15, 0.85)
  end
  fav.slot.icon = fav.slot:CreateTexture(nil, "ARTWORK")
  fav.slot.icon:SetPoint("TOPLEFT", 3, -3) fav.slot.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  fav.slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- visible frame around the slot, same art as the cells of the lure list
  fav.slot.frameTex = fav.slot:CreateTexture(nil, "OVERLAY")
  fav.slot.frameTex:SetPoint("TOPLEFT", -5, 5)
  fav.slot.frameTex:SetPoint("BOTTOMRIGHT", 5, -5)
  if hasAtlas("collections-itemborder-collected") then fav.slot.frameTex:SetAtlas("collections-itemborder-collected")
  else fav.slot.frameTex:SetTexture("Interface\\Common\\WhiteIconFrame") end
  -- grey like the bag slots (BAG_ITEM_QUALITY_COLORS[common] in the Blizzard bag code)
  local gray = BAG_ITEM_QUALITY_COLORS and BAG_ITEM_QUALITY_COLORS[1] or COMMON_GRAY_COLOR
  if gray and gray.GetRGB then fav.slot.frameTex:SetVertexColor(gray:GetRGB()) else fav.slot.frameTex:SetVertexColor(0.62, 0.62, 0.62) end
  fav.slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  fav.slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  fav.slot:RegisterForDrag("LeftButton")
  fav.name = fav:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fav.name:SetPoint("LEFT", fav.slot, "RIGHT", 12, 6)
  fav.name:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3])
  fav.name:SetShadowOffset(0, 0)
  fav.hint = fav:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  fav.hint:SetPoint("TOPLEFT", fav.slot, "BOTTOMLEFT", 0, -6)
  fav.hint:SetWidth(BODY_W)
  fav.hint:SetJustifyH("LEFT")
  fav.hint:SetTextColor(0.5, 0.5, 0.5) -- grey, no shadow
  fav.hint:SetShadowOffset(0, 0)
  fav.hint:SetText(L["Drag a lure from your bags onto the field. Right click removes it."])
  local function drop()
    local kind, id = GetCursorInfo()
    if kind ~= "item" then return false end
    if ns.Lures and ns.Lures.IsLure(id) then
      BJ.settings.cast.favoriteLure = id
      ClearCursor()
      refresh()
    else
      BJ:Print(L["This item is not a fishing lure."])
    end
    return true
  end
  fav.slot:SetScript("OnReceiveDrag", drop)
  fav.slot:SetScript("OnClick", function(_, button)
    if drop() then return end
    if button == "RightButton" then BJ.settings.cast.favoriteLure = nil refresh() end
  end)
  fav.slot:SetScript("OnEnter", function(self)
    local id = BJ.settings.cast.favoriteLure
    if id then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetItemByID(id) GameTooltip:Show() BJ:DebugTip(GameTooltip, "Item", id) end
  end)
  fav.slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Options below each other (same settings as in the options window)
  local function check(anchor, text, tip, get, set)
    local cb = CreateFrame("CheckButton", nil, fav, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    cb.text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.text:SetText(text)
    cb.text:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3])
    cb.text:SetShadowOffset(0, 0)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(text)
      GameTooltip:AddLine(tip, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return cb
  end
  fav.auto = check(fav.hint, L["Apply lures automatically"],
    L["If the pole has no lure, the next click applies a lure from your bags (the favorite first); the click after that casts. Needs Casting to be on."],
    nil, function(v) BJ.settings.cast.autoLure = v end)
  fav.best = check(fav.auto, L["Best lure as fallback"],
    L["If no favorite is set or found in your bags, the best lure you have is used."],
    nil, function(v) BJ.settings.cast.autoBest = v end)
  fav:Hide()
  frame.title = frame.page:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  frame.title:SetJustifyH("LEFT")
  frame.title:SetWidth(BODY_W - ICON_SIZE - 14 - 10)
  frame.detailRows = {}

  frame.bookmark = CreateFrame("Button", nil, frame.page, "UIPanelButtonTemplate")
  frame.bookmark:SetSize(160, 24)
  frame.bookmark:SetPoint("BOTTOMLEFT", book, "BOTTOM", 40, 40)
  frame.bookmark:SetScript("OnClick", function()
    local s = state.selected
    if s then BJ.API.SetBookmark(s.kind, s.id, not BJ.API.IsBookmarked(s.kind, s.id)) end
  end)

  -- TomTom route to the vendor or teacher (only with TomTom installed)
  frame.tomtom = CreateFrame("Button", nil, frame.page, "UIPanelButtonTemplate")
  frame.tomtom:SetSize(190, 24)
  frame.tomtom:SetPoint("BOTTOMLEFT", book, "BOTTOM", 40, 68)
  frame.tomtom:SetText(L["Set waypoint (TomTom)"])
  frame.tomtom:SetScript("OnClick", function()
    local n = state.selected and state.selected.npc
    local tt = _G.TomTom
    if n and n.map and n.x and n.y and tt and tt.AddWaypoint then
      tt:AddWaypoint(n.map, n.x, n.y, {title = n.name or "Bobber's Journal", persistent = false, minimap = true, world = true})
      BJ:Print(format(L["Waypoint set: %s"], n.name or "?"))
    end
  end)
  frame.tomtom:Hide()

  -- Paging: one page per entry; "Page n/N" with arrows at the bottom right, as in the spell book.
  frame.next = pagingButton(frame.page, "NextPage", 1)
  frame.next:SetPoint("BOTTOMRIGHT", -70, 36)
  frame.prev = pagingButton(frame.page, "PrevPage", -1)
  frame.prev:SetPoint("RIGHT", frame.next, "LEFT", -4, 0)
  -- left page: turns through the list (grid tabs)
  local function turnList(d)
    if GRID[state.tab] then
      state.selected = nil
      state.offset = math.max(state.offset + d, 0)
    else
      -- lists: one page = ROWS rows; the selection stays
      state.free = true
      state.offset = math.min(math.max(state.offset + d * ROWS, 0), state.maxOffset or 0)
    end
    pageSound()
    refresh()
  end
  -- same distance to the left edge as the controls of the right page have to the right edge (70 px);
  -- the text sits to the right of the buttons
  frame.lprev = pagingButton(frame.page, "PrevPage", -1, function() turnList(-1) end)
  frame.lprev:SetPoint("BOTTOMLEFT", frame.book, "BOTTOMLEFT", 70, 36)
  frame.lnext = pagingButton(frame.page, "NextPage", 1, function() turnList(1) end)
  frame.lnext:SetPoint("LEFT", frame.lprev, "RIGHT", 4, 0)
  frame.lpageText = frame.page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  frame.lpageText:SetPoint("LEFT", frame.lnext, "RIGHT", 8, 0)
  frame.pageText = frame.page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  frame.pageText:SetPoint("RIGHT", frame.prev, "LEFT", -8, 0)
  -- statistic line at the bottom right of the left page
  frame.stat = frame.page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  frame.stat:SetPoint("RIGHT", frame.book, "BOTTOM", -40, 52 - 0) -- level with the paging buttons (BOTTOMLEFT 70, 36, height 32)
  frame.stat:SetJustifyH("RIGHT")
  frame.stat:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3])
  frame.stat:SetShadowOffset(0, 0)
  frame.stat:Hide()

  frame:SetScript("OnShow", refresh)
  -- ESC closes the window like other panels
  if UISpecialWindows then tinsert(UISpecialWindows, "BobbersJournalFrame") end
end

--- Opens the journal on the Lures page (from the options).
function M.OpenLures()
  if not frame then createFrame() end
  frame:Show()
  setTab("lures")
end

-- (for the smoke test)
function M.SelectTab(key) if not frame then createFrame() end setTab(key) end
function M.FirstEntry() return state.entries and state.entries[1] or nil end
function M.Entries() return state.entries or {} end
function M.Select(e) state.selected, state.rpage, state.rpageKey = e, 1, nil refresh() end
function M.SetPage(p) state.rpage = p end

function M.Toggle()
  if not frame then createFrame() end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

function M:OnEnable()
  -- Redraw on new data, bookmark changes and when item names arrive; no OnUpdate needed.
  BJ:Listen(function() refresh() end)
  BJ:RegisterEvent("GET_ITEM_INFO_RECEIVED", "journal", function() if frame and frame:IsShown() then redrawLater() end end) -- arrives in bursts: one redraw
  -- lures in the bags are shown with their count on the Lures page
  BJ:RegisterEvent("BAG_UPDATE_DELAYED", "journal bags", function()
    if frame and frame:IsShown() and state.tab == "lures" then redrawLater() end
  end)
  -- a lure applied or run out
  BJ:RegisterEvent("UNIT_INVENTORY_CHANGED", "journal lure", function(_, unit)
    if unit == "player" and frame and frame:IsShown() and state.tab == "lures" then redrawLater() end
  end)
end
