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
  if GetProfessions and GetProfessionInfo then
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
  -- Fallback (clients without the profession list, port of Glimpse FromSkillLines): the skill list, found by the name of the
  -- fishing spell. GetSkillLineInfo: name, header, expanded, rank, temp, modifier, max
  if GetNumSkillLines and GetSkillLineInfo then
    local ref = spellName(Skill.REFERENCE)
    if ref then
      local ok, name, rank, max, mod = pcall(function()
        for i = 1, GetNumSkillLines() do
          local n, header, _, r, _, modifier, m = GetSkillLineInfo(i)
          if n and not header and n == ref then return n, tonumber(r), tonumber(m), tonumber(modifier) or 0 end
        end
      end)
      if ok and name then return name, rank, max, mod end
    end
  end
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

--- Is this skill line info one of the Fishing lines? The child lines carry no profession enum on some clients, so the
-- parent profession (the Fishing skill line) and the profession name count as well.
function Skill.IsFishingLine(info)
  if type(info) ~= "table" then return false end
  if info.profession == Enum.Profession.Fishing then return true end
  local parent = C_TradeSkillUI.GetProfessionSkillLineID and C_TradeSkillUI.GetProfessionSkillLineID(Enum.Profession.Fishing)
  if parent and (info.parentProfessionID == parent or info.professionID == parent) then return true end
  local name = BJ.Clean(info.professionName)
  if type(name) == "string" then
    name = name:lower()
    for _, w in ipairs({"angeln", "fishing", "pêche", "pesca", "pesca", "рыбал"}) do
      if name:find(w, 1, true) then return true end
    end
  end
  return false
end

-- { {expansion, rank, max, modifier}, ... } of the Fishing skill lines the character has, or nil outside Retail.
function Skill.RetailLines()
  if not (retailOnly() and C_TradeSkillUI.GetAllProfessionTradeSkillLines and C_TradeSkillUI.GetProfessionInfoBySkillLineID) then return nil end
  local out = {}
  pcall(function()
    for _, id in ipairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines()) do
      local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(id)
      if Skill.IsFishingLine(info) and info.parentProfessionID
        and (num(info.maxSkillLevel) or 0) > 0 and (num(info.skillLevel) or 0) > 0 then
        out[#out + 1] = {expansion = BJ.Clean(info.expansionName), rank = num(info.skillLevel), max = num(info.maxSkillLevel),
          modifier = num(info.skillModifier) or 0, id = id, name = BJ.Clean(info.professionName)}
      end
    end
  end)
  -- Fallback: the client's list of child lines of the open profession
  if #out == 0 and C_TradeSkillUI.GetChildProfessionInfos then
    pcall(function()
      for _, info in ipairs(C_TradeSkillUI.GetChildProfessionInfos() or {}) do
        if Skill.IsFishingLine(info)
          and (num(info.maxSkillLevel) or 0) > 0 and (num(info.skillLevel) or 0) > 0 then
          out[#out + 1] = {expansion = BJ.Clean(info.expansionName), rank = num(info.skillLevel), max = num(info.maxSkillLevel),
            modifier = num(info.skillModifier) or 0, id = info.professionID, name = BJ.Clean(info.professionName)}
        end
      end
    end)
  end
  -- Known skill line IDs (seen in game): Classic 2592 ... Midnight 2911. Works on clients that answer without window.
  if #out == 0 then
    pcall(function()
      for _, id in ipairs(Skill.LINE_IDS) do
        local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(id)
        if type(info) == "table" and (num(info.maxSkillLevel) or 0) > 0 and (num(info.skillLevel) or 0) > 0 then
          out[#out + 1] = {expansion = BJ.Clean(info.expansionName), rank = num(info.skillLevel), max = num(info.maxSkillLevel),
            modifier = num(info.skillModifier) or 0, id = id, name = BJ.Clean(info.professionName)}
        end
      end
    end)
  end
  -- The client only fills these lines once the profession window was opened: remember the last values per character
  -- and use them as long as the client has nothing.
  local char = BJ.DB and BJ.DB.raw and BJ.DB:Char()
  if char then
    if #out > 0 then
      char.fishLines = out
    elseif type(char.fishLines) == "table" then
      out = char.fishLines
    end
  end
  return out
end

-- Fishing skill line IDs by expansion level of the fish data (from /bob probe); Dragon Isles 2826, Khaz Algar 2876, Midnight 2911.
Skill.LINE_IDS = {2592, 2591, 2590, 2589, 2588, 2587, 2586, 2585, 2754, 2826, 2876, 2911}

-- Keywords (lowercase, English and German) in the expansion name of a skill line, per expansion level of the fish data.
local LINE_WORDS = {
  [0] = {"classic", "klassisch"}, [1] = {"outland", "scherbenwelt"}, [2] = {"northrend", "nordend"},
  [3] = {"cataclysm", "kataklysmus"}, [4] = {"pandaria"}, [5] = {"draenor"}, [6] = {"legion"},
  [7] = {"kul tiran", "zandalari", "battle for azeroth", "kul tiras", "zandalar"}, [8] = {"shadowlands", "schattenlande"},
  [9] = {"dragon", "drachen"}, [10] = {"khaz algar"}, [11] = {"midnight"},
}

--- The Fishing skill line (entry of RetailLines) that belongs to an expansion level; nil when none matches.
function Skill.RetailLineForLevel(level)
  local words = LINE_WORDS[level]
  if not words then return nil end
  for _, e in ipairs(Skill.RetailLines() or {}) do
    local name = ((type(e.expansion) == "string" and e.expansion or "") .. " " .. (type(e.name) == "string" and e.name or "")):lower()
    for _, w in ipairs(words) do
      if name:find(w, 1, true) then return e end
    end
  end
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
