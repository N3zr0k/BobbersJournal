local _, ns = ...
-- Fishing lures in the bags: bonus lookup and the best lure. Port of Glimpse FishingLure (Forever-tested there).
-- The bonus comes from a table of known lures, otherwise from the item tooltip (line with the skill name and "+N").
local Lures = {}
ns.Lures = Lures

local WEAPON, ARMOR, CONTAINER = 2, 4, 1 -- item classes that are never lures
-- Tooltip names the fishing skill only as a requirement
local NOT_LURES = {[279967] = true}
local KNOWN = {[6529] = 25, [6530] = 50, [6532] = 75, [6533] = 100, [6811] = 50, [7307] = 75, [34861] = 100}
Lures.KNOWN = KNOWN

local bag = C_Container or {}
local api = {
  NumBags = NUM_BAG_SLOTS or 4,
  GetContainerNumSlots = bag.GetContainerNumSlots or GetContainerNumSlots,
  GetContainerItemID = bag.GetContainerItemID or GetContainerItemID,
  GetContainerItemLink = bag.GetContainerItemLink or GetContainerItemLink,
  GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant,
}
Lures.api = api

local cache = {} -- itemID -> bonus or false (no lure)

local scanTip
-- Tooltip lines of a bag item: C_TooltipInfo where available, else a hidden tooltip.
local function tooltipLines(container, slot)
  local lines = {}
  if C_TooltipInfo and C_TooltipInfo.GetBagItem then
    local ok, data = pcall(C_TooltipInfo.GetBagItem, container, slot)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and ns.BJ.Clean(line.leftText)
        if type(text) == "string" then lines[#lines + 1] = text end
      end
      return lines
    end
  end
  scanTip = scanTip or CreateFrame("GameTooltip", "BobbersJournalLureScan", nil, "GameTooltipTemplate")
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  if scanTip.SetBagItem and pcall(scanTip.SetBagItem, scanTip, container, slot) then
    for i = 1, scanTip:NumLines() do
      local fs = _G["BobbersJournalLureScanTextLeft" .. i]
      local text = fs and ns.BJ.Clean(fs:GetText())
      if type(text) == "string" then lines[#lines + 1] = text end
    end
  end
  return lines
end

-- "Fishing" should find "Fishing skill": the first four letters of the skill name
local function stem()
  local name = ns.Skill and ns.Skill.Name and ns.Skill.Name()
  if type(name) ~= "string" or name == "" then return nil end
  return name:sub(1, 4):lower()
end

-- Lua pattern for ITEM_MIN_SKILL ("Requires %s (%d)"); positional formats like "%1$s (%2$d)" (German client) work too.
-- The skill level is the only capture.
local function requirementPattern()
  local fmt = _G.ITEM_MIN_SKILL
  if type(fmt) ~= "string" then return nil end
  local out, i = "^", 1
  while i <= #fmt do
    local pos = fmt:match("^%%%d%$()", i)
    local c = fmt:sub(i, i)
    if c == "%" then
      local j = pos or (i + 1)
      local conv = fmt:sub(j, j)
      if conv == "s" then out = out .. ".+" i = j + 1
      elseif conv == "d" then out = out .. "(%d+)" i = j + 1
      else out = out .. "%%" i = i + 1 end
    else
      out = out .. (c:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
      i = i + 1
    end
  end
  return out .. "$"
end

-- "Requires Fishing (20)" (ITEM_MIN_SKILL) is no bonus
local function isRequirement(text)
  local pattern = requirementPattern()
  return pattern ~= nil and text:find(pattern) ~= nil
end

local function bonusFromLines(lines, st)
  if not st then return nil end
  for _, text in ipairs(lines) do
    if text:lower():find(st, 1, true) and not isRequirement(text) then
      local n = tonumber(text:match("%+(%d+)"))
      if n then return n end
    end
  end
end

-- Fishing skill the item demands ("Requires Fishing (100)", ITEM_MIN_SKILL); nil when the tooltip names none.
local function requiredSkill(lines)
  local pattern = requirementPattern()
  if not pattern then return nil end
  for _, text in ipairs(lines) do
    local n = tonumber(text:match(pattern))
    if n then return n end
  end
end

--- false when the lure demands a higher fishing skill than the character has (rank plus modifier); true when unknown.
function Lures.Usable(container, slot)
  if not (container and slot) then return true end
  local need = requiredSkill(tooltipLines(container, slot))
  if not need then return true end
  local rank, _, mod -- (an "and" would cut the modifier off)
  if ns.Skill and ns.Skill.Info then rank, _, mod = ns.Skill.Info() end
  rank = tonumber(ns.BJ.Clean(rank))
  if not rank then return true end
  return rank + (tonumber(ns.BJ.Clean(mod)) or 0) >= need
end

--- Skill bonus of the item, nil when it is no lure. container/slot are needed for unknown items (tooltip).
function Lures.Bonus(itemID, container, slot)
  if NOT_LURES[itemID] then return nil end
  if KNOWN[itemID] then return KNOWN[itemID] end
  if cache[itemID] ~= nil then return cache[itemID] or nil end
  local classID = api.GetItemInfoInstant and select(6, api.GetItemInfoInstant(itemID))
  local bonus
  if classID ~= WEAPON and classID ~= ARMOR and classID ~= CONTAINER and container and slot then
    bonus = bonusFromLines(tooltipLines(container, slot), stem())
  end
  -- Tooltip data not loaded yet: do not cache
  if bonus or classID then cache[itemID] = bonus or false end
  return bonus
end

--- { container, slot, id, link, bonus } of the best lure in the bags, or nil.
function Lures.FindBest()
  if not (api.GetContainerNumSlots and api.GetContainerItemID) then return nil end
  local best
  for container = 0, api.NumBags do
    for slot = 1, tonumber(api.GetContainerNumSlots(container)) or 0 do
      local id = api.GetContainerItemID(container, slot)
      local bonus = id and Lures.Bonus(id, container, slot)
      if bonus and (not best or bonus > best.bonus) and Lures.Usable(container, slot) then best = {container = container, slot = slot, id = id, bonus = bonus} end
    end
  end
  if best then
    best.link = api.GetContainerItemLink and api.GetContainerItemLink(best.container, best.slot) or ("item:" .. best.id)
  end
  return best
end

--- container, slot, itemID, link, bonus of the given lure item in the bags (bonus may be nil for unknown items).
function Lures.FindItem(itemID)
  if not (itemID and api.GetContainerNumSlots and api.GetContainerItemID) then return nil end
  for container = 0, api.NumBags do
    for slot = 1, tonumber(api.GetContainerNumSlots(container)) or 0 do
      if api.GetContainerItemID(container, slot) == itemID then
        local link = api.GetContainerItemLink and api.GetContainerItemLink(container, slot) or ("item:" .. itemID)
        return {container = container, slot = slot, id = itemID, link = link, bonus = Lures.Bonus(itemID, container, slot), usable = Lures.Usable(container, slot)}
      end
    end
  end
end

--- true if the item is a fishing lure: known, or recognised by its tooltip while it is in the bags.
function Lures.IsLure(itemID)
  if NOT_LURES[itemID] then return false end
  if KNOWN[itemID] then return true end
  local found = Lures.FindItem(itemID)
  return found ~= nil and found.bonus ~= nil
end

--- Bonus of a lure by item ID alone (tooltip of the item, no bag needed); nil when it is none or the data is not loaded.
function Lures.BonusByID(itemID)
  if NOT_LURES[itemID] then return nil end
  if KNOWN[itemID] then return KNOWN[itemID] end
  local lines = {}
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and ns.BJ.Clean(line.leftText)
        if type(text) == "string" then lines[#lines + 1] = text end
      end
    end
  else
    scanTip = scanTip or CreateFrame("GameTooltip", "BobbersJournalLureScan", nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    if scanTip.SetItemByID and pcall(scanTip.SetItemByID, scanTip, itemID) then
      for i = 1, scanTip:NumLines() do
        local fs = _G["BobbersJournalLureScanTextLeft" .. i]
        local text = fs and ns.BJ.Clean(fs:GetText())
        if type(text) == "string" then lines[#lines + 1] = text end
      end
    end
  end
  return bonusFromLines(lines, stem())
end

-- Lure inventory: filled once after login/reload (Prefill), scanned again at the first cast or lure of the session
-- (Rescan). The second pass matters because item tooltips are often not loaded yet right after login, so a lure could
-- have been judged "no lure" back then.
local rescanned = false

--- Reads the bags once: fills the bonus cache and the lure catalogue of the database. Returns the BagCounts table.
function Lures.Prefill()
  local counts = Lures.BagCounts()
  local raw = ns.BJ.DB and ns.BJ.DB.raw
  if raw and raw.lureCatalog then
    for id, b in pairs(counts) do raw.lureCatalog[id] = b.bonus end
  end
  return counts
end

--- Forgets the "no lure" verdicts and reads the bags again.
function Lures.Rescan()
  for id, v in pairs(cache) do if v == false then cache[id] = nil end end
  return Lures.Prefill()
end

--- Rescan once per session (first fishing cast or first lure use).
function Lures.RescanOnce()
  if rescanned then return end
  rescanned = true
  ns.BJ.Protected("lure rescan", Lures.Rescan)
end

--- { [itemID] = { count, bonus } } of all lures in the bags.
function Lures.BagCounts()
  local out = {}
  if not (api.GetContainerNumSlots and api.GetContainerItemID) then return out end
  for container = 0, api.NumBags do
    for slot = 1, tonumber(api.GetContainerNumSlots(container)) or 0 do
      local id = api.GetContainerItemID(container, slot)
      local bonus = id and Lures.Bonus(id, container, slot)
      if bonus then
        local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(container, slot)
        local n = type(info) == "table" and tonumber(info.stackCount) or 1
        local e = out[id]
        if not e then e = {count = 0, bonus = bonus, usable = false} out[id] = e end
        e.count = e.count + (n or 1)
        if not e.usable and Lures.Usable(container, slot) then e.usable = true end
      end
    end
  end
  return out
end
