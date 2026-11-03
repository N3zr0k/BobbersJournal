local _, ns = ...
-- Recipe items (the "Recipe: ..." items vendors and creatures offer) of recipes that need a fish. Looked up by ID only, so a
-- vendor visit needs no tooltip scan.
--   ns.RecipeItems[itemID] = { fish item IDs the recipe needs }  (empty when the ingredient is no fish of the catalogue)
--   ns.RecipeItems[itemID] = recipeID                           optional: the profession recipe the item teaches
-- The game gives no recipe ID for a recipe item (all teach the spell 483 "Learn"); the ingredients are the line of the item
-- tooltip below "Teaches you how to ...". Made with the list of /bob export (Classic Cooking, deDE client).

-- Classic (Forever) fish recipes
ns.RecipeItems = {
  [5485] = {}, -- Frenzyfilet
  [6325] = {6291}, -- Glänzender Kleinfisch
  [6326] = {6303}, -- Glitschhautmakrele
  [6328] = {6289}, -- Langzahniger Matschschnapper
  [6329] = {6317}, -- Lochfrenzy Supreme
  [6330] = {6308}, -- Stoppelfühlerwels
  [6368] = {6361}, -- Regenbogenflossenthunfisch
  [6369] = {6362}, -- Steinschuppenkabeljau
  [6661] = {}, -- Pikantes Deviat Supreme
  [13939] = {4603}, -- Tüpfelgelbschwanz
  [13940] = {13754}, -- Gekochter glänzender Machtfisch
  [13941] = {13758}, -- Rotkiemenfilet
  [13943] = {13756}, -- Scharfer geräucherter Barsch
  [13945] = {13759}, -- Nachtflossensuppe
  [13946] = {13760}, -- Gedünsteter Sonnenschuppenlachs
  [13948] = {}, -- Machtfischsteak
  [13949] = {13889}, -- Gebackener Lachs
  [17062] = {8365}, -- Mithrilkopfforelle
  [21099] = {21071}, -- Geräucherter Weisenfisch
  [21219] = {21153}, -- Weisenfisch Supreme
}
