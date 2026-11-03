local _, ns = ...
-- Shipped fish catalogue of the Retail client: [itemID] = flavor mask. Shown grey as "Rumour" in the journal until the game
-- confirms the fish (first catch). Lists come from Wowhead (given by N3zr0k), one block per expansion.
-- The file does nothing on the other client. add(level, mask, {itemIDs}); level 0 Classic, 1 Burning Crusade ...
if ns.Flavor.current ~= ns.Flavor.RETAIL then return end
local RETAIL = ns.Flavor.RETAIL
local add = ns.Catalog.AddFish

-- Classic (level 0)
add(0, RETAIL, {
  4603, 6289, 6291, 6303, 6308, 6317, 6358, 6359,
  6361, 6362, 8365, 13422, 13754, 13756, 13757, 13758,
  13759, 13760, 13888, 13889, 21071, 21153,
})

-- Burning Crusade (level 1, Retail only)
add(1, RETAIL, {
  27422, 27425, 27429, 27435, 27437, 27438, 27439, 27515,
  27516, 33823, 33824,
})

-- Wrath of the Lich King (level 2, Retail only)
add(2, RETAIL, {
  41800, 41801, 41802, 41803, 41805, 41806, 41807, 41808,
  41809, 41810, 41812, 41813, 41814,
})

-- Cataclysm (level 3, Retail only)
add(3, RETAIL, {
  53062, 53063, 53064, 53065, 53066, 53067, 53068, 53069,
  53070, 53071, 53072,
})

-- Mists of Pandaria (level 4, Retail only)
add(4, RETAIL, {
  74856, 74857, 74859, 74860, 74861, 74863, 74864, 74865,
  74866, 83064,
})

-- Warlords of Draenor (level 5, Retail only)
add(5, RETAIL, {
  111589, 111595, 111601, 111650, 111651, 111652, 111656, 111658,
  111659, 111662, 111663, 111664, 111665, 111666, 111667, 111668,
  111669, 111670, 111671, 111672, 111673, 111674, 111675, 111676,
  118564, 118566, 124669,
})

-- Legion (level 6, Retail only)
add(6, RETAIL, {
  124107, 124108, 124109, 124110, 124111, 124112, 133607,
})

-- Battle for Azeroth (level 7, Retail only)
add(7, RETAIL, {
  152543, 152544, 152545, 152547, 152548, 152549, 162515, 162516,
  162517, 167562, 168262, 168302, 168646, 174327, 174328,
})

-- Shadowlands (level 8, Retail only)
add(8, RETAIL, {
  173032, 173033, 173034, 173035, 173036, 173037,
})

-- Dragonflight (level 9, Retail only)
add(9, RETAIL, {
  194730, 194966, 194967, 194968, 194969, 194970, 199344, 200061,
  200074,
})

-- The War Within (level 10, Retail only)
add(10, RETAIL, {
  220134, 220135, 220136, 220137, 220138, 220139, 220142, 220143,
  220144, 220145, 220146, 220147, 220148, 220149, 220150, 220151,
  220152, 220153, 222533,
})

-- Midnight (level 11, Retail only)
add(11, RETAIL, {
  238365, 238366, 238368, 238369, 238370, 238371, 238372, 238373,
  238374, 238375, 238376, 238377, 238378, 238379, 238380, 238381,
  238382, 238383, 238384, 274587, 274588, 274589, 274590, 274591,
  274592, 274593, 274594, 274595, 274596, 274597, 279091, 279094,
  279100, 279105, 279106,
})

-- Each block is shown only when its expansion is active on the client (Catalog.ActiveExpansion).
