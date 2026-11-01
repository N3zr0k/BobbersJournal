local _, ns = ...
local BJ, Gear, Skill = ns.BJ, ns.Gear, ns.Skill
local L = BJ.L
-- Cast the fishing pole by modifier + double click (port of Glimpse FishingCast; Forever-tested there).
--   * no pole: remember weapons, put them away, equip pole. The next double click casts.
--   * pole in hand: cast "Fishing".
-- Only while standing. After RADIUS metres of movement the weapons come back (after combat if needed).
-- Not enough bag space for the weapons: message, no swap. Off by default (intervenes in game control).
-- Auto lure (Glimpse FishingLure) is not ported yet.
local M = BJ:RegisterModule("Cast")

local KEY = "fishing"
local MAIN, OFF = Gear.MAIN_HAND, Gear.OFF_HAND
local RADIUS, TICK = 5, 0.2 -- metres, seconds per movement check
local EXTERNAL = {"FishingBuddy", "BetterFishing"} -- if loaded they cast and swap themselves

local bag = C_Container or {}
local api = {
  InCombatLockdown = InCombatLockdown,
  GetInventoryItemLink = GetInventoryItemLink,
  EquipItemByName = (C_Item and C_Item.EquipItemByName) or EquipItemByName,
  NumBags = NUM_BAG_SLOTS or 4,
  GetContainerNumSlots = bag.GetContainerNumSlots or GetContainerNumSlots,
  GetContainerItemID = bag.GetContainerItemID or GetContainerItemID,
  GetContainerNumFreeSlots = bag.GetContainerNumFreeSlots or GetContainerNumFreeSlots,
  GetUnitSpeed = GetUnitSpeed,
  NewTicker = C_Timer and C_Timer.NewTicker,
  IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded,
  Alert = function(text)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(text, 1, 0.2, 0.2, 1) end
    BJ:Print(text)
  end,
  Notice = function(text)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(text, 0.1, 1, 0.1, 1) end
  end,
}
M.api = api

local function opt(name)
  local s = BJ.settings and BJ.settings.cast
  return s and s[name]
end

function M.Modifier() local v = opt("modifier") return BJ.DoubleClick.MODIFIERS[v] and v or "SHIFT" end
function M.Button() return opt("button") or "RightButton" end

--- Name of a loaded addon that does the same, else nil. Checked on every use: load order is arbitrary.
function M.BlockedBy()
  if not api.IsAddOnLoaded then return nil end
  for _, name in ipairs(EXTERNAL) do
    local ok, loaded = pcall(api.IsAddOnLoaded, name)
    if ok and (loaded == true or loaded == 1) then return name end
  end
end

function M.Enabled() return opt("enabled") == true and not M.BlockedBy() end

local function findPole()
  if not (api.GetContainerNumSlots and api.GetContainerItemID) then return nil end
  for c = 0, api.NumBags do
    for slot = 1, tonumber(api.GetContainerNumSlots(c)) or 0 do
      local id = api.GetContainerItemID(c, slot)
      if id and Gear.IsPoleItem(id) then return c, slot, id end
    end
  end
end

--- Special bags do not count
local function freeSlots()
  if not api.GetContainerNumFreeSlots then return 0 end
  local free = 0
  for c = 0, api.NumBags do
    local count, family = api.GetContainerNumFreeSlots(c)
    if (family or 0) == 0 then free = free + (tonumber(count) or 0) end
  end
  return free
end

-- Off hand always needs a slot, main hand only if the pole does not come from the bags (it does here).
local function slotsNeeded()
  return api.GetInventoryItemLink("player", OFF) and 1 or 0
end

-- Remembered weapons live in the DB (per character) so they survive /reload.
local function saved() return BJ.DB.raw and BJ.DB:Char().savedWeapons end

local moved, ticker = 0, nil
local function stopWatching() if ticker then ticker:Cancel() ticker = nil end end

function M.RestoreWeapons()
  local s = saved()
  if not s then stopWatching() return end
  if api.InCombatLockdown() then M.restorePending = true return end
  M.restorePending = nil
  -- Main hand first, otherwise a two-hander takes the off hand away again
  for _, slot in ipairs({MAIN, OFF}) do
    if s[slot] then api.EquipItemByName(s[slot], slot) end
  end
  BJ.DB:Char().savedWeapons = nil
  moved = 0
  stopWatching()
end

local function watch()
  if ticker or not api.NewTicker then return end
  ticker = api.NewTicker(TICK, function()
    if not saved() then stopWatching() return end
    local speed = tonumber(BJ.Clean(api.GetUnitSpeed and (api.GetUnitSpeed("player")))) or 0
    moved = moved + (speed > 0 and speed * TICK or 0)
    if moved > RADIUS then M.RestoreWeapons() end
  end)
end

--- true if the pole is already in hand
function M.PreparePole()
  if Gear.IsPoleEquipped() then moved = 0 return true end
  if api.InCombatLockdown() then api.Alert(L["You cannot change your weapons in combat."]) return false end

  local container, _, poleID = findPole()
  if not container then api.Alert(L["No fishing pole found in your bags."]) return false end
  local needed, free = slotsNeeded(), freeSlots()
  if free < needed then
    api.Alert(format(L["Not enough bag space to put away your weapons. Additional space needed: %d."], needed - free))
    return false
  end
  -- Never overwrite what is remembered: those are the original weapons
  local char = BJ.DB:Char()
  if not char.savedWeapons then
    char.savedWeapons = {[MAIN] = api.GetInventoryItemLink("player", MAIN), [OFF] = api.GetInventoryItemLink("player", OFF)}
  end
  moved = 0
  api.EquipItemByName(poleID)
  watch()
  api.Notice(L["Fishing rod equipped. Double right click again to cast."])
  return false
end

--- Weapon swap only on Forever (Retail does not need a pole in hand) and only if the option is on.
function M.SwapWanted()
  return ns.Flavor.current == ns.Flavor.FOREVER and opt("weaponSwap") ~= false
end

local function prepare()
  local name = Skill.SpellName(Skill.REFERENCE)
  local ready = true
  if M.SwapWanted() then ready = M.PreparePole() end
  if ready and name then return {type = "spell", spell = name} end
end

function M:OnEnable()
  BJ.DoubleClick.Register(KEY, {
    modifier = M.Modifier, button = M.Button, priority = 10, when = {standing = true},
    Match = M.Enabled, Prepare = prepare,
  })
  BJ:RegisterEvent("PLAYER_REGEN_ENABLED", "cast", function() if M.restorePending then M.RestoreWeapons() end end)
  -- Attacked: equipment is locked in combat, so the weapons come back the moment combat ends.
  BJ:RegisterEvent("PLAYER_REGEN_DISABLED", "cast", function() if saved() then M.restorePending = true end end)
  M.CreateKeyButton()
  if saved() then watch() end -- after login/reload, keep watching while weapons are still remembered
end

--- Tooltip text: "Shift + Double right click to cast the fishing rod"
function M.ShortcutText()
  local text = BJ.DoubleClick:Text(KEY)
  local key = M.BoundKey()
  if key then text = text .. " / " .. key end
  return format(L["%s to cast the fishing rod"], text)
end


-- Key binding: Bindings.xml maps a key to CLICK BobbersJournalCastButton:LeftButton. The button works like the
-- double-click handler: PreClick (out of combat) decides what the secure button does.
local keyButton
function M.CreateKeyButton()
  if keyButton then return end
  keyButton = CreateFrame("Button", "BobbersJournalCastButton", UIParent, "SecureActionButtonTemplate")
  keyButton:RegisterForClicks("AnyDown", "AnyUp")
  local prepared
  keyButton:SetScript("PreClick", function(self)
    if api.InCombatLockdown() or not M.Enabled() then
      for _, a in ipairs({"type", "spell", "macrotext"}) do self:SetAttribute(a, nil) end
      return
    end
    -- Down and up both arrive; decide only once per press
    if not prepared then
      prepared = prepare() or false
      self:SetAttribute("type", prepared and prepared.type or nil)
      self:SetAttribute("spell", prepared and prepared.spell or nil)
    end
  end)
  keyButton:SetScript("PostClick", function(_, _, down) if not down then prepared = nil end end)
end

--- Text of the key the user bound to the cast button, or nil.
function M.BoundKey()
  local key = GetBindingKey and GetBindingKey("CLICK BobbersJournalCastButton:LeftButton")
  return key and (GetBindingText and GetBindingText(key) or key) or nil
end

-- Names in the Key Bindings window
BINDING_HEADER_BOBBERSJOURNAL = L["ADDON_NAME"]
_G["BINDING_NAME_CLICK BobbersJournalCastButton:LeftButton"] = L["Cast the fishing rod"]
