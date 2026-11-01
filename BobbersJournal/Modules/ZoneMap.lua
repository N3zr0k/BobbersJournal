local _, ns = ...
local BJ = ns.BJ
local L = BJ.L
-- Zone map on the journal page of a zone: the zone's map art drawn like ink on the parchment (desaturated, sepia),
-- one marker per fishing spot showing the icon of the fish caught there most often. Junk and non-crafting catches are
-- left out. Mouseover lists what was caught; a right click opens a menu (TomTom waypoint / route, hide spot).
-- The map art comes from C_Map.GetMapArtLayers/GetMapArtLayerTextures (tiles); without it a plain sheet is drawn.
local M = BJ:RegisterModule("ZoneMap")

local MAP_W, MAP_H = 430, 330
local MARKER = 24
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local INK = {0.36, 0.24, 0.13}

local root, zone
local selected = {} -- itemID -> true: fish chosen in the journal list; they filter the spots (none chosen: all spots)
local tiles, markers = {}, {}

local function itemIcon(id) return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)) or 134400 end
local function itemName(id)
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
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
  for _, s in ipairs(A.GetZoneSpots(z)) do
    local fish, total = {}, 0
    for id, n in pairs(s.fish) do
      if not A.IsJunk(id) then fish[#fish + 1] = {id = id, n = n} total = total + n end
    end
    table.sort(fish, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.id < b.id end)
    if #fish > 0 then out[#out + 1] = {x = s.x, y = s.y, fish = fish, total = total, key = spotKey(z, s), hidden = hidden[spotKey(z, s)]} end
  end
  return out
end

local function hasFish(s, id) for _, f in ipairs(s.fish) do if f.id == id then return f.n end end end

-- Catches of the chosen fish at a spot (all fish when none is chosen); 0 means the spot is filtered out.
local function weight(s, ids)
  local sum = 0
  for _, f in ipairs(s.fish) do if not ids or ids[f.id] then sum = sum + f.n end end
  return sum
end
local function chosen() return next(selected) and selected or nil end

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
    GameTooltip:AddDoubleLine(itemName(f.id), "x" .. f.n, 1, 1, 1, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(format("%.1f / %.1f", s.x * 100, s.y * 100), 0.7, 0.7, 0.7)
  GameTooltip:AddLine(L["Right click: menu"], 0.26, 0.69, 1)
  GameTooltip:Show()
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
    self.tex:SetDesaturated(on)
    if on then self.tex:SetVertexColor(0.36, 0.22, 0.10) self.tex:SetAlpha(0.9)
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
  root = CreateFrame("Frame", nil, parent)
  root:SetSize(MAP_W, 400)
  root.map = CreateFrame("Frame", nil, root)
  root.map:SetPoint("TOPLEFT")
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
  root.fade:SetTexture(ns.Icons.maskSoft, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  root.note = root.map:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  root.note:SetPoint("CENTER")
end

-- Map art as tiles (like the world map). Returns the map size in pixels.
local function drawMap(z)
  for _, t in ipairs(tiles) do t:Hide() end
  root.note:SetText("")
  local w, h = MAP_W, MAP_H
  local ok = C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures
  local layers = ok and select(2, pcall(C_Map.GetMapArtLayers, z))
  local info = type(layers) == "table" and layers[1]
  if info and info.layerWidth and info.layerWidth > 0 then
    local textures = select(2, pcall(C_Map.GetMapArtLayerTextures, z, 1))
    if type(textures) == "table" and #textures > 0 then
      local scale = math.min(MAP_W / info.layerWidth, MAP_H / info.layerHeight)
      w, h = info.layerWidth * scale, info.layerHeight * scale
      root.map:SetSize(w, h) root.canvas:SetSize(w, h)
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
        t:SetVertexColor(0.50, 0.34, 0.18, 0.6)
        if not t.masked then t:AddMaskTexture(root.fade) t.masked = true end
        t:Show()
      end
      return w, h
    end
  end
  root.map:SetSize(w, h) root.canvas:SetSize(w, h)
  root.note:SetText(L["Map not available"])
  return w, h
end

-- The mask reaches beyond the map so only the outermost part fades out.
local function fitMask(w, h)
  root.fade:ClearAllPoints()
  root.fade:SetPoint("TOPLEFT", root.map, "TOPLEFT", -w * 0.02, h * 0.02)
  root.fade:SetPoint("BOTTOMRIGHT", root.map, "BOTTOMRIGHT", w * 0.02, -h * 0.02)
end

--- Fish chosen in the journal list (multi-select). The list calls these; the map follows on the next Show.
function M.IsSelected(id) return selected[id] == true end
function M.Toggle(id) if selected[id] then selected[id] = nil else selected[id] = true end end
--- Switching to another zone forgets the choice.
function M.SetZone(z) if zone ~= z then wipe(selected) zone = z end end

-- Zoom (mouse wheel, towards the cursor) and pan (left mouse button held): the canvas is scaled and moved inside the
-- map frame. Markers keep their size (inverse scale). The drag uses an OnUpdate only while the button is held.
local view = {zoom = 1, px = 0, py = 0, w = MAP_W, h = MAP_H}
local MAX_ZOOM = 8

local function applyView()
  local z = view.zoom
  view.px = math.min(math.max(view.px, view.w - view.w * z), 0)
  view.py = math.min(math.max(view.py, view.h - view.h * z), 0)
  root.canvas:SetScale(z)
  root.canvas:ClearAllPoints()
  root.canvas:SetPoint("TOPLEFT", root.map, "TOPLEFT", view.px / z, -view.py / z)
  for _, m in ipairs(markers) do
    if m:IsShown() and m.spot then
      m:SetScale(1 / z)
      m:ClearAllPoints()
      m:SetPoint("CENTER", root.canvas, "TOPLEFT", m.spot.x * view.w * z, -m.spot.y * view.h * z)
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
  if not root or view.zoom <= 1 then return end
  local x, y = cursorInMap()
  view.dragX, view.dragY, view.startX, view.startY = x, y, view.px, view.py
  root.map:SetScript("OnUpdate", function()
    local cx, cy = cursorInMap()
    view.px, view.py = view.startX + (cx - view.dragX), view.startY + (cy - view.dragY)
    applyView()
  end)
end

function M.StopPan()
  if root then root.map:SetScript("OnUpdate", nil) end
end

function M.Hide() if root then root:Hide() end end

--- Shows the map for a zone below the page header; `top` is the y offset (negative) below the book top.
--- Returns nothing; the page rows above are placed by the journal.
function M.Show(book, z, top)
  if type(z) ~= "number" or z <= 0 then M.Hide() return end
  if not root then create(book) end
  root:SetParent(book)
  root.top = top
  root:ClearAllPoints()
  root:SetPoint("TOPLEFT", book, "TOP", 40, top) -- same left edge as the page rows (BODY_X)
  local newZone = zone ~= z
  M.SetZone(z)
  local w, h = drawMap(z)
  fitMask(w, h)
  for _, m in ipairs(markers) do m:Hide() end
  local A, n = BJ.API, 0
  for _, s in ipairs(collectSpots(z)) do
    if not s.hidden and weight(s, chosen()) > 0 then
      n = n + 1
      local m = marker(n)
      m.spot = s
      m:ClearAllPoints()
      m:Show()
    end
  end
  view.w, view.h = w, h
  if newZone then view.zoom, view.px, view.py = 1, 0, 0 end
  applyView()
  root:SetHeight(h)
  root:Show()
end
