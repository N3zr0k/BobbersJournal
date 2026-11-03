local _, ns = ...
-- How many of an item the player has: in the bags, in the bank (bank and reagent bank) and, on Retail, in the warband bank.
-- The client only knows the bank contents it saw at the last bank visit. Not tested in the game.
local Stock = {}
ns.Stock = Stock

local function count(id, bank, reagent, warband)
  local get = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not get then return nil end
  local ok, n = pcall(get, id, bank, false, reagent, warband)
  return ok and type(n) == "number" and n or nil
end

--- { bags, bank, warband, bankRead } or nil when the client cannot count items. bankRead is false until the bank was opened
--- in this login (the client does not know its contents before): the bank and warband numbers are not reliable then.
function Stock.Counts(itemID)
  local bags = count(itemID, false, false, false)
  if not bags then return nil end
  local withBank = count(itemID, true, true, false) or bags
  local withAll = count(itemID, true, true, true) or withBank
  local bank, warband = math.max(withBank - bags, 0), math.max(withAll - withBank, 0)
  local session = ns.BJ.DB.session
  return {bags = bags, bank = bank, warband = warband, bankRead = (session and session.bankRead == true) or bank > 0 or warband > 0}
end
