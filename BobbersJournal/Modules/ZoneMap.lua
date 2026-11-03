local _, ns = ...
local BJ = ns.BJ
local L = BJ.L
-- Zone map on the journal page of a zone: the zone's map art drawn like ink on the parchment (desaturated, sepia),
-- one marker per fishing spot showing the icon of the fish caught there most often. Junk and non-crafting catches are
-- left out. Mouseover lists what was caught; a right click opens a menu (TomTom waypoint / route, hide spot).
-- The map art comes from C_Map.GetMapArtLayers/GetMapArtLayerTextures (tiles); without it a plain sheet is drawn.
local M = BJ:RegisterModule("ZoneMap")

local MAP_W, MAP_H = 440, 500 -- fallback size of the page area
local MARKER = 24
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local root, zone
local selected = {} -- itemID -> true: fish chosen in the journal list; they filter the spots (default all; none chosen: no spots)
local tiles, markers, glows, cells, cellMasks = {}, {}, {}, {}, {}
local npcMarkers = {} -- vendors and teachers of the vendors tab
local subName -- sub zone shown highlighted (nil: the whole zone)

local function itemName(id)
  local n = BJ.DB:ItemName(id)
  if not n and GetItemInfo then n = GetItemInfo(id) end
  return n or ("#" .. id)
end

local function hiddenSet()
  BJ.settings.hiddenSpots = BJ.settings.hiddenSpots or {}
  return BJ.settings.hiddenSpots
end
local function spotKey(z, s) return format("%d:%.3f:%.3f", z, s.x, s.y) end

-- Spots with only crafting-material fish, best fish first. fish = {{id, n}, ...}
local function collectSpots(z)
  local A, out, hidden = BJ.API, {}, hiddenSet()
  local points = subName and A.GetSubZonePoints(z, subName)
  local r2 = (BJ.DB.SPOT_RADIUS * 1.5) ^ 2
  for _, s in ipairs(A.GetZoneSpots(z)) do
    local inSub = true
    if points then
      inSub = s.subs and s.subs[subName] ~= nil
      if not inSub then
        for _, p in ipairs(points) do
          local dx, dy = p.x - s.x, p.y - s.y
          if dx * dx + dy * dy <= r2 then inSub = true break end
        end
      end
    end
    if inSub then
    local fish, total = {}, 0
    for id, n in pairs(s.fish) do
      if not A.IsJunk(id) then fish[#fish + 1] = {id = id, n = n} total = total + n end
    end
    table.sort(fish, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.id < b.id end)
    if #fish > 0 then out[#out + 1] = {x = s.x, y = s.y, fish = fish, total = total, key = spotKey(z, s), hidden = hidden[spotKey(z, s)]} end
    end
  end
  return out
end


-- Catches of the chosen fish at a spot (all fish when none is chosen); 0 means the spot is filtered out.
local function weight(s, ids)
  local sum = 0
  for _, f in ipairs(s.fish) do if not ids or ids[f.id] then sum = sum + f.n end end
  return sum
end
local filtered = false -- false: all fish are chosen (default); true: only those in `selected` (none = no spots)
local function chosen() return filtered and selected or nil end

--- TomTom helpers (only when the addon is loaded)
local function tomtom() return _G.TomTom and _G.TomTom.AddWaypoint and _G.TomTom end

local function addWaypoint(x, y, title)
  tomtom():AddWaypoint(zone, x, y, {title = title, persistent = false, minimap = true, world = true})
end

local function route(list, title)
  local tt = tomtom()
  if #list == 0 then return end
  if tt.ClearAllWaypoints then tt:ClearAllWaypoints() end
  -- nearest neighbour order, starting at the player when on this map, else with the richest spot
  local px, py
  if C_Map and C_Map.GetPlayerMapPosition then
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, zone, "player")
    if ok and pos and pos.GetXY then px, py = pos:GetXY() end
  end
  local rest = {unpack(list)}
  local cx, cy = px, py
  while #rest > 0 do
    local best, bi = nil, 1
    for i, s in ipairs(rest) do
      local d = cx and ((s.x - cx) ^ 2 + (s.y - cy) ^ 2) or -s.total
      if not best or d < best then best, bi = d, i end
    end
    local s = table.remove(rest, bi)
    addWaypoint(s.x, s.y, title)
    cx, cy = s.x, s.y
  end
  if tt.SetClosestWaypoint then pcall(tt.SetClosestWaypoint, tt) end
end

local function openMenu(owner, entries)
  if #entries == 0 then return end
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner, function(_, menu)
      for _, e in ipairs(entries) do menu:CreateButton(e.text, e.func) end
    end)
  elseif EasyMenu then
    M.menuFrame = M.menuFrame or CreateFrame("Frame", "BobbersJournalMapMenu", UIParent, "UIDropDownMenuTemplate")
    local list = {}
    for _, e in ipairs(entries) do list[#list + 1] = {text = e.text, func = e.func, notCheckable = true} end
    EasyMenu(list, M.menuFrame, "cursor", 0, 0, "MENU")
  end
end

local function refreshMarkers() if root and root:IsShown() then M.Show(root:GetParent(), zone, root.top) end end

local function showTip(m)
  local s = m.spot
  GameTooltip:SetOwner(m, "ANCHOR_RIGHT")
  GameTooltip:AddLine(ns.Colors.Paint("aqua", BJ.API.GetZoneName(zone)))
  for _, f in ipairs(s.fish) do
    local qr, qg, qb = BJ.DB:ItemColor(f.id)
    GameTooltip:AddDoubleLine(itemName(f.id), "x" .. f.n, qr or 1, qg or 1, qb or 1, 1, 1, 1)
    BJ:DebugTip(GameTooltip, "Item", f.id)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(format("%.1f / %.1f", s.x * 100, s.y * 100), 0.7, 0.7, 0.7)
  GameTooltip:AddLine(L["Right click: menu"], 0.26, 0.69, 1)
  GameTooltip:Show()
  BJ:DebugTip(GameTooltip, "Zone", zone, "Spot", s.key)
end

local function menuFor(m)
  local s, entries = m.spot, {}
  local ids = chosen() or {[s.fish[1].id] = true}
  local name = ""
  for id in pairs(ids) do name = name == "" and itemName(id) or (name .. ", " .. itemName(id)) end
  local function matching()
    local list = {}
    for _, o in ipairs(collectSpots(zone)) do if not o.hidden and weight(o, ids) > 0 then list[#list + 1] = o end end
    return list
  end
  if tomtom() then
    entries[#entries + 1] = {text = L["Set waypoint (TomTom)"], func = function() addWaypoint(s.x, s.y, name) end}
    entries[#entries + 1] = {text = L["Route to all spots of this fish"], func = function() route(matching(), name) end}
    entries[#entries + 1] = {text = L["Route to the best 5 spots"], func = function()
      local list = matching()
      table.sort(list, function(a, b) return weight(a, ids) > weight(b, ids) end)
      while #list > 5 do table.remove(list) end
      route(list, name)
    end}
  end
  entries[#entries + 1] = {text = L["Hide spot"], func = function() hiddenSet()[s.key] = true refreshMarkers() end}
  if next(hiddenSet()) then
    entries[#entries + 1] = {text = L["Show hidden spots again"], func = function() wipe(hiddenSet()) refreshMarkers() end}
  end
  return entries
end

local function marker(i)
  local m = markers[i]
  if m then return m end
  m = CreateFrame("Button", nil, root.canvas)
  m:SetSize(MARKER, MARKER)
  m.tex = m:CreateTexture(nil, "ARTWORK")
  m.tex:SetAllPoints()
  -- Atlas "Professions_Tracking_Fish" (the fish glyph of the minimap tracking); where the client lacks it, the icon of
  -- "Find Fish", and as the last resort the addon's own fish symbol.
  local ok = m.tex.SetAtlas and pcall(m.tex.SetAtlas, m.tex, "Professions_Tracking_Fish", false)
  if ok and m.tex:GetAtlas() then
    -- atlas set
  else
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(43308) or (GetSpellTexture and GetSpellTexture(43308))
    if icon then
      m.tex:SetTexture(icon)
      local mask = m:CreateMaskTexture()
      mask:SetAllPoints(m.tex) mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      m.tex:AddMaskTexture(mask)
    else
      m.tex:SetTexture(ns.Icons.Path(ns.Icons.fish, 64))
    end
  end
  function m:Ink(on)
    self.tex:SetDesaturated(not on) -- hover: grey base so the green tint is clean
    if on then self.tex:SetVertexColor(1, 1, 1) self.tex:SetAlpha(1) -- original yellow of the game icon
    else self.tex:SetVertexColor(0.1, 0.55, 0.55) self.tex:SetAlpha(1) end
  end
  m:Ink(true)
  m:SetFrameLevel(root.canvas:GetFrameLevel() + 5)
  m:RegisterForClicks("RightButtonUp")
  m:SetScript("OnEnter", function(self) self:Ink(false) showTip(self) end)
  m:SetScript("OnLeave", function(self) self:Ink(true) GameTooltip:Hide() end)
  m:SetScript("OnClick", function(self) GameTooltip:Hide() openMenu(self, menuFor(self)) end)
  markers[i] = m
  return m
end

local function create(parent)
  -- The map fills the right page of the book and lies under the texts of the page (level +1; the journal's text layer
  -- is above). Edges fade out transparently through a rectangular mask.
  root = CreateFrame("Frame", nil, parent)
  root:SetPoint("TOPLEFT", parent, "TOP", 12, -60)
  root:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -24, 24)
  root:SetFrameLevel(parent:GetFrameLevel() + 1)
  root.map = CreateFrame("Frame", nil, root)
  root.map:SetAllPoints(root)
  root.map:SetClipsChildren(true)
  -- The canvas holds tiles and markers; it is scaled (zoom) and moved (pan) inside the clipping map frame.
  root.canvas = CreateFrame("Frame", nil, root.map)
  root.canvas:SetPoint("TOPLEFT")
  root.map:EnableMouse(true)
  root.map:EnableMouseWheel(true)
  root.map:SetScript("OnMouseWheel", function(_, delta) M.Zoom(delta) end)
  root.map:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then M.StartPan() end end)
  root.map:SetScript("OnMouseUp", function() M.StopPan() end)
  root.fade = root.map:CreateMaskTexture()
  root.fade:SetAllPoints(root.map)
  root.fade:SetTexture(ns.Icons.maskEdge, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  root.note = root.map:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  root.note:SetPoint("CENTER")
end

-- Map art as tiles (like the world map), scaled so the map fills the page height (and at least the width).
-- Returns the canvas size in pixels.
local function drawMap(z, vw, vh)
  for _, t in ipairs(tiles) do t:Hide() end
  root.note:SetText("")
  local ok = C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures
  local layers = ok and select(2, pcall(C_Map.GetMapArtLayers, z))
  local info = type(layers) == "table" and layers[1]
  if info and info.layerWidth and info.layerWidth > 0 then
    local textures = select(2, pcall(C_Map.GetMapArtLayerTextures, z, 1))
    if type(textures) == "table" and #textures > 0 then
      local scale = math.max(vh / info.layerHeight, vw / info.layerWidth)
      local w, h = info.layerWidth * scale, info.layerHeight * scale
      root.canvas:SetSize(w, h)
      local cols = math.ceil(info.layerWidth / info.tileWidth)
      for i, file in ipairs(textures) do
        local t = tiles[i]
        if not t then t = root.canvas:CreateTexture(nil, "ARTWORK") tiles[i] = t end
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", root.canvas, "TOPLEFT", col * info.tileWidth * scale, -row * info.tileHeight * scale)
        t:SetSize(info.tileWidth * scale, info.tileHeight * scale)
        t:SetTexture(file)
        -- ink on parchment: no colour, brown tint, partly transparent so the paper shows through
        t:SetDesaturated(true)
        t:SetVertexColor(1, 0.608, 0.243) t:SetAlpha(0.62) -- FF9B3E, alpha separately (masked texture)
        if not t.masked then t:AddMaskTexture(root.fade) t.masked = true end
        t:Show()
      end
      return w, h
    end
  end
  root.canvas:SetSize(vw, vh)
  root.note:SetText(L["Map not available"])
  return vw, vh
end

-- Position (normalised 0..1) of the spot with the most catches of the chosen fish (all fish by default); the middle of
-- the map when there is no spot.
local function focusPoint(spots)
  local best, bx, by
  for _, s in ipairs(spots) do
    if not s.hidden then
      local w = weight(s, chosen())
      if w > 0 and (not best or w > best) then best, bx, by = w, s.x, s.y end
    end
  end
  return bx or 0.5, by or 0.5
end

--- Fish chosen in the journal list (multi-select). The list calls these; the map follows on the next Show.
function M.IsSelected(id) return not filtered or selected[id] == true end
function M.Toggle(id)
  M.refocus = true -- the map centres on the best spot of the new choice
  if not filtered then
    -- first click on the default "all chosen": start from all fish of the zone and take this one out
    filtered = true
    wipe(selected)
    for _, o in ipairs(collectSpots(zone)) do for _, f in ipairs(o.fish) do selected[f.id] = true end end
    selected[id] = nil
    return
  end
  if selected[id] then selected[id] = nil else selected[id] = true end
end
--- Show only this fish on the map (the fish page of the journal) and forget the choice again with Clear.
function M.Only(id)
  filtered = true
  wipe(selected)
  selected[id] = true
  M.refocus = true
end
function M.Clear() filtered = false wipe(selected) end
--- Switching to another zone forgets the choice.
function M.SetZone(z) if zone ~= z then wipe(selected) filtered = false zone = z subName = nil end end
--- Sub zone to highlight on the map (nil: whole zone). Only its spots are shown and the map centres on it.
function M.SetSubZone(name)
  if subName ~= name then subName = name M.refocus = true wipe(selected) filtered = false end
end

-- Zoom (mouse wheel, towards the cursor) and pan (left mouse button held): the canvas is scaled and moved inside the
-- map frame. Markers keep their size (inverse scale). The drag uses an OnUpdate only while the button is held.
-- view: canvas size (w, h) at zoom 1, page area (vw, vh), zoom and canvas offset (px, py) in page pixels.
local view = {zoom = 1, px = 0, py = 0, w = MAP_W, h = MAP_H, vw = MAP_W, vh = MAP_H}
local MAX_ZOOM = 8
local FOCUS_ZOOM = 3

local function applyView()
  local z = view.zoom
  -- larger than the page: clamp to the edges; smaller: centred
  local cw, ch = view.w * z, view.h * z
  if cw <= view.vw then view.px = (view.vw - cw) / 2 else view.px = math.min(math.max(view.px, view.vw - cw), 0) end
  if ch <= view.vh then view.py = (view.vh - ch) / 2 else view.py = math.min(math.max(view.py, view.vh - ch), 0) end
  root.canvas:SetScale(z)
  root.canvas:ClearAllPoints()
  root.canvas:SetPoint("TOPLEFT", root.map, "TOPLEFT", view.px / z, -view.py / z)
  for _, pool in ipairs({markers, npcMarkers}) do
    for _, m in ipairs(pool) do
      if m:IsShown() and m.spot then
        m:SetScale(1 / z)
        m:ClearAllPoints()
        m:SetPoint("CENTER", root.canvas, "TOPLEFT", m.spot.x * view.w * z, -m.spot.y * view.h * z)
      end
    end
  end
end

local function cursorInMap()
  local x, y = GetCursorPosition()
  local scale = root.map:GetEffectiveScale()
  return x / scale - root.map:GetLeft(), root.map:GetTop() - y / scale
end

function M.Zoom(delta)
  if not root then return end
  local cx, cy = cursorInMap()
  local old = view.zoom
  local new = math.min(math.max(old * (delta > 0 and 1.25 or 0.8), 1), MAX_ZOOM)
  if new == old then return end
  -- keep the point under the cursor in place
  local ux, uy = (cx - view.px) / old, (cy - view.py) / old
  view.zoom, view.px, view.py = new, cx - ux * new, cy - uy * new
  applyView()
end

function M.StartPan()
  if not root then return end
  -- also at zoom 1: the map is wider than the page, applyView keeps it inside its edges
  local x, y = cursorInMap()
  view.dragX, view.dragY, view.startX, view.startY = x, y, view.px, view.py
  root.map:SetScript("OnUpdate", function()
    -- mouse released outside of the map: stop (only runs while dragging)
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then M.StopPan() return end
    local cx, cy = cursorInMap()
    view.px, view.py = view.startX + (cx - view.dragX), view.startY + (cy - view.dragY)
    applyView()
  end)
end

function M.StopPan()
  if root then root.map:SetScript("OnUpdate", nil) end
end

local RING = 3

--- Marker of a vendor or teacher: the game's icon on a dark disc in a 3 px aqua ring (like the pins of the maps).
local function npcMarker(i)
  local m = npcMarkers[i]
  if m then return m end
  m = CreateFrame("Button", nil, root.canvas)
  m:SetSize(MARKER + 6, MARKER + 6)
  local function disc(tex, size)
    tex:SetPoint("CENTER")
    tex:SetSize(size, size)
    local mask = m:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
  end
  local size = MARKER + 6
  m.disc = m:CreateTexture(nil, "BACKGROUND")
  m.disc:SetColorTexture(unpack(ns.Colors.aqua))
  disc(m.disc, size)
  m.inner = m:CreateTexture(nil, "BORDER")
  m.inner:SetColorTexture(0.05, 0.05, 0.05)
  m.inner:SetAlpha(0.75)
  disc(m.inner, size - 2 * RING)
  m.tex = m:CreateTexture(nil, "ARTWORK")
  m.tex:SetPoint("CENTER")
  m.tex:SetSize((size - 2 * RING) * 0.9, (size - 2 * RING) * 0.9)
  m:SetFrameLevel(root.canvas:GetFrameLevel() + 6)
  m:RegisterForClicks("RightButtonUp")
  m:SetScript("OnEnter", function(self)
    local n = self.npc
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.Colors.Paint("aqua", n.name or ("#" .. n.id)))
    GameTooltip:AddLine(n.trainer and L["Fishing teacher"] or L["Fishing vendor"], 1, 0.82, 0)
    if n.details and n.details.title then GameTooltip:AddLine(n.details.title, 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(format("%.1f / %.1f", n.x * 100, n.y * 100), 0.7, 0.7, 0.7)
    if tomtom() then GameTooltip:AddLine(L["Right click: menu"], 0.26, 0.69, 1) end
    GameTooltip:Show()
    BJ:DebugTip(GameTooltip, "NPC", n.id)
  end)
  m:SetScript("OnLeave", function() GameTooltip:Hide() end)
  m:SetScript("OnClick", function(self)
    GameTooltip:Hide()
    local n = self.npc
    if tomtom() then
      openMenu(self, {{text = L["Set waypoint (TomTom)"], func = function() addWaypoint(n.x, n.y, n.name or "Bobber's Journal") end}})
    end
  end)
  npcMarkers[i] = m
  return m
end

--- Map of a zone with the saved vendors and teachers (list of API.GetNPCs entries of that zone); `selected` is highlighted
--- by a larger marker. Same zoom and pan as the fishing map; a right click on a marker offers the TomTom waypoint.
function M.ShowNPCs(book, z, top, list, selectedID)
  if type(z) ~= "number" or z <= 0 then M.Hide() return end
  if not root then create(book) end
  root:SetParent(book)
  root:SetFrameLevel(book:GetFrameLevel() + 1)
  root.top = top
  local newZone = zone ~= z or M.npcMode ~= true
  M.npcMode = true
  M.SetZone(z)
  local vw, vh = root:GetWidth(), root:GetHeight()
  if not vw or vw < 50 or not vh or vh < 50 then vw, vh = MAP_W, MAP_H end
  local w, h = drawMap(z, vw, vh)
  view.w, view.h, view.vw, view.vh = w, h, vw, vh
  for _, m in ipairs(markers) do m:Hide() end
  for _, g in ipairs(glows) do g:Hide() end
  for _, c in ipairs(cells) do c:Hide() end
  for _, m in ipairs(npcMarkers) do m:Hide() end
  local n, fx, fy = 0, 0.5, 0.5
  for _, npc in ipairs(list) do
    if npc.x and npc.y then
      n = n + 1
      local m = npcMarker(n)
      m.npc, m.spot = npc, {x = npc.x, y = npc.y}
      m.tex:SetTexture(npc.trainer and ns.Icons.teacher or ns.Icons.vendor)
      m:Show()
      if npc.id == selectedID or n == 1 and selectedID == nil then fx, fy = npc.x, npc.y end
    end
  end
  if newZone or M.refocus then
    M.refocus = nil
    view.zoom = 1
    view.px, view.py = vw / 2 - fx * w, vh / 2 - fy * h
  end
  root:Show()
  applyView()
end

function M.Hide() if root then M.npcMode = false root:Hide() end end

--- Shows the map for a zone below the page header; `top` is the y offset (negative) below the book top.
--- Returns nothing; the page rows above are placed by the journal.
function M.Show(book, z, top)
  if type(z) ~= "number" or z <= 0 then M.Hide() return end
  M.npcMode = false
  if not root then create(book) end
  root:SetParent(book)
  root:SetFrameLevel(book:GetFrameLevel() + 1)
  root.top = top
  local newZone = zone ~= z
  M.SetZone(z)
  local vw, vh = root:GetWidth(), root:GetHeight()
  if not vw or vw < 50 or not vh or vh < 50 then vw, vh = MAP_W, MAP_H end
  local w, h = drawMap(z, vw, vh)
  view.w, view.h, view.vw, view.vh = w, h, vw, vh
  for _, m in ipairs(markers) do m:Hide() end
  for _, m in ipairs(npcMarkers) do m:Hide() end
  local spots = collectSpots(z)
  local n = 0
  for _, s in ipairs(spots) do
    if not s.hidden and weight(s, chosen()) > 0 then
      n = n + 1
      local m = marker(n)
      m.spot = s
      m:Show()
    end
  end
  if newZone or M.refocus then
    M.refocus = nil
    -- Start with the map filling the page height and the best spot (most catches) in the middle of the page.
    local fx, fy = focusPoint(spots)
    -- The spot is centred left/right (not necessarily top/bottom). The map cannot be moved beyond its edges, so a spot
    -- near the left or right edge needs some zoom to reach the middle (at most FOCUS_ZOOM).
    local edge = math.max(math.min(fx, 1 - fx), 0.01)
    view.zoom = math.min(math.max(1, vw / (2 * edge * w)), FOCUS_ZOOM)
    view.px, view.py = vw / 2 - fx * w * view.zoom, vh / 2 - fy * h * view.zoom
  end
  -- Highlighted area of the selected sub zone: soft glows around its catch positions
  for _, g in ipairs(glows) do g:Hide() end
  for _, c in ipairs(cells) do c:Hide() end
  local area = subName and BJ.API.GetSubZoneArea and BJ.API.GetSubZoneArea(z, subName)
  if area then
    -- the whole sub zone from the game's exploration data: the shaped overlay pieces of the area, tinted
    local layer, sc, used = area.layer, w / area.layer.layerWidth, 0
    local TW, TH = layer.tileWidth, layer.tileHeight
    for oi, ov in ipairs(area.overlays) do
      -- soft edge: a fading rectangle over the hit area of the overlay, so the area glows and fades out at the rim
      local mask = cellMasks[oi]
      if not mask then mask = root.canvas:CreateMaskTexture() cellMasks[oi] = mask end
      local mw, mh = ov.textureWidth * sc, ov.textureHeight * sc
      mask:SetTexture(ns.Icons.maskEdge, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:ClearAllPoints()
      mask:SetPoint("TOPLEFT", root.canvas, "TOPLEFT", ov.offsetX * sc, -ov.offsetY * sc)
      mask:SetSize(mw, mh)
      local across, down = math.ceil(ov.textureWidth / TW), math.ceil(ov.textureHeight / TH)
      for j = 1, down do
        local ph = (j < down) and TH or ((ov.textureHeight % TH == 0) and TH or ov.textureHeight % TH)
        local fh = TH
        if j == down then fh = 16 while fh < ph do fh = fh * 2 end end
        for k = 1, across do
          local pw = (k < across) and TW or ((ov.textureWidth % TW == 0) and TW or ov.textureWidth % TW)
          local fw = TW
          if k == across then fw = 16 while fw < pw do fw = fw * 2 end end
          local file = ov.fileDataIDs[(j - 1) * across + k]
          if file then
            used = used + 1
            local c = cells[used]
            if not c then
              c = root.canvas:CreateTexture(nil, "ARTWORK", nil, 3)
              cells[used] = c
            end
            if c.mask and c.mask ~= mask then c:RemoveMaskTexture(c.mask) c.mask = nil end
            if not c.mask then c:AddMaskTexture(mask) c.mask = mask end
            c:SetTexture(file)
            c:SetBlendMode("ADD") -- brightens the map like the unmarked parchment instead of darkening it
            c:SetTexCoord(0, pw / fw, 0, ph / fh)
            c:SetDesaturated(true)
            c:SetVertexColor(ns.Colors.aqua[1], ns.Colors.aqua[2], ns.Colors.aqua[3]) -- main colour of the addon, 70 % transparent
            c:SetAlpha(0.3)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", root.canvas, "TOPLEFT", (ov.offsetX + TW * (k - 1)) * sc, -(ov.offsetY + TH * (j - 1)) * sc)
            c:SetSize(pw * sc, ph * sc)
            c:Show()
          end
        end
      end
    end
  elseif subName then
    local size = 0.14 * w
    for i, p in ipairs(BJ.API.GetSubZonePoints(z, subName)) do
      local g = glows[i]
      if not g then
        g = root.canvas:CreateTexture(nil, "ARTWORK", nil, 3)
        g:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
        g:SetBlendMode("ADD")
        g:SetVertexColor(ns.Colors.aqua[1], ns.Colors.aqua[2], ns.Colors.aqua[3]) -- main colour of the addon
        g:SetAlpha(0.3)
        glows[i] = g
      end
      g:SetSize(size, size)
      g:ClearAllPoints()
      g:SetPoint("CENTER", root.canvas, "TOPLEFT", p.x * w, -p.y * h)
      g:Show()
    end
  end
  applyView()
  root:Show()
end
