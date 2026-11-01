local _, ns = ...
local BJ = ns.BJ
local DB, Flavor = BJ.DB, ns.Flavor
-- Public read-only API for other addons: BobbersJournal.API (also _G.BobbersJournalAPI).
-- Returns copies, never internal tables. Zone = uiMapID (negative instanceID in instances).
-- `flavor` is optional (Flavor.FOREVER=1, RETAIL=2, BOTH=3); default is the running client.
local API = {VERSION = 1, FOREVER = Flavor.FOREVER, RETAIL = Flavor.RETAIL, BOTH = Flavor.BOTH}
BJ.API = API
_G.BobbersJournalAPI = API

local function raw() return DB.raw end

function API.IsReady() return raw() ~= nil end
function API.GetFlavor() return Flavor.current end

--- List of { itemID, drops, chance, avgQuantity } sorted by drops, for a zone.
function API.GetZoneFish(zone, flavor)
  local w = raw() and raw().world[zone]
  local out = {}
  if not w or w.looted <= 0 then return out end
  for id, f in pairs(w.fish) do
    if Flavor.Matches(f.f, flavor) then
      out[#out + 1] = {itemID = id, drops = f.drops, chance = math.min(f.drops / w.looted, 1), avgQuantity = f.qty / f.drops}
    end
  end
  table.sort(out, function(a, b) if a.drops ~= b.drops then return a.drops > b.drops end return a.itemID < b.itemID end)
  return out
end

--- True for bycatch that is neither a crafting material/consumable (fish, food) nor something you can open (clams, crates).
--- Unknown items (data not loaded yet) count as no junk, so nothing disappears by mistake.
function API.IsJunk(itemID)
  local m = DB:ItemMeta(itemID)
  if not m or m.c == 7 or m.c == 0 then return false end
  local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
  if getSpell and getSpell(itemID) then return false end
  return true
end

--- List of { zone, drops, chance } for one fish across all known zones.
function API.GetFishZones(itemID, flavor)
  local out = {}
  for zone, w in pairs(raw() and raw().world or {}) do
    local f = w.fish[itemID]
    if f and w.looted > 0 and Flavor.Matches(f.f, flavor) then
      out[#out + 1] = {zone = zone, drops = f.drops, chance = math.min(f.drops / w.looted, 1)}
    end
  end
  table.sort(out, function(a, b) return a.drops > b.drops end)
  return out
end

--- List of { x, y, count, fish = { [itemID] = count } } (map-normalised 0..1). With itemID: only spots that gave it.
function API.GetZoneSpots(zone, itemID, flavor)
  local w = raw() and raw().world[zone]
  local out = {}
  for _, s in ipairs(w and w.spots or {}) do
    if Flavor.Matches(s.f, flavor) and (not itemID or s.fish[itemID]) then
      local fish = {}
      for id, n in pairs(s.fish) do fish[id] = n end
      out[#out + 1] = {x = s.x, y = s.y, count = itemID and s.fish[itemID] or s.n, fish = fish}
    end
  end
  return out
end

--- Loot windows seen in a zone (denominator of the chances).
function API.GetZoneCatches(zone)
  local w = raw() and raw().world[zone]
  return w and w.looted or 0
end

--- Quantity of a fish caught by this character (or all characters with allChars).
function API.GetCaught(itemID, allChars)
  local total, guid = 0, UnitGUID and BJ.Clean(UnitGUID("player"))
  for g, c in pairs(raw() and raw().chars or {}) do
    if allChars or g == guid then total = total + (c.fish[itemID] or 0) end
  end
  return total
end

--- { cast, catch, abort } of this character; zone optional.
function API.GetTotals(zone)
  local c = raw() and DB:Char()
  if not c then return {cast = 0, catch = 0, abort = 0} end
  local s = zone and c.zones[zone] or c
  return {cast = s.cast or 0, catch = s.catch or 0, abort = s.abort or 0}
end

--- fn(event, ...) with event "CATCH" (zone, {itemID=qty}) or "CAST" (zone, outcome). Errors in fn are contained.
function API.Listen(fn) if type(fn) == "function" then BJ:Listen(fn) end end

--- List of { itemID, caught, zones } for every fish seen anywhere (caught = this character).
function API.GetFishList(flavor)
  local seen, out = {}, {}
  for _, w in pairs(raw() and raw().world or {}) do
    for id, f in pairs(w.fish) do
      if Flavor.Matches(f.f, flavor) then seen[id] = (seen[id] or 0) + 1 end
    end
  end
  for id, zones in pairs(seen) do out[#out + 1] = {itemID = id, caught = API.GetCaught(id), zones = zones} end
  table.sort(out, function(a, b) return a.itemID < b.itemID end)
  return out
end

--- List of { zone, name, catches, fish } for every zone with data.
function API.GetZoneList(flavor)
  local out = {}
  for zone, w in pairs(raw() and raw().world or {}) do
    if w.looted > 0 and Flavor.Matches(w.f, flavor) then
      local n = 0
      for _, f in pairs(w.fish) do if Flavor.Matches(f.f, flavor) then n = n + 1 end end
      out[#out + 1] = {zone = zone, name = API.GetZoneName(zone), catches = w.looted, fish = n}
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function API.GetZoneName(zone)
  if zone and zone > 0 and C_Map and C_Map.GetMapInfo then
    local info = C_Map.GetMapInfo(zone)
    if info and info.name then return info.name end
  end
  return format(BJ.L["Zone %d"], zone or 0)
end

--- Bookmarks are account-wide. kind = "fish" | "zone".
function API.IsBookmarked(kind, id) return raw() ~= nil and raw().bookmarks[kind .. ":" .. id] == true end
function API.SetBookmark(kind, id, on)
  if not raw() then return end
  raw().bookmarks[kind .. ":" .. id] = on and true or nil
  BJ:Fire("BOOKMARK", kind, id, on and true or false)
end

--- Newest-first copy of the cast log (max `limit`, default 100). Fields: see DB.lua header.
function API.GetLog(limit)
  local log, out = raw() and raw().log or {}, {}
  for i = #log, math.max(#log - (limit or 100) + 1, 1), -1 do
    local r, copy = log[i], {}
    for k, v in pairs(r) do copy[k] = v end
    if r.i then copy.i = {} for id, q in pairs(r.i) do copy.i[id] = q end end
    out[#out + 1] = copy
  end
  return out
end

--- { classID, subClassID } of a fished item or nil (bycatch detection).
function API.GetItemMeta(itemID)
  local m = raw() and raw().items[itemID]
  return m and {classID = m.c, subClassID = m.s} or nil
end

--- { [enchantID] = { cast, catch } } per lure.
function API.GetLureStats()
  local out = {}
  for id, v in pairs(raw() and raw().lures or {}) do out[id] = {cast = v.cast or 0, catch = v.catch or 0} end
  return out
end

--- Seconds spent fishing: this character, or all characters with allChars; zone optional.
function API.GetFishingTime(zone, allChars)
  local total, guid = 0, UnitGUID and BJ.Clean(UnitGUID("player"))
  for g, c in pairs(raw() and raw().chars or {}) do
    if allChars or g == guid then
      total = total + ((zone and c.zones[zone] and c.zones[zone].time) or (not zone and c.time) or 0)
    end
  end
  return total
end

--- { [spellID] = { name, count, bonus, last, sources = {item=,quest=,spell=,other=,unknown=}, items = {[itemID]=n} } }
function API.GetBuffStats()
  local out = {}
  for id, b in pairs(raw() and raw().buffs or {}) do
    local src, items = {}, {}
    for k, v in pairs(b.src) do src[k] = v end
    for k, v in pairs(b.items) do items[k] = v end
    out[id] = {name = b.name, count = b.n, bonus = b.bonus, last = b.last, sources = src, items = items}
  end
  return out
end
