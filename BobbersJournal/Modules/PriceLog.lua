local _, ns = ...
local BJ = ns.BJ
-- Notes the auction house prices of the fish for the price history in the journal (see PriceHistory.lua). Samples are taken
-- a little after login, when the auction house is closed (the price addon has just scanned) and when a fish is looked at.
-- Nothing happens without a price addon. No OnUpdate: events and one timer.
local M = BJ:RegisterModule("PriceLog")

local function sample()
  if not ns.Prices.HasAuctionAddon() then return end
  BJ.Protected("price log", ns.PriceHistory.RecordAll)
end

function M:OnEnable()
  BJ:RegisterEvent("PLAYER_ENTERING_WORLD", "pricelog.login", function()
    if C_Timer and C_Timer.After then C_Timer.After(20, sample) end
  end)
  BJ:RegisterEvent("AUCTION_HOUSE_CLOSED", "pricelog.ah", function()
    if C_Timer and C_Timer.After then C_Timer.After(2, function()
      if ns.Prices.HasAuctionAddon() then
        -- after a visit the price may be fresher than the 10 minute rule allows
        for _, f in ipairs(BJ.API.GetFishList()) do ns.PriceHistory.Record(f.itemID) end
      end
    end) end
  end)
end
