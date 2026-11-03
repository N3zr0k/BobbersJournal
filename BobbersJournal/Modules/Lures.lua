local _, ns = ...
local BJ, Gear = ns.BJ, ns.Gear
-- Which item is behind a lure on the pole: the weapon enchant only gives an enchant ID, so the lure item that was used
-- just before is remembered per enchant ID (DB.lureItems). Used for names and icons in the journal and the tooltip.
local M = BJ:RegisterModule("Lures")

local WINDOW = 10 -- seconds between using the lure and the enchant showing up
local last -- { id, t }

--- Called when a lure is used (by the auto lure, or seen in the use hook).
function M.Note(itemID)
  last = {id = itemID, t = GetTime and GetTime() or 0}
  ns.Lures.RescanOnce()
end

local function items()
  if not BJ.DB.raw then return nil end
  BJ.DB.raw.lureItems = BJ.DB.raw.lureItems or {}
  return BJ.DB.raw.lureItems
end

local prevEnchant, prevMs

--- Counts how often a lure was put on the pole: a new enchant ID, or the remaining time jumping up (re-applied).
local function countApplied(enchantID, ms)
  if not (enchantID and enchantID > 0 and BJ.DB.raw) then prevEnchant, prevMs = nil, nil return end
  if enchantID ~= prevEnchant or (ms and prevMs and ms > prevMs + 5000) then
    local lz = BJ.DB.raw.lures[enchantID]
    if not lz then lz = {cast = 0, catch = 0} BJ.DB.raw.lures[enchantID] = lz end
    lz.applied = (lz.applied or 0) + 1
  end
  prevEnchant, prevMs = enchantID, ms
end

local function check()
  local has, enchantID, ms = Gear.GetMainHandEnchant()
  enchantID = tonumber(BJ.Clean(enchantID))
  countApplied(has and enchantID or nil, tonumber(BJ.Clean(ms)))
  if not (has and enchantID and enchantID > 0 and last) then return end
  if (GetTime and GetTime() or 0) - last.t > WINDOW then return end
  local t = items()
  if t and not t[enchantID] then t[enchantID] = last.id BJ:Debug("lure item " .. last.id .. " = enchant " .. enchantID) end
end

--- Item ID of the lure on the pole (when known), enchant ID, remaining seconds.
function M.Current()
  local has, enchantID, ms = Gear.GetMainHandEnchant()
  if not has then return nil end
  enchantID = tonumber(BJ.Clean(enchantID))
  ms = tonumber(BJ.Clean(ms))
  local t = items()
  return t and enchantID and t[enchantID], enchantID, ms and ms / 1000
end

function M:OnEnable()
  -- Lure inventory: filled once a few seconds after login/reload (the client is busy loading right then)
  if C_Timer and C_Timer.After then
    C_Timer.After(6, function() BJ.Protected("lure prefill", ns.Lures.Prefill) end)
  end
  BJ:RegisterEvent("UNIT_INVENTORY_CHANGED", "lures", function(_, unit) if unit == "player" then BJ.Protected("lures", check) end end)
  -- Lures used by hand: the use hook (insecure post-hook, never alters the call)
  local function onUse(container, slot)
    local get = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
    local ok, id = pcall(get, container, slot)
    id = ok and BJ.Clean(id) or nil
    if type(id) == "number" and ns.Lures.Bonus(id, container, slot) then M.Note(id) end
  end
  if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", onUse)
  elseif UseContainerItem then hooksecurefunc("UseContainerItem", onUse) end
end
