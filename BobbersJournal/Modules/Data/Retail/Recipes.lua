local _, ns = ...
-- Shipped recipes that use a fish of the Retail client. Merged with what the game showed (saved in the database).
-- ns.Catalog.AddRecipe(recipeID, name, {fishItemIDs})
if ns.Flavor.current ~= ns.Flavor.RETAIL then return end
local add = ns.Catalog.AddRecipe

-- add(12345, "Recipe name", {13754, 13758})
