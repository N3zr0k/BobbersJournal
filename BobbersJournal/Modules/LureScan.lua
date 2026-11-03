local _, ns = ...
local BJ = ns.BJ
local L = BJ.L
-- Reads the lure list out of the game: goes through the item IDs of the client (GetItemInfoInstant needs no server
-- query), keeps the consumables, loads their data in small portions and keeps those whose tooltip gives a fishing
-- bonus (ns.Lures.BonusByID). Result: DB.lureCatalog[itemID] = bonus. Timers only, no OnUpdate; started from the
-- options (and once by itself).
local M = BJ:RegisterModule("LureScan")

local MAX_ID, STEP = 320000, 4000   -- item IDs per tick
local BATCH, PAUSE = 60, 0.25       -- items requested per portion, seconds between portions
local CONSUMABLE = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local running, queue, pending, nextID, found, total

function M.IsRunning() return running == true end
function M.Status()
  if running then return format(L["Scanning lures: %d%%"], math.floor((total - #queue - M.pendingCount()) / math.max(total, 1) * 100)) end
  local n = 0
  for _ in pairs(BJ.DB.raw and BJ.DB.raw.lureCatalog or {}) do n = n + 1 end
  return format(L["Lures known: %d"], n + 0)
end
function M.pendingCount() local n = 0 for _ in pairs(pending or {}) do n = n + 1 end return n end

local function check(id)
  pending[id] = nil
  local bonus = ns.Lures.BonusByID(id)
  if bonus then BJ.DB.raw.lureCatalog[id] = bonus found = found + 1 end
end

local function finish()
  running = false
  BJ.DB.raw.lureScanDone = true
  BJ:Print(format(L["Lure scan finished: %d lures found."], found))
  BJ:Fire("LURESCAN")
end

local function portion()
  if not running then return end
  local n = 0
  while n < BATCH and #queue > 0 do
    local id = table.remove(queue)
    n = n + 1
    if C_Item and C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(id) then check(id)
    else
      pending[id] = true
      if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) else check(id) end
    end
  end
  if #queue == 0 and next(pending) == nil then finish() return end
  C_Timer.After(PAUSE, function() BJ.Protected("lurescan", portion) end)
end

-- Phase 1: all consumable item IDs
local function collect()
  if not running then return end
  local last = math.min(nextID + STEP - 1, MAX_ID)
  for id = nextID, last do
    local classID = select(6, getInfo(id))
    if classID == CONSUMABLE then queue[#queue + 1] = id end
  end
  nextID = last + 1
  if nextID > MAX_ID then
    total = #queue
    portion()
  else
    C_Timer.After(0.02, function() BJ.Protected("lurescan", collect) end)
  end
end

function M.Start()
  if running or not (getInfo and C_Timer) then return end
  if not ns.Skill.Name() then BJ:Print(L["The fishing skill is needed for the scan."]) return end
  running, queue, pending, nextID, found, total = true, {}, {}, 1, 0, 0
  BJ:Print(L["Lure scan started. It runs in small steps in the background."])
  collect()
end

function M:OnEnable()
  BJ:RegisterEvent("GET_ITEM_INFO_RECEIVED", "lurescan", function(_, id)
    if running and pending and pending[id] then BJ.Protected("lurescan", check, id) end
  end)
  -- once on its own, a while after login (the game is busy loading right then)
  if C_Timer then
    C_Timer.After(30, function()
      if BJ.DB.raw and not BJ.DB.raw.lureScanDone then BJ.Protected("lurescan", M.Start) end
    end)
  end
end
