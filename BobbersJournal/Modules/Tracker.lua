local _, ns = ...
local BJ, Zone, Skill = ns.BJ, ns.Zone, ns.Skill
-- Counts casts and catches (port of Glimpse_Professions FishingRecord, tested there on Forever only).
-- A cast is settled when it ends:
--   loot window          -> catch (also counts as cast)
--   channel ends standing -> miss (cast without catch)
--   moving/falling/combat -> abort (not counted as cast)
-- A catch only counts after an open cast, so a second loot window is not counted twice.
local M = BJ:RegisterModule("Tracker")

local LOOT_ITEM = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
local ABORT_WAIT = 0.5 -- the loot window can arrive shortly after the channel ends
local DUPLICATE_WINDOW = 2 -- seconds in which a second SUCCEEDED counts as the same cast
local pending -- { zone, tier, pos, outcome }

local api = {
  IsFishingLoot = IsFishingLoot,
  GetNumLootItems = (C_Loot and C_Loot.GetNumLootItems) or GetNumLootItems,
  GetLootSlotType = (C_Loot and C_Loot.GetLootSlotType) or GetLootSlotType,
  GetLootSlotLink = (C_Loot and C_Loot.GetLootSlotLink) or GetLootSlotLink,
  GetLootSlotInfo = GetLootSlotInfo,
  GetUnitSpeed = GetUnitSpeed,
  IsFalling = IsFalling,
  InCombat = UnitAffectingCombat,
  After = C_Timer and C_Timer.After,
}
M.api = api -- replaceable in tests

local function readLoot()
  local items = {}
  for slot = 1, tonumber(api.GetNumLootItems and api.GetNumLootItems()) or 0 do
    if api.GetLootSlotType(slot) == LOOT_ITEM then
      local link = BJ.Clean(api.GetLootSlotLink(slot))
      local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
      if id then
        local qty = api.GetLootSlotInfo and select(3, api.GetLootSlotInfo(slot))
        items[id] = (items[id] or 0) + (tonumber(BJ.Clean(qty)) or 1)
      end
    end
  end
  return items
end

local function disturbed()
  local ok, speed = pcall(api.GetUnitSpeed, "player")
  if ok and (tonumber(BJ.Clean(speed)) or 0) > 0 then return true end
  if api.IsFalling then
    local fine, v = pcall(api.IsFalling)
    if fine and BJ.Clean(v) == true then return true end
  end
  if api.InCombat then
    local fine, v = pcall(api.InCombat, "player")
    if fine and BJ.Clean(v) == true then return true end
  end
  return false
end

-- Fishing time: cast start to end of the cast, measured from the two events (no polling). Capped against stale casts.
function M.Duration(open)
  local now = GetTime and GetTime() or 0
  return math.max(0, math.min(now - (open.t0 or now), 120))
end

local function resolve()
  local open = pending
  if not (open and open.outcome) then return end
  pending = nil
  BJ:Debug("counted as " .. open.outcome)
  open.duration = M.Duration(open)
  BJ.DB:AddCast(open.zone, open.tier, open.outcome, open)
end

local function onSucceeded(_, unit, _, spellID)
  if unit ~= "player" or not Skill.IsFishingSpell(spellID) then return end
  if pending then
    -- Retail can report SUCCEEDED twice for one cast (cast + channel spell); the duplicate must not settle the open cast as a miss.
    local age = (GetTime and GetTime() or 0) - (pending.t0 or 0)
    if not pending.outcome and age < DUPLICATE_WINDOW then
      BJ:Debug("duplicate cast event ignored (spell " .. tostring(spellID) .. ")")
      return
    end
    pending.outcome = pending.outcome or "miss"
    resolve()
  end
  local map, x, y = Zone.Where()
  local rank, _, bonus = Skill.Info()
  local hour = GetGameTime and (GetGameTime()) -- server time, 0-23
  local sub = GetSubZoneText and BJ.Clean(GetSubZoneText())
  local _, lure = ns.Gear.GetMainHandEnchant()
  pending = {t0 = GetTime and GetTime() or 0, zone = (Zone.Key()), tier = Skill.Tier(), pos = map and {map = map, x = x, y = y} or nil,
    skill = rank, bonus = bonus, hour = tonumber(BJ.Clean(hour)), sub = (sub and sub ~= "") and sub or nil,
    lure = tonumber(BJ.Clean(lure)), buffs = BJ.modules.Buffs and BJ.modules.Buffs.ActiveIDs()}
  BJ:Debug(format("cast started, zone %s, tier %s", tostring(pending.zone), tostring(pending.tier)))
end

local function onStop(_, unit, _, spellID)
  if unit ~= "player" or not (pending and not pending.outcome) or not Skill.IsFishingSpell(spellID) then return end
  local open = pending
  open.outcome = disturbed() and "abort" or "miss"
  if api.After then
    api.After(ABORT_WAIT, function() if pending == open then resolve() end end)
  else
    resolve()
  end
end

local function onLoot()
  if not pending then return end
  local ok, fishing = pcall(api.IsFishingLoot)
  if not ok or BJ.Clean(fishing) ~= true then return end
  local open = pending
  pending = nil
  open.duration = M.Duration(open)
  BJ.DB:AddCatch(open.zone, open.tier, readLoot(), open.pos, open)
end

function M:OnEnable()
  BJ:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "tracker", onSucceeded)
  BJ:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", "tracker", onStop)
  BJ:RegisterEvent("LOOT_OPENED", "tracker", onLoot)
end
