local _, ns = ...
local BJ, Flavor = ns.BJ, ns.Flavor
local L = BJ.L
-- Retail only: adds our own data (catches, zones with catch chance) below the description of a fish page in Blizzard's
-- fishing journal (profession window, fish pages are "dummy recipes"). Only a text is appended after Blizzard has set
-- its own description (hooksecurefunc, no Blizzard function is replaced). Fish are matched by name.
local M = BJ:RegisterModule("Diary")

local MAX_ZONES = 6
local hooked
local box -- our scroll box on the page of the game (see ensureBox)

--- Item ID of the fish a page of the game is about, by its name: every fish of the shipped catalogue and of our records.
local function fishByName(name)
  local ids = {}
  for id, mask in pairs(ns.Catalog.fish) do
    if Flavor.Matches(mask, Flavor.RETAIL) then ids[id] = true end
  end
  for _, f in ipairs(BJ.API.GetFishList(Flavor.RETAIL)) do ids[f.itemID] = true end
  for id in pairs(ids) do
    if BJ.DB:ItemName(id) == name then return id end
  end
end

--- Asks the client for the names of all catalogue fish once (they are saved in the database on arrival), so that the pages
--- of fish we never caught can be recognised by name.
local function preloadNames()
  if not (Item and Item.CreateFromItemID) then return end
  for id, mask in pairs(ns.Catalog.fish) do
    if Flavor.Matches(mask, Flavor.RETAIL) and not BJ.DB:ItemName(id) then
      Item:CreateFromItemID(id):ContinueOnItemLoad(function() BJ.DB:ItemName(id) end)
    end
  end
end

--- Heading of our block: the small bobber icon of the minimap button in front of the addon name.
local function label()
  return format("|T%s:16:16:0:-2|t ", ns.Icons.Path(ns.Icons.bobber, 64)) .. ns.Colors.Paint("aqua", L["ADDON_NAME"])
end

local AQUA = ns.Colors.aquaHex -- headings of our own data (the game's own headings are green)

--- Section "Zones": names of the zones where the fish was caught (heading + lines), or nil.
local function zonesText(itemID)
  local zones = BJ.API.GetFishZones(itemID, Flavor.RETAIL)
  if #zones == 0 then return nil end
  local lines = {AQUA .. L["Zones with catches:"] .. "|r"}
  for i = 1, math.min(#zones, MAX_ZONES) do lines[#lines + 1] = "- " .. BJ.API.GetZoneName(zones[i].zone) end
  return table.concat(lines, "\n")
end

--- Section "Rates": how often the fish was caught, in total and per zone (heading + lines), or nil.
local function ratesText(itemID)
  local API = BJ.API
  local mine, all = API.GetCaught(itemID, false), API.GetCaught(itemID, true)
  local zones = API.GetFishZones(itemID, Flavor.RETAIL)
  if all == 0 and #zones == 0 then return AQUA .. L["Caught:"] .. "|r\n" .. L["Not caught yet."] end
  local lines = {format("%s%s|r %d", AQUA, L["Caught:"], mine)}
  if #zones > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = AQUA .. L["Zones:"] .. "|r"
    for i = 1, math.min(#zones, MAX_ZONES) do
      local z = zones[i]
      lines[#lines + 1] = format("- %s: %s", API.GetZoneName(z.zone), ns.Format.Value(z.drops, z.chance))
    end
  end
  if all ~= mine then
    lines[#lines + 1] = ""
    lines[#lines + 1] = AQUA .. L["Account values:"] .. "|r"
    for _, c in ipairs(API.GetCharCatches(itemID)) do
      local color = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
      local name = color and ns.Colors.Wrap(color.r, color.g, color.b, c.name) or c.name
      lines[#lines + 1] = format("%s: %d", name, c.caught)
    end
  end
  return table.concat(lines, "\n")
end

--- Section "Recipes": the recipes found that use the fish (heading + lines), or nil.
local function recipesText(itemID)
  local list = BJ.API.GetFishRecipes(itemID)
  if #list == 0 then return nil end
  local lines = {AQUA .. L["Used in recipes:"] .. "|r"}
  for i = 1, math.min(#list, MAX_ZONES) do lines[#lines + 1] = "- " .. list[i].name end
  return table.concat(lines, "\n")
end

--- Sections "In stock" and "Per hour" (the same as in the journal): heading + lines each, or nil.
local function sectionsText(itemID)
  local T = BJ.modules.Tooltip
  local parts = {}
  for _, section in ipairs(T and T.FishSections and T.FishSections(itemID) or {}) do
    parts[#parts + 1] = AQUA .. section[1] .. "|r\n" .. table.concat(section[2], "\n")
  end
  return #parts > 0 and table.concat(parts, "\n\n") or nil
end

--- Rows of the statistics panel next to the page (Bobber's Journal replaces the heading of the game's crafting details):
--- { head = "Heading" } or { left, right }.
local function fishRows(itemID)
  local API = BJ.API
  local mine, all = API.GetCaught(itemID, false), API.GetCaught(itemID, true)
  local zones = API.GetFishZones(itemID, Flavor.RETAIL)
  local rows = {{head = L["Caught:"], right = ns.Format.Count(mine)}}
  if all == 0 and #zones == 0 then rows[#rows + 1] = {left = L["Not caught yet."]} return rows end
  if #zones > 0 then
    rows[#rows + 1] = {head = L["Zones:"]}
    for i = 1, math.min(#zones, MAX_ZONES) do
      rows[#rows + 1] = {left = API.GetZoneName(zones[i].zone), right = ns.Format.Value(zones[i].drops, zones[i].chance)}
    end
  end
  if all ~= mine then
    rows[#rows + 1] = {head = L["Account values:"]}
    for _, c in ipairs(API.GetCharCatches(itemID)) do
      local color = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
      rows[#rows + 1] = {left = color and ns.Colors.Wrap(color.r, color.g, color.b, c.name) or c.name, right = ns.Format.Count(c.caught)}
    end
  end
  return rows
end

local function zoneRows(zone)
  local data = M.ZoneData(zone)
  local rows = {{head = L["Rates:"]}}
  if data.cast == 0 and data.catch == 0 and #data.fish == 0 then rows[#rows + 1] = {left = L["Not caught yet."]} return rows end
  rows[#rows + 1] = {left = L["Casts"], right = ns.Format.Count(data.cast)}
  rows[#rows + 1] = {left = L["Catches"], right = ns.Format.Count(data.catch)}
  if data.cast > 0 then rows[#rows + 1] = {left = L["Catch rate"], right = ns.Format.Percent(data.catch / data.cast)} end
  return rows
end

--- Catch rank of a fish ("Trophy", "Minnow" ...): read from the game's own fish page, where it is the second line of the form
--- "Label: value" (after the fishing score). Saved with the item (m.rk, in the client language) for the lists of the bobber display.
local function labelLines(form)
  local found, seen = {}, {}
  local function take(fs)
    if not (fs.GetText and fs:IsShown()) then return end
    local text = BJ.Clean(fs:GetText())
    if type(text) ~= "string" or not text:find("|c", 1, true) then return end
    local top = tonumber(BJ.Clean(fs:GetTop())) or 0
    local n = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
      n = n + 1
      local value = line:match("^%s*|c%x%x%x%x%x%x%x%x[^|\n]-:|r%s*(.+)$")
      if value then found[#found + 1] = {top = top - n * 0.01, value = value} end
    end
  end
  local function walk(frame, depth)
    if seen[frame] or depth > 4 or (box and (frame == box.scroll or frame == box.content)) then return end
    seen[frame] = true
    for _, region in ipairs({frame:GetRegions()}) do
      if region.GetObjectType and region:GetObjectType() == "FontString" then take(region) end
    end
    for _, child in ipairs({frame:GetChildren()}) do walk(child, depth + 1) end
  end
  walk(form, 0)
  table.sort(found, function(a, b) return a.top > b.top end)
  return found
end

local function saveRank(form, itemID)
  local lines = labelLines(form)
  local rank = lines[2] and lines[2].value
  if not rank then return end
  rank = rank:gsub("%s+$", "")
  if BJ.DB:SetRank(itemID, rank) then BJ:Debug("diary: catch rank of " .. itemID .. " = " .. rank) end
end

--- The block appended to a page of the game: our label and the rates (withZones: the zone names before them).
local function block(itemID, withZones, panel)
  local rates, recipes = not panel and ratesText(itemID) or nil, recipesText(itemID)
  local more = sectionsText(itemID)
  if not (rates or recipes or more or panel) then return nil end
  local parts = {"", label()}
  local zones = withZones and zonesText(itemID)
  if zones then parts[#parts + 1] = "" parts[#parts + 1] = zones end
  if recipes then parts[#parts + 1] = "" parts[#parts + 1] = recipes end
  if more then parts[#parts + 1] = "" parts[#parts + 1] = more end
  if rates then parts[#parts + 1] = "" parts[#parts + 1] = rates end
  return table.concat(parts, "\n")
end

M.Zones, M.Rates, M.Recipes, M.Label, M.Sections = zonesText, ratesText, recipesText, label, sectionsText
M.Block = block

--- Catch rank from the description text of a fish page: the second "Label: value" line (the first is the fishing score).
--- Saved with the item; used by the background scan of Recipes.lua (C_TradeSkillUI.GetRecipeDescription).
function M.SaveRankFromText(itemID, text)
  if type(text) ~= "string" then return end
  local values = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local value = line:match("^%s*|c%x%x%x%x%x%x%x%x[^|\n]-:|r%s*(.+)$")
    if value then values[#values + 1] = value end
  end
  local rank = values[2] and values[2]:gsub("%s+$", "")
  if rank and BJ.DB:SetRank(itemID, rank) then BJ:Debug("diary: catch rank of " .. itemID .. " = " .. rank) end
end
M.FishByName = function(name) return fishByName(name) end

--- uiMapID of a zone by its name: our zones with data first, then every zone map of the game (listed once, lazily).
local zoneNames
local function zoneByName(name)
  for _, z in ipairs(BJ.API.GetZoneList(Flavor.RETAIL)) do
    if z.name == name then return z.zone end
  end
  if not zoneNames then
    zoneNames = {}
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    if C_Map and C_Map.GetMapInfo then
      for id = 1, 4000 do
        local info = C_Map.GetMapInfo(id)
        if info and info.name and (not zoneType or info.mapType == zoneType) and not zoneNames[info.name] then zoneNames[info.name] = id end
      end
    end
  end
  return zoneNames[name]
end

--- Parent maps of a map (set of uiMapIDs).
local function ancestors(key)
  local set, id = {}, key
  for _ = 1, 8 do
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    id = info and info.parentMapID
    if not id or id == 0 then break end
    set[id] = true
  end
  return set
end

--- The zone and all sub maps below it that have catch data (the game's zone pages cover them all).
function M.Family(zone)
  local keys = {zone}
  for _, z in ipairs(BJ.API.GetZoneList(Flavor.RETAIL)) do
    if z.zone ~= zone and ancestors(z.zone)[zone] then keys[#keys + 1] = z.zone end
  end
  return keys
end

--- Fish, chances and casts of a zone added up over the zone and its sub maps:
--- { fish = { { itemID, drops, chance, spot = { key, x, y, n } }, ... }, cast, catch }.
function M.ZoneData(zone)
  local API = BJ.API
  local drops, spots, looted, cast, catch = {}, {}, 0, 0, 0
  for _, key in ipairs(M.Family(zone)) do
    looted = looted + API.GetZoneCatches(key)
    local t = API.GetTotals(key, true)
    -- the zone's loot count is account wide and also covers imported data; every catch was a cast
    local caught = math.max(t.catch, API.GetZoneCatches(key))
    cast, catch = cast + math.max(t.cast, caught), catch + caught
    for _, f in ipairs(API.GetZoneFish(key, Flavor.RETAIL)) do
      if not API.IsJunk(f.itemID) then drops[f.itemID] = (drops[f.itemID] or 0) + f.drops end
    end
    -- best spot per fish: the spot where it was caught most often (coordinates belong to the map of that spot)
    for _, spot in ipairs(API.GetZoneSpots(key, nil, Flavor.RETAIL)) do
      for id, n in pairs(spot.fish) do
        if not spots[id] or n > spots[id].n then spots[id] = {key = key, x = spot.x, y = spot.y, n = n} end
      end
    end
  end
  local fish = {}
  for id, n in pairs(drops) do
    fish[#fish + 1] = {itemID = id, drops = n, chance = looted > 0 and math.min(n / looted, 1) or 0, spot = spots[id]}
  end
  table.sort(fish, function(a, b) return a.drops > b.drops end)
  return {fish = fish, cast = cast, catch = catch}
end

--- The block for a zone page of the game as two texts of equal line structure: the body and a right column with the
--- coordinates (right aligned, like on our own pages). A click on a fish name or its coordinates starts a TomTom route
--- when it is loaded (see DiaryList.RouteClick). Sub maps are added up.
local function zoneBlock(zone, panel)
  local data = M.ZoneData(zone)
  local hasTomTom = _G.TomTom and _G.TomTom.AddWaypoint
  local lines = {{label()}}
  if #data.fish == 0 and data.cast == 0 and data.catch == 0 then
    if not panel then -- (with the statistics panel the page keeps only the label)
      lines[#lines + 1] = {""}
      lines[#lines + 1] = {AQUA .. L["Rates:"] .. "|r"}
      lines[#lines + 1] = {L["Not caught yet."]}
    end
  else
    if #data.fish > 0 then
      lines[#lines + 1] = {""}
      lines[#lines + 1] = {AQUA .. L["Fish in this zone:"] .. "|r"}
      for _, f in ipairs(data.fish) do
        local name = BJ.DB:ItemName(f.itemID) or ("#" .. f.itemID)
        local r, g, b = BJ.DB:ItemColor(f.itemID)
        local colored = ns.Colors.Wrap(r, g, b, name)
        local coords = ""
        local spot = f.spot
        if spot then
          coords = format("|cffffd100[%.1f, %.1f]|r", spot.x * 100, spot.y * 100)
          if hasTomTom then
            local link = format("|Hbjroute:%d:%d|h", spot.key, f.itemID)
            coords = link .. coords .. "|h"
            colored = link .. colored .. "|h"
          end
        end
        lines[#lines + 1] = {format("- %s: %s", colored, ns.Format.Value(f.drops, f.chance)), coords}
      end
    end
    if not panel then
      lines[#lines + 1] = {""}
      lines[#lines + 1] = {AQUA .. L["Rates:"] .. "|r"}
      lines[#lines + 1] = {format(L["Casts: %d"], data.cast)}
      lines[#lines + 1] = {format(L["Catches: %d"], data.catch)}
    end
  end
  local body, right, any = {}, {}, false
  for i, l in ipairs(lines) do
    body[i] = l[1]
    right[i] = l[2] or ""
    if right[i] ~= "" then any = true end
  end
  return table.concat(body, "\n"), any and table.concat(right, "\n") or nil
end

-- Long pages scroll: the description of the game moves into a scroll frame of ours (and back on other pages), so the text
-- we add below it stays reachable. The frame lies on the place of the description down to the bottom of the form.

local function attachLinks(frame)
  frame:SetHyperlinksEnabled(true)
  frame:SetScript("OnHyperlinkEnter", function(self, link)
    local zone, id = link:match("^bjroute:(%d+):(%d+)")
    local list = BJ.modules.DiaryList
    if zone and list and list.RouteTip then BJ.Protected("diary route tip", list.RouteTip, self, tonumber(zone), tonumber(id)) end
  end)
  frame:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  frame:SetScript("OnHyperlinkClick", function(self, link, _, button)
    local zone, id = link:match("^bjroute:(%d+):(%d+)")
    local list = BJ.modules.DiaryList
    if zone and list and list.RouteClick then BJ.Protected("diary route", list.RouteClick, self, tonumber(zone), tonumber(id), button) end
  end)
end

local function textFields(content, desc)
  local body, right = content:CreateFontString(nil, "ARTWORK"), content:CreateFontString(nil, "ARTWORK")
  for _, fs in ipairs({body, right}) do
    fs:SetFontObject(desc:GetFontObject() or "GameFontHighlightSmall2")
    fs:SetSpacing(desc:GetSpacing() or 3)
    fs:SetJustifyV("TOP")
  end
  body:SetJustifyH("LEFT")
  right:SetJustifyH("RIGHT")
  return body, right
end

--- The scroll frame of the game that holds the description (an ancestor), if the page has one. Then our block goes INTO
--- that frame and its scrollbar scrolls everything; without one our own scroll box is used.
local function nativeScroll(desc)
  local f, chain = desc:GetParent(), {}
  for _ = 1, 8 do
    if not f then break end
    local kind = f.GetObjectType and f:GetObjectType() or "?"
    chain[#chain + 1] = kind .. ":" .. tostring(f.GetName and f:GetName() or f.GetParentKey and f:GetParentKey() or "")
    if kind == "ScrollFrame" and f.GetScrollChild and f:GetScrollChild() then
      BJ:Debug("diary: scroll frame of the game found: " .. table.concat(chain, " < "))
      return f
    end
    f = f.GetParent and f:GetParent()
  end
  BJ:Debug("diary: no scroll frame of the game above the description: " .. table.concat(chain, " < "))
  return nil
end

local function ensureBox(form)
  if box then return box end
  local desc = form.Description
  local point, rel, relPoint, x, y = desc:GetPoint(1)
  if not point then return nil end
  box = {parent = desc:GetParent(), points = {}, desc = desc, inset = 28}
  for i = 1, desc:GetNumPoints() do box.points[i] = {desc:GetPoint(i)} end
  local native = nativeScroll(desc)
  if native then
    box.native = native
    box.content = CreateFrame("Frame", nil, box.parent)
    box.content:SetSize(460, 10)
    attachLinks(box.content)
    box.body, box.right = textFields(box.content, desc)
    box.content:Hide()
    return box
  end
  box.scroll = CreateFrame("Frame", nil, form) -- clips its content; scrolled by hand (offset of the content), no ScrollFrame logic
  box.scroll:SetClipsChildren(true)
  box.scroll:SetPoint(point, rel, relPoint, x, y)
  box.scroll:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -28, 14)
  -- above the frames of the form (its background art and border), like our own pages of the Classic list
  box.scroll:SetFrameLevel(form:GetFrameLevel() + 10)
  -- the NineSlice border panel of the form lay over our scrollbar and swallowed the clicks: one strata above the form
  local STRATA = {"BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP"}
  local above = form:GetFrameStrata()
  for i, name in ipairs(STRATA) do if name == above then above = STRATA[math.min(i + 1, #STRATA)] break end end
  box.scroll:SetFrameStrata(above)
  -- our area lies where the game puts its description: the anchor is taken over every time the game sets it (it differs
  -- from page to page and moves with the title), instead of staying at the place of the first page
  box.form = form
  function box.track()
    local p, relTo, relPoint, px, py = desc:GetPoint(1)
    if not p or relTo == box.content then return end
    box.scroll:ClearAllPoints()
    box.scroll:SetPoint(p, relTo, relPoint, px, py)
    box.scroll:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -box.inset, 14)
  end
  function box.reinset() box.scroll:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -box.inset, 14) end
  -- own scrollbar in the look of the game's minimal scroll bar (same atlases): arrows, track, thumb
  local bar = CreateFrame("Frame", nil, form)
  bar:SetFrameStrata(above)
  bar:SetFrameLevel(form:GetFrameLevel() + 11)
  bar:SetWidth(17)
  bar:SetPoint("TOPLEFT", box.scroll, "TOPRIGHT", 4, 0)
  bar:SetPoint("BOTTOMLEFT", box.scroll, "BOTTOMRIGHT", 4, 0)
  local track = CreateFrame("Frame", nil, bar)
  track:SetWidth(8)
  track:SetPoint("TOP", bar, "TOP", 0, -19)
  track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 19)
  local tBegin, tEnd, tMid = track:CreateTexture(nil, "ARTWORK"), track:CreateTexture(nil, "ARTWORK"), track:CreateTexture(nil, "ARTWORK")
  tBegin:SetAtlas("minimal-scrollbar-track-top", true) tBegin:SetPoint("TOPLEFT")
  tEnd:SetAtlas("minimal-scrollbar-track-bottom", true) tEnd:SetPoint("BOTTOMLEFT")
  tMid:SetAtlas("!minimal-scrollbar-track-middle", true)
  tMid:SetPoint("TOPLEFT", tBegin, "BOTTOMLEFT") tMid:SetPoint("BOTTOMRIGHT", tEnd, "TOPRIGHT")
  local thumb = CreateFrame("Frame", nil, track)
  thumb:SetWidth(8)
  thumb:EnableMouse(true)
  local parts = {thumb:CreateTexture(nil, "ARTWORK"), thumb:CreateTexture(nil, "ARTWORK"), thumb:CreateTexture(nil, "ARTWORK")}
  parts[1]:SetPoint("TOPLEFT") parts[3]:SetPoint("BOTTOMLEFT")
  parts[2]:SetPoint("TOPLEFT", parts[1], "BOTTOMLEFT") parts[2]:SetPoint("BOTTOMRIGHT", parts[3], "TOPRIGHT")
  local function paintThumb(state) -- "" / "-over" / "-down"
    parts[1]:SetAtlas("minimal-scrollbar-small-thumb-top" .. state, true)
    parts[2]:SetAtlas("minimal-scrollbar-small-thumb-middle" .. state, true)
    parts[3]:SetAtlas("minimal-scrollbar-small-thumb-bottom" .. state, true)
  end
  paintThumb("")
  bar:Hide()
  box.bar = bar
  local scroll = box.scroll
  local offset = 0
  local function range()
    local r = ((box.content and box.content:GetHeight()) or 0) - (scroll:GetHeight() or 0)
    -- what is really drawn counts, too: how far our text reaches below the visible area (the estimate may be too short)
    -- measured from the top of the content (not the scroll position), so the value does not change while scrolling
    local bodyBottom, contentTop = box.body and box.body:IsShown() and box.body:GetBottom(), box.content and box.content:GetTop()
    if bodyBottom and contentTop then r = math.max(r, contentTop - bodyBottom + 12 - (scroll:GetHeight() or 0)) end
    return math.max(r, 0)
  end
  local sync
  local function scrollTo(v)
    offset = math.min(math.max(v, 0), range())
    if box.content then
      box.content:ClearAllPoints()
      box.content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, offset)
      -- the layout of the game sets the anchor of its description to the form again and again; our text hangs on the
      -- description, so it is tied to our content again with every step (else the page would stand still)
      local d = box.desc
      if d and d:GetParent() == box.content then
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", box.content, "TOPLEFT", 0, 0)
      end
    end
    sync()
  end
  function sync()
    local r, h = range(), track:GetHeight() or 0
    bar:SetShown(r > 1)
    if r <= 1 or h <= 0 then return end
    local view = scroll:GetHeight() or h
    local th = math.max(23, h * view / (view + r))
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -(h - th) * math.min(offset / r, 1))
  end
  box.sync = function() scrollTo(offset) end
  box.setOffset = scrollTo
  -- arrow buttons step the page
  local function arrow(name, point, step)
    local btn = CreateFrame("Button", nil, bar)
    btn:SetSize(17, 11)
    btn:SetPoint(point)
    local tex = btn:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetAtlas("minimal-scrollbar-arrow-" .. name)
    btn:SetScript("OnEnter", function() tex:SetAtlas("minimal-scrollbar-arrow-" .. name .. "-over") end)
    btn:SetScript("OnLeave", function() tex:SetAtlas("minimal-scrollbar-arrow-" .. name) end)
    btn:SetScript("OnMouseDown", function() tex:SetAtlas("minimal-scrollbar-arrow-" .. name .. "-down") scrollTo(offset + step) end)
    btn:SetScript("OnMouseUp", function() tex:SetAtlas("minimal-scrollbar-arrow-" .. name .. "-over") end)
  end
  arrow("top", "TOP", -32)
  arrow("bottom", "BOTTOM", 32)
  scroll:SetScript("OnSizeChanged", function() box.sync() end)
  local function wheel(_, delta)
    if not box.wheelSeen then box.wheelSeen = true BJ:Debug("diary: mouse wheel reaches our page") end
    scrollTo(offset - delta * 32)
  end
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", wheel)
  bar:EnableMouseWheel(true)
  bar:SetScript("OnMouseWheel", wheel)
  thumb:SetScript("OnEnter", function() paintThumb("-over") end)
  thumb:SetScript("OnLeave", function(self) if not self.dragging then paintThumb("") end end)
  thumb:SetScript("OnMouseDown", function(self)
    self.dragging = true
    BJ:Debug("diary: scrollbar thumb clicked")
    paintThumb("-down")
    local scale = self:GetEffectiveScale()
    local startY, startV = select(2, GetCursorPosition()) / scale, offset
    self:SetScript("OnUpdate", function() -- only while the thumb is dragged
      local travel = (track:GetHeight() or 0) - (self:GetHeight() or 0)
      if travel > 0 then scrollTo(startV + (startY - select(2, GetCursorPosition()) / scale) * range() / travel) end
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self) self.dragging = false self:SetScript("OnUpdate", nil) paintThumb(self:IsMouseOver() and "-over" or "") end)
  box.content = CreateFrame("Frame", nil, box.scroll)
  box.content:SetSize(480, 10)
  box.content:EnableMouseWheel(true)
  box.content:SetScript("OnMouseWheel", wheel)
  box.content:SetPoint("TOPLEFT", box.scroll, "TOPLEFT", 0, 0)
  attachLinks(box.content)
  box.body, box.right = textFields(box.content, desc)
  -- whenever the game anchors its description again (its layout does so after loading), it goes back onto our content
  hooksecurefunc(desc, "SetPoint", function()
    if box.fixing or desc:GetParent() ~= box.content then return end
    box.fixing = true
    box.track()
    desc:ClearAllPoints()
    desc:SetPoint("TOPLEFT", box.content, "TOPLEFT", 0, 0)
    box.fixing = false
  end)
  box.scroll:Hide()
  return box
end

-- Statistics panel next to the page, in the look of the game's "crafting details" (same atlases), with our own heading
local PANEL_W, PANEL_ROW_H, TEXT_W = 263, 22, 352

local function ensurePanel(form)
  if box.panel then return box.panel end
  local pnl = CreateFrame("Frame", nil, form)
  pnl:SetSize(PANEL_W, 199)
  pnl:SetFrameStrata(box.scroll:GetFrameStrata())
  pnl:SetFrameLevel(form:GetFrameLevel() + 10)
  local top, bottom, mid = pnl:CreateTexture(nil, "BACKGROUND"), pnl:CreateTexture(nil, "BACKGROUND"), pnl:CreateTexture(nil, "BACKGROUND")
  top:SetAtlas("Professions-QualityPane-bg-top") top:SetSize(PANEL_W, 100) top:SetPoint("TOP")
  bottom:SetAtlas("Professions-QualityPane-bg-bottom") bottom:SetSize(PANEL_W, 100) bottom:SetPoint("BOTTOM", 0, -1)
  mid:SetAtlas("Professions-QualityPane-bg-middle")
  mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT") mid:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT")
  mid:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT") mid:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
  local title = pnl:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  title:SetPoint("TOP", 0, -25)
  title:SetText("|T" .. ns.Icons.Path(ns.Icons.bobber, 64) .. ":16:16:0:-2|t " .. ns.Colors.Paint("aqua", L["ADDON_NAME"]))
  local line = pnl:CreateTexture(nil, "ARTWORK")
  line:SetAtlas("Professions-QualityPane-Divider", true)
  line:SetPoint("TOP", 0, -50)
  pnl.rows = {}
  function pnl.fill(rows)
    for i, row in ipairs(rows) do
      local fs = pnl.rows[i]
      if not fs then
        fs = {left = pnl:CreateFontString(nil, "ARTWORK", "GameFontHighlight"), right = pnl:CreateFontString(nil, "ARTWORK", "GameFontHighlight")}
        fs.left:SetJustifyH("LEFT") fs.right:SetJustifyH("RIGHT")
        pnl.rows[i] = fs
      end
      local y = -62 - (i - 1) * PANEL_ROW_H
      fs.left:ClearAllPoints() fs.left:SetPoint("TOPLEFT", pnl, "TOPLEFT", 26, y)
      fs.right:ClearAllPoints() fs.right:SetPoint("TOPRIGHT", pnl, "TOPRIGHT", -26, y)
      fs.left:SetText(row.head and ns.Colors.Paint("aqua", row.head) or row.left or "")
      fs.right:SetText(row.right or "")
      fs.left:Show() fs.right:Show()
    end
    for i = #rows + 1, #pnl.rows do pnl.rows[i].left:Hide() pnl.rows[i].right:Hide() end
    pnl:SetHeight(math.max(199, 62 + #rows * PANEL_ROW_H + 24))
  end
  box.panel = pnl
  return pnl
end

--- The panel sits at the right edge of the form, level with the top of our scroll area (which is narrower then).
local function placePanel(form)
  local pnl, scroll = box.panel, box.scroll
  if not (pnl and pnl:IsShown()) then return end
  local sTop, fTop = scroll:GetTop(), form:GetTop()
  pnl:ClearAllPoints()
  pnl:SetPoint("TOPRIGHT", form, "TOPRIGHT", -12, (sTop and fTop) and (sTop - fTop + 4) or -90)
end

local function setPanel(form, rows)
  if rows then
    local left = (box.scroll:GetLeft() and form:GetLeft()) and (box.scroll:GetLeft() - form:GetLeft()) or 20
    box.inset = math.max((form:GetWidth() or 793) - left - (TEXT_W + 8), 60)
    box.reinset()
    ensurePanel(form).fill(rows)
    box.panel:Show()
    placePanel(form)
  else
    if box.panel then box.panel:Hide() end
    box.inset = 28
    box.reinset()
  end
end

local GAP = 14

local function moveIn(form, key, bodyText, rightText, rows)
  local b = ensureBox(form)
  if not b then return end
  local desc = form.Description
  if b.native then
    local width = math.max(desc:GetWidth(), 10)
    b.content:ClearAllPoints()
    b.content:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -GAP)
    b.body:ClearAllPoints()
    b.body:SetPoint("TOPLEFT", b.content, "TOPLEFT", 0, 0)
    b.body:SetWidth(width)
    b.body:SetText(bodyText)
    b.right:ClearAllPoints()
    b.right:SetPoint("TOPLEFT", b.content, "TOPLEFT", 0, 0)
    b.right:SetWidth(width)
    b.right:SetText(rightText or "")
    b.right:SetShown(rightText ~= nil)
    local height = (b.body:GetStringHeight() or 0) + 4
    b.content:SetSize(width, height)
    b.content:Show()
    -- the scroll child of the game must be long enough for our block: grow it, remember the original length
    local child = b.native:GetScrollChild()
    local top, bottom = child:GetTop(), desc:GetBottom()
    if top and bottom then
      b.baseHeight = b.baseHeight or child:GetHeight()
      child:SetHeight(math.max(b.baseHeight, top - bottom + GAP + height + 16))
      b.native:UpdateScrollChildRect()
    end
    b.key = key
    return
  end
  if desc:GetParent() ~= b.content then
    b.track()
    desc:SetParent(b.content)
    desc:ClearAllPoints()
    desc:SetPoint("TOPLEFT", b.content, "TOPLEFT", 0, 0)
  end
  setPanel(form, rows)
  local width = math.max(desc:GetWidth(), 10)
  if rows then
    -- narrower text next to the panel: the description of the game follows (its height is set again for the new width)
    width = TEXT_W
    desc:SetWidth(width)
    desc:SetHeight((desc:GetStringHeight() or 0) + 1)
  end
  b.body:ClearAllPoints()
  b.body:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -GAP)
  b.body:SetWidth(width)
  b.body:SetText(bodyText)
  b.body:Show()
  b.right:ClearAllPoints()
  b.right:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -GAP)
  b.right:SetWidth(width)
  b.right:SetText(rightText or "")
  b.right:SetShown(rightText ~= nil)
  b.scroll:Show()
  -- length of the content: the text of the game may be longer than the height the game gave its field, so both count;
  -- measured again a moment later, when the layout is done
  local function measure()
    local descH = math.max(desc:GetHeight() or 0, desc:GetStringHeight() or 0)
    local bodyH = b.body:GetStringHeight() or 0
    b.content:SetSize(width + 8, descH + GAP + bodyH + 24)
    BJ:Debug(format("diary: content %.0f (description %.0f/%.0f, our text %.0f), viewport %.0f", b.content:GetHeight(), desc:GetHeight() or 0,
      desc:GetStringHeight() or 0, bodyH, b.scroll:GetHeight() or 0))
    placePanel(form)
    b.sync()
  end
  measure()
  if b.key ~= key then b.key = key b.setOffset(0) end
  if C_Timer then C_Timer.After(0.1, function() BJ.Protected("diary measure", measure) end) end
end

local function moveOut(form)
  if box and box.native then
    box.content:Hide()
    if box.baseHeight then
      box.native:GetScrollChild():SetHeight(box.baseHeight)
      box.baseHeight = nil
      box.native:UpdateScrollChildRect()
    end
    box.key = nil
    return
  end
  if not (box and form.Description:GetParent() == box.content) then return end
  local desc = form.Description
  desc:SetParent(box.parent)
  desc:ClearAllPoints()
  for _, pt in ipairs(box.points) do desc:SetPoint(unpack(pt)) end
  box.scroll:Hide()
  box.bar:Hide()
  setPanel(form, nil)
  box.body:Hide()
  box.right:Hide()
  box.key = nil
end

local function onUpdate(form)
  local info = form.currentRecipeInfo
  local body, right, key, rows
  if BJ.settings.diary and info and info.isDummyRecipe and type(info.name) == "string" then
    local itemID = fishByName(info.name)
    if itemID then
      saveRank(form, itemID)
      body, key, rows = block(itemID, false, true), "fish" .. itemID, fishRows(itemID)
      if body then body = body:gsub("^\n", "") end
    else
      local zone = zoneByName(info.name)
      if zone then body, right = zoneBlock(zone, true) key = "zone" .. zone rows = zoneRows(zone) end
    end
  end
  BJ:Debug(format("diary: page %s, dummy %s, extra text %s", tostring(info and info.name), tostring(info and info.isDummyRecipe), tostring(body ~= nil)))
  if not body then moveOut(form) return end
  form.Description:Show()
  moveIn(form, key, body, right, rows)
end

local function hook()
  if hooked then return end
  local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
  if not (form and form.UpdateRecipeDescription and form.Description) then return end
  hooked = true
  hooksecurefunc(form, "UpdateRecipeDescription", function(self)
    BJ.Protected("diary", onUpdate, self)
  end)
  -- second trigger: the page is built by Init; a frame later the text of the game is certainly set
  if form.Init then
    hooksecurefunc(form, "Init", function(self)
      if C_Timer then C_Timer.After(0, function() BJ.Protected("diary", onUpdate, self) end) end
    end)
  end
  preloadNames()
end

--- State for /bob probe: the hook, the open page, what we matched it to and how long our block is.
function M.Probe()
  local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
  local info = form and form.currentRecipeInfo
  local name = info and info.name
  local fishID = type(name) == "string" and fishByName(name)
  local zone = type(name) == "string" and not fishID and zoneByName(name)
  local extra = fishID and block(fishID) or (zone and (zoneBlock(zone))) or nil
  local known = {}
  for _, z in ipairs(BJ.API.GetZoneList(Flavor.RETAIL)) do known[#known + 1] = z.zone .. "=" .. tostring(z.name) end
  local geo = "none"
  if box and box.native then
    geo = "scroll frame of the game, content " .. format("%.0fx%.0f", box.content:GetWidth() or 0, box.content:GetHeight() or 0)
  elseif box then
    local w, h = box.scroll:GetSize()
    local desc = form and form.Description
    geo = format("%.0fx%.0f shown %s level %s, content %.0fx%.0f, text %d chars, text visible %s", w or 0, h or 0, tostring(box.scroll:IsVisible()),
      tostring(box.scroll:GetFrameLevel()), box.content:GetWidth() or 0, box.content:GetHeight() or 0, desc and #(desc:GetText() or "") or 0,
      tostring(desc and desc:IsVisible()))
  end
  return format("diary: hooked %s, form %s, page %s, dummy %s, setting %s, fish %s, zone %s, block %s chars, scroll %s (%s); zones with data: %s",
    tostring(hooked), tostring(form ~= nil), tostring(name), tostring(info and info.isDummyRecipe), tostring(BJ.settings.diary),
    tostring(fishID), tostring(zone), tostring(extra and #extra or 0), tostring(box and (box.native and box.content:IsShown() or box.scroll and box.scroll:IsShown())), geo, table.concat(known, ", "))
end

--- Called by the options: redraws the open page.
function M.Refresh()
  local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
  if hooked and form and form:IsVisible() and form.UpdateRecipeDescription then BJ.Protected("diary", form.UpdateRecipeDescription, form) end
end

function M:OnEnable()
  if Flavor.current ~= Flavor.RETAIL then return end
  hook()
  BJ:RegisterEvent("ADDON_LOADED", "diary", function(_, addon)
    if addon == "Blizzard_Professions" then hook() end
  end)
end
