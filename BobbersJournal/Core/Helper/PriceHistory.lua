local _, ns = ...
-- Price history of fish from a price addon (Auctionator, TSM, Auctioneer): this addon does not scan the auction house, it
-- notes the price the addon reports. One entry per day: raw.prices[itemID][day] = { lowest, highest, last } in copper of
-- the samples of that day. day = days since 2020-01-01 (server time). Entries older than KEEP days are dropped.
-- Not tested in the game.
local PH = {}
ns.PriceHistory = PH

local EPOCH, DAY, KEEP = 1577836800, 86400, 400

function PH.Day(t)
  t = t or (GetServerTime and GetServerTime()) or time()
  return math.floor((t - EPOCH) / DAY)
end

--- Time stamp of the start of a day number.
function PH.Time(day) return EPOCH + day * DAY end

local function store()
  local raw = ns.BJ.DB.raw
  if not raw then return nil end
  raw.prices = raw.prices or {}
  return raw.prices
end

--- Notes the current auction house price of the item (when a price addon knows it). Returns true when a sample was saved.
function PH.Record(itemID)
  local s = store()
  local P = ns.Prices
  if not (s and P) then return false end
  local price = P.Auction(itemID)
  if type(price) ~= "number" or price <= 0 then return false end
  price = math.floor(price + 0.5)
  local day = PH.Day()
  -- the day this price first showed up (for price addons that do not tell their scan date)
  local seen = ns.BJ.DB.raw.priceSeen
  if seen and (not seen[itemID] or seen[itemID][1] ~= price) then seen[itemID] = {price, day} end
  local t = s[itemID] or {}
  s[itemID] = t
  local d = t[day]
  if d then
    d[1], d[2], d[3] = math.min(d[1], price), math.max(d[2], price), price
  else
    t[day] = {price, price, price}
  end
  for k in pairs(t) do if k < day - KEEP then t[k] = nil end end
  return true
end

--- Notes the price of every fish this character knows (at most once in 10 minutes).
local lastAll = 0
function PH.RecordAll()
  local now = GetTime and GetTime() or 0
  if lastAll > 0 and now - lastAll < 600 then return end
  lastAll = now
  for _, f in ipairs(ns.BJ.API.GetFishList()) do PH.Record(f.itemID) end
end

--- Days with data, oldest first: { {day, lo, hi, last}, ... } for the last `days` days.
function PH.Series(itemID, days)
  local s = store()
  local t = s and s[itemID]
  local out = {}
  if not t then return out end
  local from = PH.Day() - (days or 365) + 1
  for day, d in pairs(t) do
    if day >= from and type(d) == "table" then out[#out + 1] = {day = day, lo = d[1], hi = d[2], last = d[3]} end
  end
  table.sort(out, function(a, b) return a.day < b.day end)
  return out
end

--- Figures over the last year: { n, min, max, avg, last, change30, bestWday, worstWday } or nil without data.
--- `series` = the result of PH.Series for the same item, when the caller has it already (saves a second pass).
--- change30 = change of the last price against the last price known 30 or more days ago (fraction, nil when unknown).
--- Weekdays (1 = Sunday) are only named when every weekday has at least 3 samples.
function PH.Stats(itemID, series)
  local list = series or PH.Series(itemID, 365)
  if #list == 0 then return nil end
  local lo, hi, sum = math.huge, 0, 0
  local wd = {}
  for _, e in ipairs(list) do
    lo, hi, sum = math.min(lo, e.lo), math.max(hi, e.hi), sum + e.last
    local w = ((e.day + 3) % 7) + 1 -- 2020-01-01 was a Wednesday (4)
    wd[w] = wd[w] or {0, 0}
    wd[w][1], wd[w][2] = wd[w][1] + e.last, wd[w][2] + 1
  end
  local last = list[#list]
  local out = {n = #list, min = lo, max = hi, avg = sum / #list, last = last.last, lastDay = last.day, firstDay = list[1].day}
  for i = #list, 1, -1 do
    if list[i].day <= last.day - 30 then out.change30 = (last.last - list[i].last) / list[i].last break end
  end
  local best, worst, bestAvg, worstAvg
  local complete = true
  for w = 1, 7 do
    if not wd[w] or wd[w][2] < 3 then complete = false break end
    local a = wd[w][1] / wd[w][2]
    if not bestAvg or a > bestAvg then best, bestAvg = w, a end
    if not worstAvg or a < worstAvg then worst, worstAvg = w, a end
  end
  if complete then out.bestWday, out.bestAvg, out.worstWday = best, bestAvg, worst end
  return out
end

--- Day number on which the current auction price first showed up here, nil when never noted.
function PH.LastChange(itemID)
  local seen = ns.BJ.DB.raw and ns.BJ.DB.raw.priceSeen
  return seen and seen[itemID] and seen[itemID][2] or nil
end
