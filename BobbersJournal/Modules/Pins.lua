local _, ns = ...
local BJ, Flavor = ns.BJ, ns.Flavor
local L = BJ.L
-- Shows the saved fishing teachers and vendors (API.GetNPCs) on the world map (own data provider with pins of the game's map
-- canvas) and on the minimap (small frames, placed from the player's position in steps of a quarter second while the option
-- is on and the minimap is shown; there is no event for "player moved"). 
-- Not tested in the game. Option: settings.npcPins.
local M = BJ:RegisterModule("Pins")

local PIN_SIZE, MINI_SIZE = 26, 22
local TICK = 0.25
-- diameter of the minimap in yards per zoom level (outdoors) where the client has no C_Minimap.GetViewRadius
local OUTDOOR = {[0] = 466.67, 400, 333.33, 266.67, 200, 133.33}

local function npcs() return BJ.API.GetNPCs(Flavor.current) end

local RING = 3 -- thickness of the aqua ring in pixels
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- the game's round mask

--- Symbol of a pin: the game's icon on a dark disc inside an aqua ring of 3 px. Needs pin.icon (see decorate).
local function paint(pin, npc)
  pin.icon:SetTexture(npc.trainer and ns.Icons.teacher or ns.Icons.vendor)
end

local function round(pin, tex, layer)
  tex:SetPoint("CENTER")
  local mask = pin:CreateMaskTexture()
  mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(tex)
  tex:AddMaskTexture(mask)
end

local function decorate(pin)
  if pin.icon then return end
  pin.disc = pin:CreateTexture(nil, "BACKGROUND")
  pin.disc:SetColorTexture(unpack(ns.Colors.aqua))
  round(pin, pin.disc)
  pin.inner = pin:CreateTexture(nil, "BORDER")
  pin.inner:SetColorTexture(0.05, 0.05, 0.05)
  pin.inner:SetAlpha(0.75)
  round(pin, pin.inner)
  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetPoint("CENTER")
  local function layout(self, w)
    w = w or self:GetWidth()
    self.disc:SetSize(w, w)
    self.inner:SetSize(w - 2 * RING, w - 2 * RING)
    self.icon:SetSize((w - 2 * RING) * 0.9, (w - 2 * RING) * 0.9)
  end
  pin:HookScript("OnSizeChanged", layout)
  layout(pin)
end

local CATEGORIES = {{"pole", "Fishing poles"}, {"bobber", "Oversized bobber"}, {"lure", "Lures"}, {"recipe", "Recipes"}, {"fish", "Fish"}, {"other", "Other"}}

--- Tooltip of a pin: name, role, place, then everything the NPC offers, grouped, in the colours of the items.
local function tooltip(owner, npc)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(ns.Colors.Paint("aqua", npc.name or ("#" .. npc.id)))
  GameTooltip:AddLine(npc.trainer and L["Fishing teacher"] or L["Fishing vendor"], 1, 0.82, 0)
  local place = npc.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(npc.map)
  local where = place and place.name or ""
  if npc.x and npc.y then where = format("%s  |cffffd100[%.1f, %.1f]|r", where, npc.x * 100, npc.y * 100) end
  if where ~= "" then GameTooltip:AddLine(where, 0.7, 0.7, 0.7) end
  for _, cat in ipairs(CATEGORIES) do
    local names = {}
    for itemID, c in pairs(npc.items or {}) do
      if c == cat[1] then
        local name = BJ.DB:ItemName(itemID) or ("#" .. itemID)
        local r, g, b = BJ.DB:ItemColor(itemID)
        local offer = npc.offers and npc.offers[itemID]
        local price = offer and ns.Prices.OfferText(offer) or ""
        names[#names + 1] = ns.Colors.Wrap(r, g, b, name) .. (price ~= "" and ("  |cffaaaaaa" .. price .. "|r") or "") .. ((#ns.Prices.Needs(offer) > 0) and " |cffff6060!|r" or "") .. ((c == "recipe" and BJ.DB:RecipeKnown(itemID)) and " |TInterface\\RaidFrame\\ReadyCheck-Ready:14|t" or "")
      end
    end
    if #names > 0 then
      table.sort(names)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L[cat[2]], 0.13, 0.7, 0.65)
      for i = 1, math.min(#names, 10) do GameTooltip:AddLine(names[i], 1, 1, 1) end
      if #names > 10 then GameTooltip:AddLine(format("+%d", #names - 10), 0.7, 0.7, 0.7) end
    end
  end
  if npc.lessons and #npc.lessons > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Teaches"], 0.13, 0.7, 0.65)
    for i = 1, math.min(#npc.lessons, 6) do GameTooltip:AddLine(ns.Prices.LessonText(npc.lessons[i]), 1, 1, 1) end
  end
  if npc.repair then GameTooltip:AddLine(L["Repairs equipment"], 0.7, 0.7, 0.7) end
  BJ:DebugTip(GameTooltip, "NPC", npc.id)
  GameTooltip:Show()
end

-- ---- world map -------------------------------------------------------------------------------------------------------

local provider

local function createProvider()
  provider = CreateFromMixins(MapCanvasDataProviderMixin)
  function provider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate("BobbersJournalPinTemplate") end
  function provider:RefreshAllData()
    self:RemoveAllData()
    if not BJ.settings.npcPins then return end
    local map = self:GetMap()
    local mapID = map:GetMapID()
    for _, npc in ipairs(npcs()) do
      if npc.map == mapID and npc.x and npc.y then
        local pin = map:AcquirePin("BobbersJournalPinTemplate")
        pin:SetSize(PIN_SIZE, PIN_SIZE)
        decorate(pin)
        paint(pin, npc)
        pin.npc = npc
        pin:SetScript("OnEnter", function(self) tooltip(self, self.npc) end)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if pin.UseFrameLevelType then pin:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
        pin:SetPosition(npc.x, npc.y)
        pin:Show()
      end
    end
  end
end

local function attachWorldMap()
  if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return end
  createProvider()
  WorldMapFrame:AddDataProvider(provider)
end

-- ---- minimap ---------------------------------------------------------------------------------------------------------

local pins, ticker = {}, nil

local function viewRadius()
  if C_Minimap and C_Minimap.GetViewRadius then
    local r = C_Minimap.GetViewRadius()
    if type(r) == "number" and r > 0 then return r end
  end
  return (OUTDOOR[Minimap:GetZoom() or 0] or OUTDOOR[3]) / 2
end

local function pinFrame(i)
  local f = pins[i]
  if f then return f end
  f = CreateFrame("Frame", nil, Minimap)
  f:SetSize(MINI_SIZE, MINI_SIZE)
  f:SetFrameLevel(Minimap:GetFrameLevel() + 5)
  decorate(f)
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self) tooltip(self, self.npc) end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pins[i] = f
  return f
end

--- Size of the map in yards (width, height), from the world positions the client gives for map points.
local sizeCache = {}
local function mapSize(mapID)
  if sizeCache[mapID] then return unpack(sizeCache[mapID]) end
  if C_Map and C_Map.GetMapWorldSize then
    local w, h = C_Map.GetMapWorldSize(mapID)
    if type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then sizeCache[mapID] = {w, h} return w, h end
  end
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local _, a = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
  local _, b = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
  local _, c = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
  if not (a and b and c) then return nil end
  local w = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
  local h = math.sqrt((c.x - a.x) ^ 2 + (c.y - a.y) ^ 2)
  if w <= 0 or h <= 0 then return nil end
  sizeCache[mapID] = {w, h}
  return w, h
end

local function hideAll(from)
  for i = from or 1, #pins do pins[i]:Hide() end
end

local lastWhy
local function why(text)
  if text ~= lastWhy then lastWhy = text BJ:Debug("pins: minimap " .. text) end
end

local function update()
  if not (BJ.settings.npcPins and Minimap and Minimap:IsVisible()) then hideAll() return end
  local mapID = C_Map and C_Map.GetBestMapForUnit and BJ.Clean(C_Map.GetBestMapForUnit("player"))
  local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
  local px, py -- (an "and" would cut the second return value off)
  if pos and pos.GetXY then px, py = pos:GetXY() end
  px, py = BJ.Clean(px), BJ.Clean(py)
  local w, h -- (an "and" would cut the second return value off here too)
  if mapID then w, h = mapSize(mapID) end
  if not (px and py and w) then
    why(format("no position (map %s, player x %s, y %s, size %s)", tostring(mapID), tostring(px ~= nil), tostring(py ~= nil), tostring(w)))
    hideAll()
    return
  end
  local radius = viewRadius()
  local half = Minimap:GetWidth() / 2
  local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
  local facing = rotate and GetPlayerFacing and BJ.Clean(GetPlayerFacing()) or nil
  local sin, cos = 0, 1
  if facing then sin, cos = math.sin(facing), math.cos(facing) end
  local n = 0
  for _, npc in ipairs(npcs()) do
    if npc.map == mapID and npc.x and npc.y then
      local east, north = (npc.x - px) * w, -(npc.y - py) * h
      local sx, sy = east * cos + north * sin, -east * sin + north * cos
      if sx * sx + sy * sy <= radius * radius then
        n = n + 1
        local f = pinFrame(n)
        f.npc = npc
        paint(f, npc)
        f:ClearAllPoints()
        f:SetPoint("CENTER", Minimap, "CENTER", sx / radius * half, sy / radius * half)
        f:Show()
      end
    end
  end
  hideAll(n + 1)
  why(format("map %s, radius %.0f, %d of %d in range", tostring(mapID), radius, n, #npcs()))
end

local function tick() BJ.Protected("pins", update) end

function M.HasProvider() return provider ~= nil end

--- Applies the option: starts or stops the minimap steps and redraws the world map.
function M.Refresh()
  if BJ.settings.npcPins then
    if not ticker and C_Timer then ticker = C_Timer.NewTicker(TICK, tick) end
  else
    if ticker then ticker:Cancel() ticker = nil end
    hideAll()
  end
  if provider and provider.GetMap and provider:GetMap() then BJ.Protected("pins", provider.RefreshAllData, provider) end
end

function M:OnEnable()
  attachWorldMap()
  if not provider then
    BJ:RegisterEvent("ADDON_LOADED", "pins", function(_, name)
      if name == "Blizzard_WorldMap" then BJ.Protected("pins", attachWorldMap) end
    end)
  end
  -- new vendors and teachers appear while the player talks to them
  for _, event in ipairs({"MERCHANT_SHOW", "TRAINER_SHOW"}) do
    BJ:RegisterEvent(event, "pins", function()
      if C_Timer then C_Timer.After(1, function() BJ.Protected("pins", M.Refresh) end) end
    end)
  end
  M.Refresh()
end
