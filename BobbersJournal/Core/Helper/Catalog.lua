local _, ns = ...
-- Catalogue of things that can be fished, so the journal can show what you have not caught yet (grey entries).
--   fish:  [itemID] = true  - fish and other crafting materials that come out of fishing (shipped data, per game version)
--   lures: [itemID] = bonus - lures: the known ones plus the ones found by the in-game scan (saved in the data base)
-- The fish list is data that has to be collected outside the game (the client has no query for "everything fishable");
-- it stays empty until a data file is added to Core/Data/.
local Catalog = {fish = {}, fishExp = {}, vendors = {}, recipes = {}} -- fishExp[itemID] = expansion level (0 Classic, 1 Burning Crusade ...)
ns.Catalog = Catalog

--- itemIDs of all known lures with their bonus.
function Catalog.Lures()
  local out = {}
  for id, bonus in pairs(ns.Lures and ns.Lures.KNOWN or {}) do out[id] = bonus end
  for id, bonus in pairs(ns.BJ.DB.raw and ns.BJ.DB.raw.lureCatalog or {}) do out[id] = bonus end
  return out
end

--- Expansion level that is active on this client (0 Classic, 1 Burning Crusade ...); Retail: everything.
function Catalog.ActiveExpansion()
  if ns.Flavor.current == ns.Flavor.RETAIL then return 99 end
  local get = GetServerExpansionLevel or GetClassicExpansionLevel or GetExpansionLevel
  local level = get and tonumber(ns.BJ.Clean(get()))
  return level or 0
end

--- Registers fish of one expansion: Catalog.AddFish(level, mask, {ids}).
function Catalog.AddFish(level, mask, ids)
  for _, id in ipairs(ids) do Catalog.fish[id] = mask Catalog.fishExp[id] = level end
end

--- Registers a shipped vendor or teacher (see Modules/Data/<Flavor>/Vendors.lua).
function Catalog.AddVendor(npcID, info)
  local v = {f = ns.Flavor.current, items = {}}
  for k, val in pairs(info) do v[k] = val end
  Catalog.vendors[npcID] = v
end

--- Registers a shipped recipe with the fish it uses: Catalog.AddRecipe(recipeID, name, {itemIDs}).
function Catalog.AddRecipe(recipeID, name, fishIDs)
  Catalog.recipes[recipeID] = {name = name, fish = fishIDs}
end
