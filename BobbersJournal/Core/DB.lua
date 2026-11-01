local _, ns = ...
local BJ = ns.BJ
local Flavor = ns.Flavor
-- BobbersJournal_DB, schema version 1. Written only by the Tracker, read through the API.
--
--   world[zoneKey]   account-wide knowledge about a zone (uiMapID, -instanceID in instances)
--     f              flavor mask (1 Forever, 2 Retail, 3 both), OR-ed on every write
--     looted         loot windows seen (denominator for drop chances)
--     fish[itemID]   { drops = loot windows containing it, qty = total quantity, f = flavor mask }
--     spots[]        fishing spots { x, y, n = catches, f, fish = { [itemID] = count } }
--   chars[guid]      per character counters
--     name, since    display name, first record (unix time)
--     cast, catch, abort                totals
--     time           seconds spent fishing (cast start to cast end), zones[zoneKey].time per zone
--     zones[zoneKey] = { cast, catch, abort, time }
--     tiers[maxSkill] = { cast, catch, abort }
--     fish[itemID]   total quantity
--     days[YYYYMMDD] = { cast, catch, fish }   last 8 days only
--   log[]            one compact record per finished cast (ring, MAX_LOG newest):
--     t time, k "c" catch | "m" miss | "a" abort, z zone, s subzone, x y position (4 decimals),
--     d duration s, sk skill rank, b equipment+lure bonus, l lure enchantID, h server hour 0-23, f flavor, i = { [itemID] = qty }
--   items[itemID]    { c = classID, s = subClassID } so bycatch can be told from fish later
--   lures[enchantID] { cast, catch }
--   buffs[spellID]   { name, n appearances, bonus (last), last time, src = { item, quest, spell, other, unknown },
--                      items = { [itemID] = n }, zones = { [zoneKey] = n } }  (Modules/Buffs.lua)
--   log record also has bf = { spellIDs of fishing buffs active at cast start }
--   world[zone].subs[name] = { looted }, world[zone].hours[0..23] = catches
--   Weather is not recorded: no API found that exists on both clients.
local DB = {MAX_LOG = 3000, VERSION = 1, SPOT_RADIUS = 0.01, MAX_SPOTS = 200, KEEP_DAYS = 8}
BJ.DB = DB

local raw

function DB:Init(saved)
  raw = type(saved) == "table" and saved or {}
  raw.version = raw.version or self.VERSION
  raw.world = raw.world or {}
  raw.chars = raw.chars or {}
  raw.log = raw.log or {}
  raw.items = raw.items or {}
  raw.lures = raw.lures or {}
  raw.buffs = raw.buffs or {}
  raw.bookmarks = raw.bookmarks or {} -- ["fish:<itemID>" | "zone:<zoneKey>"] = true
  self.raw = raw
  return raw
end

--- Deletes everything recorded so far (world, characters, log, items, lures, buffs, bookmarks). Settings stay.
function DB:Reset()
  local fresh = self:Init({})
  BobbersJournal_DB = fresh
  BJ.debugLog = {}
  return fresh
end

local function bump(t, k, by) t[k] = (t[k] or 0) + (by or 1) end

function DB:World(zone)
  local w = raw.world[zone]
  if not w then
    w = {f = 0, looted = 0, fish = {}, spots = {}}
    raw.world[zone] = w
  end
  w.f = bit.bor(w.f, Flavor.current)
  return w
end

function DB:Char()
  local guid = UnitGUID and BJ.Clean(UnitGUID("player")) or "unknown"
  local c = raw.chars[guid]
  if not c then
    c = {name = UnitName and UnitName("player"), since = time(), cast = 0, catch = 0, abort = 0,
      zones = {}, tiers = {}, fish = {}, days = {}}
    raw.chars[guid] = c
  end
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
  local field = outcome == "abort" and "abort" or "cast"
  bump(c, field)
  local d = ctx and ctx.duration
  if d and d > 0 then
    c.time = (c.time or 0) + d
    if zone then local z = sub(c.zones, zone) z.time = (z.time or 0) + d end
  end
  if zone then bump(sub(c.zones, zone), field) end
  if tier then bump(sub(c.tiers, tier), field) end
  if field == "cast" then bump(today(c), "cast") end
  if ctx and ctx.lure then bump(sub(raw.lures, ctx.lure), field) end
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
  local w = zone and self:World(zone)
  if w then
    w.looted = w.looted + 1
    if ctx and ctx.sub then
      w.subs = w.subs or {}
      local sz = w.subs[ctx.sub]
      if not sz then sz = {looted = 0} w.subs[ctx.sub] = sz end
      sz.looted = sz.looted + 1
    end
    if ctx and ctx.hour then
      w.hours = w.hours or {}
      w.hours[ctx.hour] = (w.hours[ctx.hour] or 0) + 1
    end
  end
  if ctx and ctx.lure then bump(sub(raw.lures, ctx.lure), "catch") end
  self:Log("c", zone, ctx, items)
  for id in pairs(items) do self:ItemMeta(id) end
  local spot = w and pos and pos.map == zone and self:Spot(w, pos)
  for id, qty in pairs(items) do
    bump(c.fish, id, qty)
    bump(today(c), "fish", qty)
    if w then
      local f = w.fish[id]
      if not f then f = {drops = 0, qty = 0, f = 0} w.fish[id] = f end
      f.drops, f.qty, f.f = f.drops + 1, f.qty + qty, bit.bor(f.f, Flavor.current)
      if spot then bump(spot.fish, id) end
    end
  end
  BJ:Fire("CATCH", zone, items)
end

--- Nearest known spot within SPOT_RADIUS gets the catch, otherwise a new one is created (capped).
function DB:Spot(w, pos)
  local r2 = self.SPOT_RADIUS ^ 2
  for _, s in ipairs(w.spots) do
    local dx, dy = s.x - pos.x, s.y - pos.y
    if dx * dx + dy * dy <= r2 then s.n = s.n + 1 s.f = bit.bor(s.f, Flavor.current) return s end
  end
  if #w.spots >= self.MAX_SPOTS then return nil end
  local s = {x = pos.x, y = pos.y, n = 1, f = Flavor.current, fish = {}}
  w.spots[#w.spots + 1] = s
  return s
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
  local rec = {t = time(), k = kind, z = zone, s = ctx.sub, x = pos and round4(pos.x), y = pos and round4(pos.y),
    d = ctx.duration and math.floor(ctx.duration + 0.5), bf = ctx.buffs, sk = ctx.skill, b = ctx.bonus, l = ctx.lure, h = ctx.hour, f = Flavor.current}
  if items then
    rec.i = {}
    for id, qty in pairs(items) do rec.i[id] = qty end
  end
  local log = raw.log
  log[#log + 1] = rec
  if #log > self.MAX_LOG + 200 then -- trim in batches, not on every write
    local n = #log - self.MAX_LOG
    table.move(log, n + 1, #log, 1)
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
