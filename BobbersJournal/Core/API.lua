local _, ns = ...
local BJ = ns.BJ
local DB, Flavor = BJ.DB, ns.Flavor
-- Public read-only API for other addons: BobbersJournal.API (also _G.BobbersJournalAPI).
-- Returns copies, never internal tables. Zone = uiMapID (negative instanceID in instances).
-- `flavor` is optional (Flavor.FOREVER=1, RETAIL=2, BOTH=3); default is the running client.
local API = {VERSION = 1, FOREVER = Flavor.FOREVER, RETAIL = Flavor.RETAIL, BOTH = Flavor.BOTH}
BJ.API = API
_G.BobbersJournalAPI = API

--- The data of the running client. The data of the other client lives in the other client's own file, so a `flavor`
--- argument that names it returns nothing; BOTH means this client.
local function raw(flavor)
  if flavor and flavor ~= Flavor.BOTH and flavor ~= Flavor.current then return nil end
  return DB.raw
end

function API.IsReady() return raw() ~= nil end
function API.GetFlavor() return Flavor.current end

--- List of { itemID, drops, chance, avgQuantity } sorted by drops, for a zone.
function API.GetZoneFish(zone, flavor)
  local r = raw(flavor)
  local w = r and r.zones[zone]
  local out = {}
  if not w or w.looted <= 0 then return out end
  for id, f in pairs(w.fish) do
    out[#out + 1] = {itemID = id, drops = f.drops, chance = math.min(f.drops / w.looted, 1), avgQuantity = f.qty / f.drops}
  end
  table.sort(out, function(a, b) if a.drops ~= b.drops then return a.drops > b.drops end return a.itemID < b.itemID end)
  return out
end

-- Word for "fish" in the client languages; the tooltip of a real fish names it (type line, flavour text, "Fish" reagent).
local FISH_WORDS = {"fish", "fisch", "poisson", "pez", "pescado", "pesce", "peixe", "рыб", "鱼", "魚", "물고기", "생선"}
-- Words that contain "fish" but speak about the profession.
local FISHING_WORDS = {"fishing", "fisher", "fischen", "fischer", "pêche", "pescador", "pesca", "pescar", "pescatore", "рыбал", "рыбач", "钓鱼", "釣魚", "낚시"}

local function mentionsFish(lines)
  for _, l in ipairs(lines) do
    local t = type(l.text) == "string" and l.text:lower()
    if t then
      for _, w in ipairs(FISHING_WORDS) do t = t:gsub(w, " ") end
      for _, w in ipairs(FISH_WORDS) do if t:find(w, 1, true) then return true end end
    end
  end
  return false
end

--- "fish", "material" (crafting material, consumable, openable: no fish but no junk either) or "junk".
--- Unknown items (data not loaded yet) count as fish, so nothing disappears by mistake.
function API.ItemCategory(itemID)
  if ns.Catalog.fish[itemID] then return "fish" end
  local m = DB:ItemMeta(itemID)
  if not m then return "fish" end
  local isMaterial = m.c == 7 or m.c == 0
  if not isMaterial then
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if getSpell and getSpell(itemID) then isMaterial = true end
  end
  if not isMaterial then return "junk" end
  if m.c == 7 then
    local tip = DB:ItemTooltip(itemID)
    if not tip then return "fish" end -- tooltip not read yet
    if mentionsFish(tip) then return "fish" end
  end
  return "material"
end

--- True for everything the fish tab does not list: junk and "crafting materials & others".
function API.IsJunk(itemID)
  return API.ItemCategory(itemID) ~= "fish"
end

--- List of { zone, drops, chance } for one fish across all known zones.
function API.GetFishZones(itemID, flavor)
  local out = {}
  local r = raw(flavor)
  for zone, w in pairs(r and r.zones or {}) do
    local f = w.fish[itemID]
    if f and w.looted > 0 then
      out[#out + 1] = {zone = zone, drops = f.drops, chance = math.min(f.drops / w.looted, 1)}
    end
  end
  table.sort(out, function(a, b) return a.drops > b.drops end)
  return out
end

--- List of { x, y, count, fish = { [itemID] = count } } (map-normalised 0..1). With itemID: only spots that gave it.
function API.GetZoneSpots(zone, itemID, flavor)
  local r = raw(flavor)
  local out = {}
  for code, fish in pairs(r and r.points[zone] or {}) do
    if not itemID or fish[itemID] then
      local copy, total = {}, 0
      for id, n in pairs(fish) do copy[id] = n total = total + n end
      local x, y = DB.Decode(code)
      out[#out + 1] = {x = x, y = y, count = itemID and fish[itemID] or total, fish = copy}
    end
  end
  table.sort(out, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.y < b.y end)
  return out
end

--- Loot windows seen in a zone (denominator of the chances).
function API.GetZoneCatches(zone)
  local w = raw() and raw().zones[zone]
  return w and w.looted or 0
end

--- Recipes found that use the fish: list of { id = recipeID, name }, sorted by name.
function API.GetFishRecipes(itemID)
  local r = raw()
  local out, seen = {}, {}
  for id, rec in pairs(ns.Catalog.recipes) do
    for _, fishID in ipairs(rec.fish or {}) do
      if fishID == itemID then seen[id] = rec.name end
    end
  end
  for id, rec in pairs(r and r.recipes or {}) do
    if rec.fish and rec.fish[itemID] then
      local name = r.text.recipes[id]
      seen[id] = type(name) == "string" and name or seen[id] or true
    end
  end
  for id, name in pairs(seen) do
    local live = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    out[#out + 1] = {id = id, name = (type(live) == "string" and live ~= "" and live) or (type(name) == "string" and name) or ("#" .. id)}
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- Saved vendors and teachers: list of { id, name, map, x, y, trainer, repair, items = { [itemID] = category }, offers = { [itemID] = { p, q, lim, cost, need } }, lessons = { { n, r, c, k, l } }, details = { tip, title, type, level, ... } } for this client.
function API.GetNPCs(flavor)
  local out, merged = {}, {}
  -- shipped entries first, then what the game showed wins field by field
  for id, n in pairs(ns.Catalog.vendors) do
    merged[id] = {n = n.n, f = n.f, map = n.map, x = n.x, y = n.y, trainer = n.trainer, items = {}}
    for item, cat in pairs(n.items or {}) do merged[id].items[item] = cat end
  end
  for id, n in pairs(raw() and raw().npcs or {}) do
    local e = merged[id] or {items = {}}
    merged[id] = e
    for k, v in pairs(n) do
      if k == "items" then for item, cat in pairs(v) do e.items[item] = cat end
      elseif k == "offers" then e.offers = e.offers or {} for item, o in pairs(v) do e.offers[item] = o end
      else e[k] = v end
    end
  end
  for id, n in pairs(merged) do
    if Flavor.Matches(n.f, flavor) then
      out[#out + 1] = {id = id, name = n.n, map = n.map, x = n.x, y = n.y, trainer = n.trainer, items = n.items, offers = n.offers, lessons = n.lessons, repair = n.repair, details = n.details}
    end
  end
  table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
  return out
end

--- Quantity of a fish caught by this character (or all characters with allChars).
function API.GetCaught(itemID, allChars)
  local total, guid = 0, UnitGUID and BJ.Clean(UnitGUID("player"))
  for g, c in pairs(raw() and raw().chars or {}) do
    if allChars or g == guid then total = total + (c.fish[itemID] or 0) end
  end
  return total
end

--- List of { name, class, caught, current } of every character that caught the fish (most first).
function API.GetCharCatches(itemID)
  local out = {}
  if not raw() then return out end
  local mine = DB:Char()
  for _, c in pairs(raw().chars) do
    local n = c.fish[itemID] or 0
    if n > 0 then out[#out + 1] = {name = c.name or "?", class = c.class, caught = n, current = c == mine} end
  end
  table.sort(out, function(a, b) return a.caught > b.caught end)
  return out
end

--- { cast, catch, abort } of this character; zone optional.
function API.GetTotals(zone, account)
  local c = raw() and DB:Char()
  if not c then return {cast = 0, catch = 0, abort = 0} end
  if zone and account then
    -- all characters of the account (the fish data of a zone is account wide, too)
    local out = {cast = 0, catch = 0, abort = 0}
    for _, ch in pairs(raw().chars or {}) do
      local z = type(ch) == "table" and ch.zones and ch.zones[zone]
      if z then
        out.cast, out.catch, out.abort = out.cast + (z.cast or 0), out.catch + (z.catch or 0), out.abort + (z.abort or 0)
      end
    end
    return out
  end
  local s = c
  if zone then s = c.zones[zone] or {} end -- a zone without data counts 0, not the totals of the character
  return {cast = s.cast or 0, catch = s.catch or 0, abort = s.abort or 0}
end

--- fn(event, ...) with event "CATCH" (zone, {itemID=qty}) or "CAST" (zone, outcome). Errors in fn are contained.
function API.Listen(fn) if type(fn) == "function" then BJ:Listen(fn) end end

--- List of { itemID, caught, zones } for every fish seen anywhere (caught = this character).
function API.GetFishList(flavor)
  local seen, out = {}, {}
  local r = raw(flavor)
  for _, w in pairs(r and r.zones or {}) do
    for id in pairs(w.fish) do seen[id] = (seen[id] or 0) + 1 end
  end
  for id, zones in pairs(seen) do out[#out + 1] = {itemID = id, caught = API.GetCaught(id), zones = zones} end
  table.sort(out, function(a, b) return a.itemID < b.itemID end)
  return out
end

--- List of { zone, name, catches, fish } for every zone with data.
function API.GetZoneList(flavor)
  local out = {}
  local r = raw(flavor)
  for zone, w in pairs(r and r.zones or {}) do
    if w.looted > 0 then
      local n = 0
      for _ in pairs(w.fish) do n = n + 1 end
      out[#out + 1] = {zone = zone, name = API.GetZoneName(zone), catches = w.looted, fish = n}
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- Sub zones of a zone: list of { name, catches }, most catches first.
function API.GetSubZones(zone)
  local w = raw() and raw().zones[zone]
  local out = {}
  for nr, sz in pairs(w and w.subs or {}) do
    local name = DB:SubName(zone, nr)
    if name and sz.looted and sz.looted > 0 then out[#out + 1] = {name = name, catches = sz.looted, id = nr} end
  end
  table.sort(out, function(a, b) if a.catches ~= b.catches then return a.catches > b.catches end return a.name < b.name end)
  return out
end

--- Fish of a sub zone: list of { itemID, drops, chance }, most drops first (empty for entries recorded before sub zone fish existed).
function API.GetSubZoneFish(zone, name)
  local w = raw() and raw().zones[zone]
  local nr = raw() and DB:FindSub(zone, name)
  local sz = w and nr and w.subs and w.subs[nr]
  local out = {}
  if not sz or not sz.fish or (sz.looted or 0) <= 0 then return out end
  for id, f in pairs(sz.fish) do
    out[#out + 1] = {itemID = id, drops = f.drops, chance = math.min(f.drops / sz.looted, 1)}
  end
  table.sort(out, function(a, b) if a.drops ~= b.drops then return a.drops > b.drops end return a.itemID < b.itemID end)
  return out
end

--- Catch positions of a sub zone ({x, y} in 0..1 map coordinates, one per rounded position) from the cast log (the
--- fishing spots carry no sub zone); the area of the sub zone on the map is drawn around them.
function API.GetSubZonePoints(zone, name)
  local out, seen = {}, {}
  local function add(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local k = math.floor(x * 50 + 0.5) .. ":" .. math.floor(y * 50 + 0.5)
    if not seen[k] then seen[k] = true out[#out + 1] = {x = x, y = y} end
  end
  local r = raw()
  local nr = r and DB:FindSub(zone, name)
  if not nr then return out end
  for _, rec in ipairs(r.log or {}) do
    if rec.k == "c" and rec.z == zone and rec.s == nr then add(rec.x, rec.y) end
  end
  return out
end

--- Area of a sub zone from the game's map exploration data (Retail: C_MapExplorationInfo). The map overlays of the
--- explored areas have a shape; the overlay whose centre lies in an area of this name is the sub zone. Returns
--- { layer = layer info of the map art, overlays = { exploration infos with fileDataIDs/offsets } } or nil when the client
--- has no such data or the sub zone is not explored yet. Cached when found (exploring later changes the answer).
local areaCache = {}
function API.GetSubZoneArea(zone, name)
  local info = C_MapExplorationInfo
  if not (info and info.GetExploredMapTextures and info.GetExploredAreaIDsAtPosition and C_Map and C_Map.GetAreaInfo and CreateVector2D) then return nil end
  local key = zone .. ":" .. name
  if areaCache[key] then return areaCache[key] end
  local okT, textures = pcall(info.GetExploredMapTextures, zone)
  local okL, layers = pcall(C_Map.GetMapArtLayers, zone)
  local layer = okL and type(layers) == "table" and layers[1]
  if not (okT and type(textures) == "table" and layer and layer.layerWidth and layer.layerWidth > 0) then return nil end
  local out = {}
  for _, tex in ipairs(textures) do
    local r = tex.hitRect
    if r and tex.fileDataIDs then
      local pos = CreateVector2D((r.left + r.right) / 2 / layer.layerWidth, (r.top + r.bottom) / 2 / layer.layerHeight)
      local ok, ids = pcall(info.GetExploredAreaIDsAtPosition, zone, pos)
      if ok and type(ids) == "table" then
        for _, id in ipairs(ids) do
          if C_Map.GetAreaInfo(id) == name then out[#out + 1] = tex break end
        end
      end
    end
  end
  if #out == 0 then return nil end
  areaCache[key] = {layer = layer, overlays = out}
  return areaCache[key]
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
  local items = raw() and raw().lureItems or {}
  for id, v in pairs(raw() and raw().lures or {}) do out[id] = {cast = v.cast or 0, catch = v.catch or 0, time = v.time or 0, applied = v.applied or 0, itemID = items[id]} end
  return out
end

--- This play session (since login): { time = seconds fished, fish = { [itemID] = quantity } }. Copy.
function API.GetSession()
  local s = DB.session
  local out = {time = s and s.time or 0, fish = {}}
  for id, n in pairs(s and s.fish or {}) do out.fish[id] = n end
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

--- True when the game itself confirmed the entry (caught it / used it / found it by the scan); false = "rumour" from shipped data.
--- kind = "fish" | "lure"; for lures id is the lure itemID.
function API.IsConfirmed(kind, id)
  if not raw() then return false end
  if kind == "fish" then
    for _, c in pairs(raw().chars) do if (c.fish[id] or 0) > 0 then return true end end
    for _, w in pairs(raw().zones) do if w.fish[id] then return true end end
    return false
  end
  if kind == "lure" then
    if raw().lureCatalog and raw().lureCatalog[id] then return true end
    for _, item in pairs(raw().lureItems or {}) do if item == id then return true end end
  end
  return false
end
