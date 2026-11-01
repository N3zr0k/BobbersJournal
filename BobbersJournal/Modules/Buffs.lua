local _, ns = ...
local BJ, Skill = ns.BJ, ns.Skill
-- Fishing buffs (e.g. Shiny Bauble, lures' auras, event buffs): how often they appear and what caused them.
-- A buff counts as fishing buff when its tooltip names the fishing skill together with a number (same idea as
-- Glimpse FishingBuffs). Event driven: UNIT_AURA rescans the player's helpful auras, but only out of combat and
-- only new spell IDs are looked at (tooltip lookups are expensive).
-- Source is a heuristic, see Classify. World events cannot be told apart and end up as "unknown".
local M = BJ:RegisterModule("Buffs")

local MAX_AURAS = 40
local WINDOW = 3 -- seconds in which a use/cast/turn-in counts as the cause
local known = {}   -- spellID -> true: seen and judged (fishing or not), so tooltips are read once per appearance
local active = {}  -- spellID -> { name, bonus }
local last = {}    -- last item use / cast / quest turn-in: { id, t }
M.active = active

local api = {
  GetAura = C_UnitAuras and (C_UnitAuras.GetAuraDataByIndex or C_UnitAuras.GetBuffDataAtIndex),
  GetTip = C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID,
  GetTipByIndex = C_TooltipInfo and C_TooltipInfo.GetUnitBuff,
  InCombat = function() return InCombatLockdown and InCombatLockdown() or false end,
  Now = function() return GetTime and GetTime() or 0 end,
}
M.api = api

local function plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h", ""):gsub("|h", ""))
end

--- First line part with the skill stem and a number -> number. "+30" wins over other numbers.
local function bonusFromLines(lines, stem)
  for _, line in ipairs(lines or {}) do
    local text = type(line) == "table" and line.leftText
    if type(text) == "string" then
      for part in plain(text):gmatch("[^\r\n]+") do
        if part:find(stem, 1, true) then
          local n = tonumber(part:match("%+%s*(%d+)") or part:match("(%d+)"))
          if n and n > 0 then return n end
        end
      end
    end
  end
end

-- First four letters of the skill name ("Angeln" -> "Ange") also match "Angelfertigkeit"
local function stem()
  local name = Skill.Name()
  if type(name) ~= "string" or name == "" then return nil end
  local first = name:sub(1, 4)
  return first:match("^%a%a%a%a$") and first or name
end

--- "item" (+ itemID) | "quest" | "spell" | "other" | "unknown"
local function classify(spellID, sourceUnit)
  local now = api.Now()
  if last.item and now - last.item.t <= WINDOW then return "item", last.item.id end
  if last.quest and now - last.quest <= WINDOW then return "quest" end
  if last.spell and last.spell.id == spellID and now - last.spell.t <= WINDOW then return "spell" end
  if sourceUnit and BJ.Clean(sourceUnit) ~= nil and sourceUnit ~= "player" then return "other" end
  return "unknown"
end

local function scan()
  if not api.GetAura or api.InCombat() then return end
  local seen = {}
  local st
  for i = 1, MAX_AURAS do
    -- Aura access can be restricted (secret/blocked): a failing call just ends the scan
    local ok, data = pcall(api.GetAura, "player", i, "HELPFUL")
    if not ok or type(data) ~= "table" then break end
    local id, name = BJ.Clean(data.spellId), BJ.Clean(data.name)
    if type(id) == "number" and type(name) == "string" then
      seen[id] = true
      if not known[id] then
        known[id] = true
        st = st or stem()
        local tip = st and ((api.GetTip and data.auraInstanceID and api.GetTip("player", data.auraInstanceID))
          or (api.GetTipByIndex and api.GetTipByIndex("player", i)))
        local bonus = st and tip and bonusFromLines(tip.lines, st)
        if bonus then
          local src, itemID = classify(id, data.sourceUnit)
          active[id] = {name = name, bonus = bonus}
          BJ.DB:AddBuff(id, name, bonus, src, itemID, (ns.Zone.Key()))
        end
      end
    end
  end
  -- Gone auras may come back later as a new appearance
  for id in pairs(known) do
    if not seen[id] then known[id] = nil active[id] = nil end
  end
end

--- Spell IDs of the fishing buffs active right now (for the cast log).
function M.ActiveIDs()
  local out
  for id in pairs(active) do out = out or {} out[#out + 1] = id end
  return out
end

function M:OnEnable()
  BJ:RegisterEvent("UNIT_AURA", "buffs", function(_, unit) if unit == "player" then scan() end end)
  BJ:RegisterEvent("PLAYER_ENTERING_WORLD", "buffs", scan)
  BJ:RegisterEvent("QUEST_TURNED_IN", "buffs", function() last.quest = api.Now() end)
  BJ:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "buffs", function(_, unit, _, spellID)
    spellID = BJ.Clean(spellID)
    if unit == "player" and type(spellID) == "number" then last.spell = {id = spellID, t = api.Now()} end
  end)
  -- The item that was used: insecure post-hook, never alters the call
  local function onUse(bag, slot)
    local get = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
    local ok, id = pcall(get, bag, slot)
    id = ok and BJ.Clean(id) or nil
    if type(id) == "number" then last.item = {id = id, t = api.Now()} end
  end
  if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", onUse)
  elseif UseContainerItem then hooksecurefunc("UseContainerItem", onUse) end
  scan()
end
