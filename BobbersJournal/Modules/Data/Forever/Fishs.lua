local _, ns = ...
-- Shipped fish catalogue of the Forever client: [itemID] = flavor mask. Shown grey as "Rumour" in the journal until the game
-- confirms the fish (first catch). Lists come from Wowhead (given by N3zr0k), one block per expansion.
-- The file does nothing on the other client. add(level, mask, {itemIDs}); level 0 Classic, 1 Burning Crusade ...
if ns.Flavor.current ~= ns.Flavor.FOREVER then return end
local FOREVER = ns.Flavor.FOREVER
local add = ns.Catalog.AddFish

-- Classic (level 0); the other expansions are added here as their lists exist
add(0, FOREVER, {
  4603, 6289, 6291, 6303, 6308, 6317, 6358, 6359,
  6361, 6362, 8365, 13422, 13754, 13756, 13757, 13758,
  13759, 13760, 13888, 13889, 21071, 21153,
})
