local _, ns = ...
local BJ = ns.BJ
local L = BJ.L
-- Optional: keeps the minimap tracking "Find Fish" switched on. Checked at login / zone change and when a cast starts,
-- never on tracking changes, so a player who switches it off later is not fought within the session.
-- Retail: C_Minimap.GetTrackingInfo returns a table; Forever: GetTrackingInfo returns name, texture, active.
local M = BJ:RegisterModule("FindFish")

local FIND_FISH = 43308

local function spellName()
  return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(FIND_FISH) or (GetSpellInfo and GetSpellInfo(FIND_FISH))
end

local function info(i)
  if C_Minimap and C_Minimap.GetTrackingInfo then
    local t = C_Minimap.GetTrackingInfo(i)
    if type(t) == "table" then return t.name, t.active, t.spellID end
    return
  end
  local name, _, active = GetTrackingInfo(i)
  return name, active
end

-- Retail's tracking menu keeps its own copy of the state; it re-reads it on SPELLS_CHANGED / tracking CVAR updates, and
-- tracking that works through a spell (Find Fish) does not always trigger those. Once the change is through, the menu
-- button gets the same event so the check mark is right. Only a state read; no tracking is changed here.
function M.SyncMenu(index)
  if not C_Timer then return end
  C_Timer.After(0.7, function()
    BJ.Protected("findfish sync", function()
      local _, active = info(index)
      BJ:Debug("Find Fish active after switching: " .. tostring(active))
      local button = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
      local onEvent = button and button.GetScript and button:GetScript("OnEvent")
      if onEvent and not (button.IsMenuOpen and button:IsMenuOpen()) then onEvent(button, "SPELLS_CHANGED") end
    end)
  end)
end

--- Switches Find Fish on when the option is set, the character knows it and it is off.
function M.Check()
  if not (BJ.settings and BJ.settings.findFish) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local count = (C_Minimap and C_Minimap.GetNumTrackingTypes or GetNumTrackingTypes or function() return 0 end)()
  local name = spellName()
  for i = 1, count do
    local n, active, id = info(i)
    if id == FIND_FISH or (name and n == name) then
      if not active then
        local set = C_Minimap and C_Minimap.SetTracking or SetTracking
        if set then
          set(i, true)
          BJ:Debug("Find Fish enabled")
          M.SyncMenu(i)
        end
      end
      return
    end
  end
end

function M:OnEnable()
  BJ:RegisterEvent("PLAYER_ENTERING_WORLD", "findfish", function()
    if C_Timer then C_Timer.After(3, function() BJ.Protected("findfish", M.Check) end) end
  end)
  BJ:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "findfish", function(_, unit)
    if unit == "player" then BJ.Protected("findfish", M.Check) end
  end)
end
