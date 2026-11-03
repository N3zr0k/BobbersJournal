local _, ns = ...
local BJ = ns.BJ
local Flavor = ns.Flavor
-- BobbersJournal_DB, format 2. Written only by the Tracker, read through the API.
--
-- BobbersJournal_DB = { format = 2, forever = <client>, retail = <client> }  one container per client, so IDs of the two
-- clients are never mixed and no entry needs a flavor flag. DB.raw is the container of the running client:
--
--   zones[mapID]     knowledge about a zone (uiMapID, -instanceID in instances), account-wide
--     looted         loot windows seen (denominator for drop chances)
--     fish[itemID]   { drops = loot windows containing it, qty = total quantity }
--     subs[nr]       { looted, fish = { [itemID] = { drops, qty } } }   nr = own number per zone (nextSub), name in text.subs
--     nextSub        counter for new sub zone numbers
--     hours[0..23]   catches per server hour
--   points[mapID][code] = { [itemID] = catches }   fishing spots, one cell per rounded position (code: see DB.Encode)
--   chars[guid]      per character counters
--     name, since    display name, first record (unix time)
--     cast, catch, abort                totals
--     time           seconds spent fishing (cast start to cast end), zones[mapID].time per zone
--     zones[mapID] = { cast, catch, abort, time }
--     tiers[maxSkill] = { cast, catch, abort }
--     fish[itemID]   total quantity
--     learned[recipeID] = true   recipes with a fish ingredient this character has learned (global recipes[recipeID], name in text.recipes)
--     recipes[itemID] = true   recipe items this character has learned (vendor tooltip "Already known")
--     days[YYYYMMDD] = { cast, catch, fish }   last 8 days only
--   session          { time = seconds fished, fish = { [itemID] = quantity } } since the last login; /reload keeps it
--   log[]            one compact record per finished cast (ring, MAX_LOG newest), only for the detail views:
--     t time, k "c" catch | "m" miss | "a" abort, z zone, s sub zone number, x y position (4 decimals),
--     d duration s, sk skill rank, b equipment+lure bonus, l lure enchantID, h server hour 0-23, i = { [itemID] = qty }
--     bf = { spellIDs of fishing buffs active at cast start }
--   items[itemID]    { c = classID, s = subClassID, q = quality, i = icon } language free
--   recipes[recipeID] = { fish = { [itemID] = true } }   one entry per recipe with a fish ingredient, whatever number of vendors sell it
--   text             language store, dropped completely when the client language changes:
--     locale, items[itemID] = { n = name, t = tooltip lines, rk = catch rank }, subs[mapID][nr] = sub zone name,
--     recipes[recipeID] = recipe name
--   lures[enchantID] { cast, catch, time (seconds fished with it), applied (times put on the pole) }
--   buffs[spellID]   { name, n appearances, bonus (last), last time, src = { item, quest, spell, other, unknown },
--                      items = { [itemID] = n }, zones = { [mapID] = n } }  (Modules/Buffs.lua)
--   Weather is not recorded: no API found that exists on both clients.
local DB = {MAX_LOG = 3000, FORMAT = 2, SPOT_RADIUS = 0.01, SPOT_GRID = 0.005, MAX_SPOTS = 200, KEEP_DAYS = 8}
BJ.DB = DB

local raw

local CLIENT_KEY = {[Flavor.FOREVER] = "forever", [Flavor.RETAIL] = "retail"}

--- Takes the saved variable and returns it (to be assigned back). Older formats are not converted: they start fresh.
function DB:Init(saved)
  saved = type(saved) == "table" and saved or {}
  if saved.format ~= self.FORMAT then saved = {format = self.FORMAT} end
  local key = CLIENT_KEY[Flavor.current]
  raw = type(saved[key]) == "table" and saved[key] or {}
  saved[key] = raw
  raw.zones = raw.zones or {}
  raw.points = raw.points or {}
  raw.chars = raw.chars or {}
  raw.log = raw.log or {}
  raw.items = raw.items or {}
  raw.lures = raw.lures or {}
  raw.lureCatalog = raw.lureCatalog or {} -- [itemID] = bonus, filled by the in-game lure scan
  raw.lureItems = raw.lureItems or {} -- [enchantID] = itemID of the lure that made it
  raw.buffs = raw.buffs or {}
  raw.priceSeen = raw.priceSeen or {} -- [itemID] = { price, day } the price last seen and the day it first showed up
  raw.prices = raw.prices or {} -- [itemID][day] = { lowest, highest, last } auction price samples in copper (PriceHistory.lua)
  raw.npcs = raw.npcs or {} -- [npcID] = { n = name, map = uiMapID, x, y, trainer = true, repair = true, offers = { [itemID] = { p, q, lim, cost, need } }, lessons = { { n, r, c, k, l } }, guid, details = { tip = tooltip lines, title, type, level, class, faction, sex, race, zoneText, subZone, options, services, loc, seen }, items = { [itemID] = category } }
  raw.recipes = raw.recipes or {} -- [recipeID] = { fish = { [itemID] = true } } profession recipes that use a fish; the name is in text.recipes
  raw.bookmarks = raw.bookmarks or {} -- ["fish:<itemID>" | "zone:<zoneKey>"] = true
  -- all texts are saved per client language; another language drops them (the numbers stay)
  local locale = GetLocale and GetLocale() or "?"
  if type(raw.text) ~= "table" or raw.text.locale ~= locale then raw.text = {locale = locale} end
  raw.text.items = raw.text.items or {}
  raw.text.subs = raw.text.subs or {}
  raw.text.recipes = raw.text.recipes or {}
  self.saved, self.key, self.raw = saved, key, raw
  -- the play session (from login to the next login, a /reload keeps it): seconds fished and quantity per fish
  raw.session = type(raw.session) == "table" and raw.session or {time = 0, fish = {}}
  raw.session.fish = raw.session.fish or {}
  self.session = raw.session
  return saved
end

--- A new login starts a new play session (called on PLAYER_ENTERING_WORLD after a real login, not after /reload).
function DB:ResetSession()
  if not raw then return end
  raw.session = {time = 0, fish = {}}
  self.session = raw.session
end

--- Deletes everything recorded so far on this client (zones, characters, log, items, lures, buffs, bookmarks). Settings stay.
function DB:Reset()
  self.saved[self.key] = nil
  BJ.debugLog = {}
  BobbersJournal_DB = self:Init(self.saved)
  return BobbersJournal_DB
end

local function bump(t, k, by) t[k] = (t[k] or 0) + (by or 1) end

function DB:Zone(zone)
  local w = raw.zones[zone]
  if not w then
    w = {looted = 0, fish = {}}
    raw.zones[zone] = w
  end
  return w
end

--- Number of a known sub zone name, or nil.
function DB:FindSub(zone, name)
  if not (zone and type(name) == "string") then return nil end
  for nr, n in pairs(raw.text.subs[zone] or {}) do if n == name then return nr end end
  return nil
end

--- Number of a sub zone within its zone (own counter, the name lives in text.subs). Allocates a new number for a new name.
function DB:SubID(zone, name)
  if not (zone and type(name) == "string" and name ~= "") then return nil end
  local found = self:FindSub(zone, name)
  if found then return found end
  local names = raw.text.subs[zone]
  local z = self:Zone(zone)
  z.nextSub = (z.nextSub or 0) + 1
  names = names or {}
  raw.text.subs[zone] = names
  names[z.nextSub] = name
  return z.nextSub
end

--- Name of a sub zone number in the client language (nil after a language change, until the zone is seen again).
function DB:SubName(zone, nr)
  local names = raw.text.subs[zone]
  return names and names[nr] or nil
end

--- Position code of a spot (the key style of GatherMate2): x and y in 0..1 with 4 decimals plus a level (floor, instance).
function DB.Encode(x, y, level)
  return math.floor(x * 10000 + 0.5) * 1000000 + math.floor(y * 10000 + 0.5) * 100 + (level or 0)
end

--- x, y, level of a position code.
function DB.Decode(code)
  local level = code % 100
  local rest = (code - level) / 100
  local y = rest % 10000
  return (rest - y) / 10000 / 10000, y / 10000, level
end

local function snap(v, grid) return math.floor(v / grid + 0.5) * grid end

--- The cell of a fishing spot: positions are rounded to SPOT_GRID, so casts at the same place share one entry. Returns the
--- table { [itemID] = catches } of the cell, or nil when the zone already has MAX_SPOTS cells.
function DB:Point(zone, x, y)
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  local code = DB.Encode(snap(x, self.SPOT_GRID), snap(y, self.SPOT_GRID))
  local pts = raw.points[zone]
  if not pts then pts = {} raw.points[zone] = pts end
  local cell = pts[code]
  if cell then return cell end
  local n = 0
  for _ in pairs(pts) do n = n + 1 end
  if n >= self.MAX_SPOTS then return nil end
  cell = {}
  pts[code] = cell
  return cell
end

function DB:Char()
  local guid = UnitGUID and BJ.Clean(UnitGUID("player")) or "unknown"
  local c = raw.chars[guid]
  if not c then
    c = {name = UnitName and UnitName("player"), since = time(), cast = 0, catch = 0, abort = 0,
      zones = {}, tiers = {}, fish = {}, days = {}}
    raw.chars[guid] = c
  end
  if not c.class and UnitClass then c.class = select(2, UnitClass("player")) end -- class file name, for the colour
  return c
end

local function sub(t, k)
  local s = t[k]
  if not s then s = {cast = 0, catch = 0, abort = 0} t[k] = s end
  return s
end

local function today(c)
  local key = date("%Y%m%d")
  local d = c.days[key]
  if not d then
    d = {cast = 0, catch = 0, fish = 0}
    c.days[key] = d
    -- Lexicographic order equals date order; drop the oldest beyond KEEP_DAYS.
    local keys = {}
    for k in pairs(c.days) do keys[#keys + 1] = k end
    table.sort(keys)
    while #keys > DB.KEEP_DAYS do c.days[table.remove(keys, 1)] = nil end
  end
  return d
end

--- A cast that ended: outcome "catch" is counted via AddCatch, "miss" here, "abort" separately.
function DB:AddCast(zone, tier, outcome, ctx)
  local c = self:Char()
  -- aborted casts are only counted as "abort", never as "cast" (not part of casts, failed casts or catch rate)
  local field = outcome == "abort" and "abort" or "cast"
  local function count(t) bump(t, field) end
  count(c)
  local d = field == "cast" and ctx and ctx.duration or nil -- aborted casts add no fishing time either
  if d and d > 0 then
    self.session.time = self.session.time + d
    c.time = (c.time or 0) + d
    if zone then local z = sub(c.zones, zone) z.time = (z.time or 0) + d end
  end
  if zone then count(sub(c.zones, zone)) end
  if tier then count(sub(c.tiers, tier)) end
  if field == "cast" then bump(today(c), "cast") end
  if ctx and ctx.lure then
    local lz = sub(raw.lures, ctx.lure)
    count(lz)
    if d and d > 0 then lz.time = (lz.time or 0) + d end
  end
  if outcome ~= "catch" then self:Log(outcome == "abort" and "a" or "m", zone, ctx) end
  BJ:Fire("CAST", zone, outcome)
end

--- items = { [itemID] = qty }; pos = { map, x, y } or nil. Also counts as a cast.
function DB:AddCatch(zone, tier, items, pos, ctx)
  self:AddCast(zone, tier, "catch", ctx)
  local c = self:Char()
  bump(c, "catch")
  bump(today(c), "catch")
  if zone then bump(sub(c.zones, zone), "catch") end
  if tier then bump(sub(c.tiers, tier), "catch") end
  local w = zone and self:Zone(zone)
  if w then
    w.looted = w.looted + 1
    local subNr = ctx and ctx.sub and self:SubID(zone, ctx.sub)
    if subNr then
      w.subs = w.subs or {}
      local sz = w.subs[subNr]
      if not sz then sz = {looted = 0} w.subs[subNr] = sz end
      sz.looted = sz.looted + 1
      sz.fish = sz.fish or {}
      for id, qty in pairs(items) do
        local f = sz.fish[id]
        if not f then f = {drops = 0, qty = 0} sz.fish[id] = f end
        f.drops, f.qty = f.drops + 1, f.qty + qty
      end
    end
    if ctx and ctx.hour then
      w.hours = w.hours or {}
      w.hours[ctx.hour] = (w.hours[ctx.hour] or 0) + 1
    end
  end
  if ctx and ctx.lure then bump(sub(raw.lures, ctx.lure), "catch") end
  self:Log("c", zone, ctx, items)
  for id in pairs(items) do self:ItemMeta(id) self:ItemName(id) end
  local spot = w and pos and pos.map == zone and self:Point(zone, pos.x, pos.y)
  for id, qty in pairs(items) do
    bump(self.session.fish, id, qty)
    bump(c.fish, id, qty)
    bump(today(c), "fish", qty)
    if w then
      local f = w.fish[id]
      if not f then f = {drops = 0, qty = 0} w.fish[id] = f end
      f.drops, f.qty = f.drops + 1, f.qty + qty
      if spot then bump(spot, id) end
    end
  end
  BJ:Fire("CATCH", zone, items)
end

-- Minimal callback list so addons can listen without LibStub/CallbackHandler (embedded later).
local listeners = {}
function BJ:Listen(fn) listeners[#listeners + 1] = fn end
function BJ:Fire(...)
  for _, fn in ipairs(listeners) do BJ.Protected("listener", fn, ...) end
end

local function round4(v) return v and math.floor(v * 10000 + 0.5) / 10000 or nil end

--- Compact record of a finished cast. Only game values, secret values never reach here (Clean at the source).
function DB:Log(kind, zone, ctx, items)
  ctx = ctx or {}
  local pos = ctx.pos
  local rec = {t = time(), k = kind, z = zone, s = ctx.sub and self:SubID(zone, ctx.sub), x = pos and round4(pos.x), y = pos and round4(pos.y),
    d = ctx.duration and math.floor(ctx.duration + 0.5), bf = ctx.buffs, sk = ctx.skill, b = ctx.bonus, l = ctx.lure, h = ctx.hour}
  if items then
    rec.i = {}
    for id, qty in pairs(items) do rec.i[id] = qty end
  end
  local log = raw.log
  log[#log + 1] = rec
  if #log > self.MAX_LOG + 200 then -- trim in batches, not on every write
    local n = #log - self.MAX_LOG
    for i = 1, #log - n do log[i] = log[i + n] end
    for i = #log - n + 1, #log do log[i] = nil end
  end
end

--- Class/subclass of an item, cached once so the journal can tell fish from bycatch.
function DB:ItemMeta(id)
  if raw.items[id] then return raw.items[id] end
  local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not getInfo then return nil end
  local _, _, _, _, _, classID, subClassID = getInfo(id)
  if classID then raw.items[id] = {c = classID, s = subClassID} end
  return raw.items[id]
end

local function textOf(id, create)
  local t = raw.text.items
  local m = t[id]
  if not m and create then m = {} t[id] = m end
  return m
end

--- Name of an item: the live name from the client (and saved in the database), otherwise the saved one, nil if neither.
function DB:ItemName(id)
  if type(id) ~= "number" or not raw then return nil end
  local live = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if type(live) == "string" and live ~= "" then
    if not raw.items[id] then raw.items[id] = self:ItemMeta(id) or {} end
    textOf(id, true).n = live
    return live
  end
  local m = textOf(id)
  return m and m.n or nil
end

--- Catch rank text of a fish (Retail fish page, in the client language), saved with the texts.
function DB:Rank(id)
  local m = textOf(id)
  return m and m.rk or nil
end

function DB:SetRank(id, rank)
  if type(id) ~= "number" or type(rank) ~= "string" or not raw then return false end
  local m = textOf(id, true)
  if m.rk == rank then return false end
  m.rk = rank
  return true
end

--- Tooltip of an item, saved once per item ID (name, icon and the lines with their colours) and read from the database
--- afterwards. Returns { { text, r, g, b, right }, ... } (line 1 is the name) or nil while the client has not delivered it;
--- incomplete data (name only) is never saved.
function DB:ItemTooltip(id)
  if type(id) ~= "number" or not raw then return nil end
  local tm = textOf(id)
  if tm and tm.t then return tm.t end
  if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
  if not (ok and type(data) == "table") then return nil end
  if TooltipUtil and TooltipUtil.SurfaceArgs then
    pcall(TooltipUtil.SurfaceArgs, data)
    for _, line in ipairs(data.lines or {}) do pcall(TooltipUtil.SurfaceArgs, line) end
  end
  local lines = {}
  for _, line in ipairs(data.lines or {}) do
    local text = BJ.Clean(line.leftText)
    if type(text) == "string" and text ~= "" then
      local c = line.leftColor
      local right = BJ.Clean(line.rightText)
      lines[#lines + 1] = {
        text = text,
        r = type(c) == "table" and tonumber(BJ.Clean(c.r)) or 1,
        g = type(c) == "table" and tonumber(BJ.Clean(c.g)) or 1,
        b = type(c) == "table" and tonumber(BJ.Clean(c.b)) or 1,
        right = type(right) == "string" and right ~= "" and right or nil,
      }
    end
  end
  if #lines < 2 or not self:ItemName(id) then return nil end
  textOf(id, true).t = lines
  local m = raw.items[id]
  if not m then m = self:ItemMeta(id) or {} raw.items[id] = m end
  local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  if icon then m.i = icon end
  return lines
end

--- Saves that a recipe uses the item (a fish): recipes[recipeID].fish[itemID], with the recipe's name in the language store.
function DB:AddFishRecipe(itemID, recipeID, name)
  if type(itemID) ~= "number" or type(recipeID) ~= "number" or not raw then return end
  local r = raw.recipes[recipeID]
  if not r then r = {fish = {}} raw.recipes[recipeID] = r end
  r.fish = r.fish or {}
  r.fish[itemID] = true
  if type(name) == "string" and name ~= "" then raw.text.recipes[recipeID] = name end
end

--- Saves a vendor or teacher (merged with what is known): NPC ID, name, position and the fishing items it sells.
--- info = { n, f, map, x, y, trainer = true, items = { [itemID] = category } }
function DB:AddNPC(npcID, info)
  if type(npcID) ~= "number" or not raw then return end
  local npc = raw.npcs[npcID] or {items = {}}
  raw.npcs[npcID] = npc
  for k, v in pairs(info) do
    if k == "items" then for id, cat in pairs(v) do npc.items[id] = cat end
    elseif k == "offers" then
      npc.offers = npc.offers or {}
      for id, o in pairs(v) do npc.offers[id] = o end
    elseif v ~= nil then npc[k] = v end
  end
end

--- Forget a saved NPC (a vendor or teacher that turned out not to be one).
function DB:RemoveNPC(npcID)
  if type(npcID) ~= "number" or not raw or not raw.npcs[npcID] then return false end
  raw.npcs[npcID] = nil
  return true
end

--- Recipes the current character has learned (seen as "Already known" at a vendor): chars[guid].recipes[itemID] = true.
function DB:SetRecipeKnown(itemID)
  if type(itemID) ~= "number" or not raw then return end
  local c = self:Char()
  c.recipes = c.recipes or {}
  c.recipes[itemID] = true
end

--- A recipe (profession recipe ID) with a fish ingredient that the current character has learned. The recipe is saved once
--- (recipes[recipeID] = {n = name}), whatever number of vendors sell it; the marker is per character (chars[guid].learned).
function DB:SetRecipeLearned(recipeID, name)
  if type(recipeID) ~= "number" or not raw then return end
  local r = raw.recipes[recipeID]
  if not r then r = {fish = {}} raw.recipes[recipeID] = r end
  if type(name) == "string" and name ~= "" then raw.text.recipes[recipeID] = name end
  local c = self:Char()
  c.learned = c.learned or {}
  c.learned[recipeID] = true
end

local checkedAt = {} -- itemID -> GetTime() of the last "Already known" check that said no

--- Does the tooltip of the item (by ID) say "Already known"? The text is the client's own constant, so every language works.
local function tooltipSaysKnown(itemID)
  local known = _G.ITEM_SPELL_KNOWN
  if type(known) ~= "string" or not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return false end
  local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
  if not (ok and type(data) == "table") then return false end
  for _, line in ipairs(data.lines or {}) do
    local t = BJ.Clean(line.leftText)
    if type(t) == "string" and t:find(known, 1, true) then return true end
  end
  return false
end

--- Is the recipe item learned by the current character? Looked up by the ID of the item, no names:
--- 1. saved before (chars[guid].recipes[itemID], set by a vendor visit or an earlier check),
--- 2. the tooltip of the item says "Already known" (checked again at most every 10 seconds, only for recipe items),
--- 3. ns.RecipeItems[itemID] is the ID of a learned recipe.
function DB:RecipeKnown(itemID)
  local c = raw and self:Char()
  if not c then return false end
  if c.recipes and c.recipes[itemID] == true then return true end
  local recipeID = ns.RecipeItems and ns.RecipeItems[itemID]
  if type(recipeID) == "number" and c.learned and c.learned[recipeID] == true then return true end
  local now = GetTime and GetTime() or 0
  if checkedAt[itemID] and now - checkedAt[itemID] < 10 then return false end
  if tooltipSaysKnown(itemID) then
    c.recipes = c.recipes or {}
    c.recipes[itemID] = true
    return true
  end
  checkedAt[itemID] = now
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
  return false
end

--- Item quality (0 poor .. 5 legendary): live from the client, saved in the database, nil when unknown.
function DB:ItemQuality(id)
  if type(id) ~= "number" or not raw then return nil end
  local live = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
  if type(live) == "number" then
    local m = raw.items[id]
    if not m then m = self:ItemMeta(id) or {} raw.items[id] = m end
    m.q = live
    return live
  end
  local m = raw.items[id]
  return m and m.q or nil
end

--- Colour of the item quality: r, g, b (0..1); nil when the quality is unknown.
function DB:ItemColor(id)
  local q = self:ItemQuality(id)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  return nil
end

--- Asks the client for every saved item whose name is not saved yet (old entries); the names are stored on arrival.
function DB:PreloadNames()
  if not raw then return end
  for id, m in pairs(raw.items) do
    local tm = textOf(id)
    if type(id) == "number" and not (tm and tm.n) then
      if Item and Item.CreateFromItemID then
        Item:CreateFromItemID(id):ContinueOnItemLoad(function() self:ItemName(id) end)
      elseif C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(id)
      end
    end
  end
end

--- A fishing buff appeared. src: item | quest | spell | other | unknown.
function DB:AddBuff(spellID, name, bonus, src, itemID, zone)
  local b = raw.buffs[spellID]
  if not b then b = {name = name, n = 0, src = {}, items = {}, zones = {}} raw.buffs[spellID] = b end
  b.name, b.bonus, b.last = name, bonus, time()
  b.n = b.n + 1
  b.src[src] = (b.src[src] or 0) + 1
  if itemID then b.items[itemID] = (b.items[itemID] or 0) + 1 end
  if zone then b.zones[zone] = (b.zones[zone] or 0) + 1 end
  BJ:Fire("BUFF", spellID, src)
end
