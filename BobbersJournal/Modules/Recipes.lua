local _, ns = ...
local BJ = ns.BJ
-- Learns which recipes use a fish: whenever a profession window opens, its recipes are read once per session and the recipe ID
-- (with its name) is saved on every fish of the catalogue that the recipe needs (DB:AddFishRecipe). The journal and the fishing
-- journal show the list on the fish page. Retail reads the recipe schematics in small steps (no big frame spike), Forever the
-- trade skill list. Not tested in the game.
local M = BJ:RegisterModule("Recipes")

local STEP = 100 -- recipes per frame (Retail)
local scanned = {}

--- Saves the recipe on the fish; true when the item is one of the fish.
local function note(itemID, recipeID, name)
  if not ns.Catalog.fish[itemID] then return false end
  BJ.DB:AddFishRecipe(itemID, recipeID, name)
  return true
end

--- Saves the recipe on every fish it needs; true when a fish is among the ingredients.
local function retailFish(schematic, recipeID, name)
  local usesFish = false
  for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
    for _, reagent in ipairs(slot.reagents or {}) do
      if reagent.itemID and note(reagent.itemID, recipeID, name) then usesFish = true end
    end
  end
  return usesFish
end

local function scanRetail()
  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeSchematic) then return end
  if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsNPCCrafting and T.IsNPCCrafting()) then return end
  local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
  local key = base and base.professionID
  if not key or scanned[key] then return end
  local ids = T.GetAllRecipeIDs()
  if type(ids) ~= "table" or #ids == 0 then return end
  scanned[key] = true
  local index, dummies, fishPages, sample = 1, 0, 0, nil
  local function step()
    local last = math.min(index + STEP - 1, #ids)
    for i = index, last do
      local id = ids[i]
      local info = T.GetRecipeInfo and T.GetRecipeInfo(id)
      if info and info.isDummyRecipe then
        -- fish pages of the fishing journal: the description holds fishing score and catch rank (no click needed)
        dummies = dummies + 1
        local diary = BJ.modules.Diary
        local itemID = diary and diary.FishByName and type(info.name) == "string" and diary.FishByName(info.name)
        if itemID and T.GetRecipeDescription then
          local ok, text = pcall(T.GetRecipeDescription, id, {}, nil)
          fishPages = fishPages + 1
          if ok then
            text = BJ.Clean(text)
            if not sample and type(text) == "string" then sample = info.name .. ": " .. text:sub(1, 300):gsub("|", "||"):gsub("\n", "\\n") end
            diary.SaveRankFromText(itemID, text)
          end
        end
      else
        local ok, schematic = pcall(T.GetRecipeSchematic, id, false)
        if ok and type(schematic) == "table" then
          local usesFish = retailFish(schematic, id, info and info.name)
          -- learned recipes with a fish ingredient: marked as learned for this character (once per recipe)
          if usesFish and info and info.learned then BJ.DB:SetRecipeLearned(id, info.name) end
        end
      end
    end
    index = last + 1
    if index > #ids then
      BJ:Debug(format("recipes: %d recipes, %d fish pages (%d with matching fish). Sample: %s", #ids, dummies, fishPages, tostring(sample)))
    end
    if index <= #ids then C_Timer.After(0, function() BJ.Protected("recipes", step) end) end
  end
  step()
end

local function scanForever()
  if not GetNumTradeSkills then return end
  for i = 1, GetNumTradeSkills() do
    local name, kind = GetTradeSkillInfo(i)
    if kind ~= "header" then
      local link = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i)
      local recipeID = type(link) == "string" and tonumber(link:match("enchant:(%d+)"))
      if recipeID then
        local usesFish = false
        for j = 1, (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) or 0) do
          local rlink = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j)
          local itemID = type(rlink) == "string" and tonumber(rlink:match("item:(%d+)"))
          if itemID and note(itemID, recipeID, name) then usesFish = true end
        end
        -- the list of the trade skill only holds learned recipes
        if usesFish then BJ.DB:SetRecipeLearned(recipeID, name) end
      end
    end
  end
end

--- A recipe was just learned (Retail): when it needs a fish it is saved and marked as learned right away.
local function learned(recipeID)
  local T = C_TradeSkillUI
  if type(recipeID) ~= "number" or not (T and T.GetRecipeSchematic) then return end
  local ok, schematic = pcall(T.GetRecipeSchematic, recipeID, false)
  if not (ok and type(schematic) == "table") then return end
  local info = T.GetRecipeInfo and T.GetRecipeInfo(recipeID)
  local name = info and BJ.Clean(info.name)
  local usesFish = retailFish(schematic, recipeID, name)
  if usesFish then BJ.DB:SetRecipeLearned(recipeID, name) BJ:Debug("recipes: learned " .. tostring(name)) end
end

function M:OnEnable()
  if ns.Flavor.current == ns.Flavor.RETAIL then
    BJ:RegisterEvent("NEW_RECIPE_LEARNED", "recipes", function(_, recipeID)
      BJ.Protected("recipes", learned, BJ.Clean(recipeID))
    end)
    -- the list arrives a moment after the window opened
    BJ:RegisterEvent("TRADE_SKILL_LIST_UPDATE", "recipes", function()
      if C_Timer then C_Timer.After(1, function() BJ.Protected("recipes", scanRetail) end) end
    end)
  else
    BJ:RegisterEvent("TRADE_SKILL_SHOW", "recipes", function() BJ.Protected("recipes", scanForever) end)
    BJ:RegisterEvent("TRADE_SKILL_UPDATE", "recipes", function() BJ.Protected("recipes", scanForever) end)
  end
end
