local _, ns = ...
-- Fishing pole and lure (temporary weapon enchant) detection. Port of Glimpse FishingGear.
local Gear = {MAIN_HAND = 16, OFF_HAND = 17, FISHING_TOOL = 28}
ns.Gear = Gear

local WEAPON = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
local FISHING_POLE = Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20
-- Retail: the fishing pole is a profession tool (item class Profession, subclass Fishing, equip slot profession tool)
local PROFESSION = Enum and Enum.ItemClass and Enum.ItemClass.Profession or 19
local PROF_FISHING = Enum and Enum.ItemProfessionSubclass and Enum.ItemProfessionSubclass.Fishing or 9
local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

function Gear.IsPoleItem(itemID)
  if not (itemID and getInfo) then return false end
  local _, _, _, equipLoc, _, classID, subClassID = getInfo(itemID)
  if classID == PROFESSION and subClassID == PROF_FISHING then return equipLoc == "INVTYPE_PROFESSION_TOOL" end
  return classID == WEAPON and subClassID == FISHING_POLE
end

local function poleIn(slot)
  if not GetInventoryItemID then return false end
  local ok, id = pcall(GetInventoryItemID, "player", slot)
  return ok and id and Gear.IsPoleItem(id) or false
end

--- Inventory slot that holds the pole: the main hand, on Retail also the fishing tool slot (profession gear). nil if none.
function Gear.PoleSlot()
  if poleIn(Gear.MAIN_HAND) then return Gear.MAIN_HAND end
  if poleIn(Gear.FISHING_TOOL) then return Gear.FISHING_TOOL end
end

function Gear.IsPoleEquipped()
  return Gear.PoleSlot() ~= nil
end

--- Lure on the pole: active, enchantID, remaining ms.
-- Retail 12.1 deprecates GetWeaponEnchantInfo in favour of C_PaperDollInfo.GetTemporaryEnchantmentInfo.
function Gear.GetMainHandEnchant()
  if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
    local ok, info = pcall(C_PaperDollInfo.GetTemporaryEnchantmentInfo, Gear.PoleSlot() or Gear.MAIN_HAND)
    if not ok or type(info) ~= "table" then return false end
    return true, info.enchantID, info.remainingTimeMs
  end
  if not GetWeaponEnchantInfo then return false end
  local ok, has, expiration, _, enchantID = pcall(GetWeaponEnchantInfo)
  if not ok then return false end
  return has == true or has == 1, enchantID, expiration
end
