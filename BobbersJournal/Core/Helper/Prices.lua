local _, ns = ...
-- Prices of items for the income figures in the fish tooltip.
--   Vendor: the sell price the game knows for every item (copper).
--   Auction: asked from a price addon that is installed (Auctionator, TSM, Auctioneer); this addon does not scan the auction
--   house itself. Returns nil when no addon answers. Not tested in the game.
local Prices = {}
ns.Prices = Prices

--- Sell price to a vendor in copper, nil when unknown (item not loaded yet, or not sellable).
function Prices.Vendor(itemID)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getInfo then return nil end
  local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(getInfo, itemID)
  if ok and type(sell) == "number" and sell > 0 then return sell end
  return nil
end

local function itemLink(itemID)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local ok, _, link = pcall(getInfo, itemID)
  return ok and link or nil
end

-- One entry per supported addon: { name, function(itemID) -> copper or nil }
local SOURCES = {
  {"Auctionator", function(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    return api and api.GetAuctionPriceByItemID and api.GetAuctionPriceByItemID("BobbersJournal", id)
  end},
  {"TradeSkillMaster", function(id)
    return TSM_API and TSM_API.GetCustomPriceValue and TSM_API.GetCustomPriceValue("DBMarket", "i:" .. id)
  end},
  {"Auctioneer", function(id)
    local link = itemLink(id)
    return link and AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue and AucAdvanced.API.GetMarketValue(link)
  end},
}

--- Auction house price in copper and the name of the addon that gave it; nil when no price addon knows the item.
function Prices.Auction(itemID)
  for _, s in ipairs(SOURCES) do
    local ok, price = pcall(s[2], itemID)
    if ok and type(price) == "number" and price > 0 then return price, s[1] end
  end
  return nil
end

--- True when at least one supported price addon is loaded.
function Prices.HasAuctionAddon()
  return (Auctionator and Auctionator.API) ~= nil or TSM_API ~= nil or (AucAdvanced and AucAdvanced.API) ~= nil
end

--- Copper as coin text with the game's coin icons.
function Prices.Money(copper)
  copper = math.floor((copper or 0) + 0.5)
  local f = GetCoinTextureString or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
  if f then return f(copper) end
  return format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100)
end

-- ---- what vendors and teachers ask ------------------------------------------------------------------------------------

local function costName(kind, id)
  if kind == 2 then
    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
    return info and info.name or ("#" .. id)
  end
  return ns.BJ.DB:ItemName(id) or ("#" .. id)
end

--- Text for a saved vendor offer (see Vendors.lua): price, extra costs, stack size and how many are left.
--- Example: "2g 50s + 5 Mark of Honor (x5), 3 left". Empty when nothing is known.
function Prices.OfferText(o)
  if type(o) ~= "table" then return "" end
  local parts = {}
  if o.p then parts[#parts + 1] = Prices.Money(o.p) end
  for _, c in ipairs(o.cost or {}) do parts[#parts + 1] = format("%d %s", c[3] or 0, costName(c[1], c[2])) end
  local text = table.concat(parts, " + ")
  if o.q then text = text .. format(" (x%d)", o.q) end
  if o.lim then text = text .. ", " .. format(ns.BJ.L["%d left"], o.lim) end
  return text
end

--- Text for a saved teacher service: "Journeyman Fishing, skill 50, level 10, 1s".
function Prices.LessonText(l)
  if type(l) ~= "table" then return "" end
  local parts = {l.n or "?"}
  if l.r then parts[1] = parts[1] .. " (" .. l.r .. ")" end
  if l.k then parts[#parts + 1] = format(ns.BJ.L["skill %d"], l.k) end
  if l.l then parts[#parts + 1] = format(ns.BJ.L["level %d"], l.l) end
  if l.c then parts[#parts + 1] = Prices.Money(l.c) end
  return table.concat(parts, ", ")
end

--- The lines of a saved offer that say what the character lacks. "Already known" is red in the game's tooltip too, but is no
--- shortcoming, so it is left out (also of entries saved by earlier versions). Empty list = nothing missing.
function Prices.Needs(o)
  local out = {}
  local known = _G.ITEM_SPELL_KNOWN
  for _, line in ipairs(type(o) == "table" and o.need or {}) do
    if not (type(known) == "string" and type(line) == "string" and line:find(known, 1, true)) then out[#out + 1] = line end
  end
  return out
end

--- When the auction price was last scanned: server time stamp and true when the price addon says so itself (Auctionator
--- tells the age of its price); otherwise the day this price first showed up here (it can be later than the real scan). nil
--- when unknown. Not tested in the game.
function Prices.AuctionStamp(itemID)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if api and api.GetAuctionAgeByItemID then
    local ok, age = pcall(api.GetAuctionAgeByItemID, "BobbersJournal", itemID)
    if ok and type(age) == "number" and age >= 0 then
      local now = (GetServerTime and GetServerTime()) or time()
      return now - age * 86400, true
    end
  end
  local PH = ns.PriceHistory
  local day = PH and PH.LastChange(itemID)
  if day then return PH.Time(day), false end
  return nil
end
