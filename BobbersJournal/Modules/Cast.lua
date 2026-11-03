local _, ns = ...
local BJ, Gear, Skill = ns.BJ, ns.Gear, ns.Skill
local L = BJ.L
-- Cast the fishing pole by modifier + double click (port of Glimpse FishingCast; Forever-tested there).
--   * no pole: remember weapons, put them away, equip pole. The next double click casts.
--   * pole in hand: cast "Fishing".
-- Only while standing. After RADIUS metres of movement the weapons come back (after combat if needed).
-- Not enough bag space for the weapons: message, no swap. Off by default (intervenes in game control).
-- Auto lure (Glimpse FishingLure): option cast.autoLure, see lureMacro.
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

-- Auto lure: the pole is in hand and has no lure -> this click applies the best lure from the bags (macro: use the
-- item, then the main hand), the next click casts. Using items is protected, so it has to be a secure macro.
local function lureMacro()
  if opt("autoLure") ~= true or api.InCombatLockdown() then return nil end
  ns.Lures.RescanOnce() -- the first cast of the session reads the bags again
  local retail = ns.Flavor.current == ns.Flavor.RETAIL
  -- Forever: the lure is an enchant on the pole in the main hand. Retail: the lure is a buff on the player (the pole
  -- sits in the profession slot, not in the main hand), so there it is "buff not active yet".
  local poleSlot = Gear.PoleSlot()
  -- Retail with the pole in a gear slot (main hand or fishing tool slot): the lure is applied to the pole like in Forever.
  local onPole = poleSlot ~= nil
  if onPole and Gear.GetMainHandEnchant() then BJ:Debug("autolure: enchant present") return nil end
  if not retail and not onPole then BJ:Debug("autolure: no pole") return nil end
  -- The favourite from the bags first; without one (not set or not in the bags) the best lure, if that is wanted.
  local best = opt("favoriteLure") and ns.Lures and ns.Lures.FindItem(opt("favoriteLure"))
  if best and best.usable == false then BJ:Debug("autolure: favourite " .. best.id .. " needs more fishing skill") best = nil end
  if not best and opt("autoBest") ~= false then best = ns.Lures and ns.Lures.FindBest() end
  if not best then BJ:Debug("autolure: no lure in the bags") return nil end
  if retail and not onPole then
    local spellID = C_Item and C_Item.GetItemSpell and select(2, C_Item.GetItemSpell(best.id))
    if spellID and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
      BJ:Debug("autolure: effect of lure " .. best.id .. " is active") return nil
    end
    api.Notice(format(L["Apply %s."], best.link))
    return format("/use %d %d", best.container, best.slot)
  end
  if BJ.modules.Lures then BJ.modules.Lures.Note(best.id) end
  local pole = api.GetInventoryItemLink("player", poleSlot) or ""
  api.Notice(format(L["Apply %s to %s."], best.link, pole))
  if best.bonus then api.Notice(format(L["Your fishing skill increases by %d."], best.bonus)) end
  return format("/use %d %d\n/use %d", best.container, best.slot, poleSlot)
end

-- The oversized bobber is used first when its effect is not active: as the toy "Reusable Oversized Bobber" (Retail,
-- when collected and usable), otherwise as the item in the bags (Retail and Forever).
local TOY_ID, TOY_PAUSE = 202207, 60
local toyUsedAt = 0

local function getCooldown(id)
  local f = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
  if not f then return nil end
  local ok, start, duration = pcall(f, id)
  if not ok then return nil end
  return tonumber(BJ.Clean(start)), tonumber(BJ.Clean(duration))
end

local function itemCount()
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not f then return 0 end
  local ok, n = pcall(f, TOY_ID)
  return ok and tonumber(n) or 0
end

--- "toy" when the toy is collected and usable (Retail), "item" when the item is in the bags, else nil.
local function bobberSource()
  if ns.Flavor.current == ns.Flavor.RETAIL and PlayerHasToy and PlayerHasToy(TOY_ID)
    and not (C_ToyBox and C_ToyBox.IsToyUsable and not C_ToyBox.IsToyUsable(TOY_ID)) then
    return "toy"
  end
  if itemCount() > 0 then return "item" end
  return nil
end

-- Player buffs as { name, icon, spellId, expirationTime } for the client's aura API (Retail) or UnitBuff (Forever)
local function buffAt(i)
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
    return a and {name = BJ.Clean(a.name), icon = BJ.Clean(a.icon), spellId = BJ.Clean(a.spellId), expirationTime = a.expirationTime}
  end
  if UnitBuff then
    local name, icon, _, _, _, expires, _, _, _, spellId = UnitBuff("player", i)
    return name and {name = BJ.Clean(name), icon = BJ.Clean(icon), spellId = BJ.Clean(spellId), expirationTime = expires}
  end
end

--- State of the oversized bobber: nil when neither toy nor item is there. {active, left = seconds of the buff, cooldown = seconds left}
-- The buff is not necessarily the item's use spell, so look it up by spell ID, then by name/icon
local function findToyAura()
  local spellID = C_Item and C_Item.GetItemSpell and select(2, C_Item.GetItemSpell(TOY_ID))
  if not spellID and GetItemSpell then spellID = select(2, GetItemSpell(TOY_ID)) end
  local names = {}
  local spellName = spellID and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID)))
  if type(spellName) == "string" then names[spellName] = true end
  local itemName = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(TOY_ID)
  if type(itemName) == "string" then names[itemName] = true end
  local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(TOY_ID)
  for i = 1, 60 do
    local aura = buffAt(i)
    if not aura then break end
    if (spellID and aura.spellId == spellID) or (type(aura.name) == "string" and names[aura.name]) or (icon and aura.icon == icon) then return aura end
  end
  return nil
end

function M.ToyStatus()
  if opt("bobberToy") ~= true then return nil end -- option off: not shown in the tooltips
  if not bobberSource() then return nil end
  local now = GetTime and GetTime() or 0
  local st = {active = false}
  local aura = findToyAura()
  if aura then
    st.active = true
    local expires = tonumber(BJ.Clean(aura.expirationTime))
    if expires and expires > 0 then st.left = math.max(expires - now, 0) end
  end
  local start, duration = getCooldown(TOY_ID)
  if start and duration and start > 0 and duration > 1.5 and start + duration > now then st.cooldown = start + duration - now end
  return st
end

--- Name of the toy for /usetoy. The item name is only there once the client has loaded the item, so it is requested at
--- login (RequestToyData) and the toy box is asked as well; without a name the first double click could not use the toy.
local function toyName()
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(TOY_ID)
  if type(name) == "string" and name ~= "" then return name end
  if C_ToyBox and C_ToyBox.GetToyInfo then
    local ok, _, toy = pcall(C_ToyBox.GetToyInfo, TOY_ID)
    if ok and type(toy) == "string" and toy ~= "" then return toy end
  end
  if GetItemInfo then
    local info = GetItemInfo(TOY_ID)
    if type(info) == "string" and info ~= "" then return info end
  end
  return nil
end

local function requestToyData()
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, TOY_ID) end
  if C_ToyBox and C_ToyBox.GetToyInfo then pcall(C_ToyBox.GetToyInfo, TOY_ID) end
end

local function toyMacro()
  if opt("bobberToy") ~= true then BJ:Debug("toy: option is off") return nil end
  if api.InCombatLockdown() then BJ:Debug("toy: in combat") return nil end
  local source = bobberSource()
  if not source then BJ:Debug("toy: neither the toy " .. TOY_ID .. " nor the item in the bags") return nil end
  local now = GetTime and GetTime() or 0
  if now - toyUsedAt < TOY_PAUSE then BJ:Debug("toy: used less than " .. TOY_PAUSE .. " s ago") return nil end
  local start, duration = getCooldown(TOY_ID)
  if start and duration and start > 0 and duration > 0 and start + duration > now then BJ:Debug("toy: on cooldown") return nil end
  -- effect active already?
  if findToyAura() then BJ:Debug("toy: effect is active") return nil end
  toyUsedAt = now
  -- /usetoy wants the toy NAME (UseToyByName), not the ID; the item from the bags is used with /use item:<id>
  local name = toyName()
  if source == "toy" and not name then
    requestToyData()
    BJ:Debug("toy: name not loaded yet, requested")
    toyUsedAt = 0
    return nil -- the next click has it
  end
  local macro = (source == "toy" and type(name) == "string" and name ~= "") and ("/usetoy " .. name) or ("/use item:" .. TOY_ID)
  BJ:Debug("bobber (" .. source .. "): " .. macro)
  return macro
end

local function prepare()
  local name = Skill.SpellName(Skill.REFERENCE)
  local ready = true
  if M.SwapWanted() then ready = M.PreparePole() end
  if not ready then return nil end
  local macro = toyMacro() or lureMacro()
  if macro then return {type = "macro", macrotext = macro} end
  if name then return {type = "spell", spell = name} end
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
  requestToyData()
  BJ:RegisterEvent("PLAYER_ENTERING_WORLD", "cast.toy", requestToyData)
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
      self:SetAttribute("macrotext", prepared and prepared.macrotext or nil)
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
