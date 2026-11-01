local _, ns = ...
-- Fishing pole and lure (temporary weapon enchant) detection. Port of Glimpse FishingGear.
local Gear = {MAIN_HAND = 16, OFF_HAND = 17}
ns.Gear = Gear

local WEAPON = Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2
local FISHING_POLE = Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20
local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

function Gear.IsPoleItem(itemID)
  if not (itemID and getInfo) then return false end
  local _, _, _, _, _, classID, subClassID = getInfo(itemID)
  return classID == WEAPON and subClassID == FISHING_POLE
end

function Gear.IsPoleEquipped()
  if not GetInventoryItemID then return false end
  local ok, id = pcall(GetInventoryItemID, "player", Gear.MAIN_HAND)
  return ok and id and Gear.IsPoleItem(id) or false
end

--- Lure on the pole: active, enchantID, remaining ms.
-- Retail 12.1 deprecates GetWeaponEnchantInfo in favour of C_PaperDollInfo.GetTemporaryEnchantmentInfo.
function Gear.GetMainHandEnchant()
  if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
    local ok, info = pcall(C_PaperDollInfo.GetTemporaryEnchantmentInfo, Gear.MAIN_HAND)
    if not ok or type(info) ~= "table" then return false end
    return true, info.enchantID, info.remainingTimeMs
  end
  if not GetWeaponEnchantInfo then return false end
  local ok, has, expiration, _, enchantID = pcall(GetWeaponEnchantInfo)
  if not ok then return false end
  return has == true or has == 1, enchantID, expiration
end
