local _, ns = ...
-- Shipped vendors and teachers of the Forever client. Merged with what the game showed (saved in the database, which wins).
-- ns.Catalog.AddVendor(npcID, { n = name, map = uiMapID, x = 0..1, y = 0..1, trainer = true,
--   items = { [itemID] = "pole" | "lure" | "recipe" | "fish" | "other" } })
if ns.Flavor.current ~= ns.Flavor.FOREVER then return end
-- luacheck: ignore 211
local add = ns.Catalog.AddVendor

-- add(12345, {n = "Name", map = 84, x = 0.5, y = 0.5, items = {[6256] = "pole"}})
