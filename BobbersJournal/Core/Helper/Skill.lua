local _, ns = ...
local BJ = ns.BJ
-- Fishing skill and spell recognition. skillLine 356 = Fishing.
local Skill = {LINE = 356, SPELLS = {7620, 7731, 7732, 18248, 33095, 51294}, REFERENCE = 7620}
ns.Skill = Skill

local set = {}
for _, id in ipairs(Skill.SPELLS) do set[id] = true end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, id)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  if GetSpellInfo then
    local ok, name = pcall(GetSpellInfo, id)
    if ok and type(name) == "table" then name = name.name end
    if ok and type(name) == "string" and name ~= "" then return name end
  end
end
Skill.SpellName = spellName

--- Is this one of the fishing spells (any rank)? ID first, name as fallback for unknown ranks.
function Skill.IsFishingSpell(spellID)
  spellID = tonumber(BJ.Clean(spellID))
  if not spellID then return false end
  if set[spellID] then return true end
  local name, ref = spellName(spellID), spellName(Skill.REFERENCE)
  return name ~= nil and name == ref
end

-- name, rank, max, modifier of the Fishing skill line, nil if unknown. skillLine 356 = Fishing.
local function profession()
  if not (GetProfessions and GetProfessionInfo) then return nil end
  local ok, name, rank, max, mod = pcall(function()
    local idx = {GetProfessions()}
    for i = 1, 6 do
      if idx[i] then
        local n, _, r, m, _, _, line, modifier = GetProfessionInfo(idx[i])
        if line == Skill.LINE then return n, tonumber(r), tonumber(m), tonumber(modifier) or 0 end
      end
    end
  end)
  if ok and name then return name, rank, max, mod end
end

--- Highest skill of the current tier (75, 150 ...) or nil. Used to bucket catch rates per tier.
function Skill.Tier() local _, _, max = profession() return max end

--- rank, max, modifier (equipment + lure bonus) or nil.
function Skill.Info() local _, rank, max, mod = profession() if rank then return rank, max, mod end end

--- Localised skill name ("Angeln") or nil.
function Skill.Name() return (profession()) end

--- Rank title of the Fishing spell ("Apprentice", "Journeyman" ...) from the spell subtext; nil where the client has none.
function Skill.Rank()
  local name = Skill.Name() or spellName(Skill.REFERENCE)
  if not name then return nil end
  local get = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
  if not get then return nil end
  local ok, text = pcall(get, name)
  text = ok and BJ.Clean(text)
  if type(text) == "string" and text ~= "" then return text end
end

-- Retail only: the old skill line (GetProfessionInfo) is just the base value. Since the expansion skill lines
-- every expansion has its own skill, and gathering has bonus stats (names/values come from the client).
-- Based on the Retail API docs (TradeSkillUI); not verified in game.
local function retailOnly()
  return ns.Flavor and ns.Flavor.current == ns.Flavor.RETAIL and C_TradeSkillUI ~= nil
end

local function num(v) v = BJ.Clean(v) return type(v) == "number" and v or nil end

--- { {expansion, rank, max, modifier}, ... } of the Fishing skill lines the character has, or nil outside Retail.
function Skill.RetailLines()
  if not (retailOnly() and C_TradeSkillUI.GetAllProfessionTradeSkillLines and C_TradeSkillUI.GetProfessionInfoBySkillLineID) then return nil end
  local out = {}
  pcall(function()
    for _, id in ipairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines()) do
      local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(id)
      if type(info) == "table" and info.profession == Enum.Profession.Fishing and info.parentProfessionID
        and (num(info.maxSkillLevel) or 0) > 0 and (num(info.skillLevel) or 0) > 0 then
        out[#out + 1] = {expansion = BJ.Clean(info.expansionName), rank = num(info.skillLevel), max = num(info.maxSkillLevel),
          modifier = num(info.skillModifier) or 0}
      end
    end
  end)
  return out
end

--- { {name, value, pct}, ... } bonus stats of the fishing gathering operation, or nil. Which recipeID the client
--- wants for fishing is unclear, the fishing spell IDs are tried; /bob probe shows what the client answers.
function Skill.RetailStats()
  if not (retailOnly() and C_TradeSkillUI.GetGatheringOperationInfo) then return nil end
  for _, id in ipairs(Skill.SPELLS) do
    local ok, info = pcall(C_TradeSkillUI.GetGatheringOperationInfo, id)
    if ok and type(info) == "table" and type(info.bonusStats) == "table" and #info.bonusStats > 0 then
      local out = {}
      for _, s in ipairs(info.bonusStats) do
        out[#out + 1] = {name = BJ.Clean(s.bonusStatName), value = num(s.bonusStatValue), pct = num(s.ratingPct)}
      end
      return out, num(info.baseSkill), num(info.bonusSkill)
    end
  end
end
