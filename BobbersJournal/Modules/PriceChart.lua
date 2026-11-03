local _, ns = ...
local BJ = ns.BJ
local L = BJ.L
-- Price chart of the journal (fish sales page): the daily range (lowest to highest sample) as thin bars, the last price of
-- each day as a line, the average as a dashed hairline; figures below. Data: ns.PriceHistory. Painted with textures and
-- lines, no OnUpdate. Not tested in the game.
local M = BJ:RegisterModule("PriceChart")

local W, H, STATS_H = 400, 120, 44
local INK = {0.22, 0.14, 0.06}
local LINE = {0.05, 0.40, 0.40}
local BAR = {0.55, 0.36, 0.14}

--- Creates the chart frame on `parent` (anchor it yourself). Size W x (H + STATS_H).
function M.Create(parent)
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(W, H + STATS_H + 18)
  c.title = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  c.title:SetPoint("TOPLEFT")
  c.title:SetTextColor(INK[1], INK[2], INK[3])
  c.title:SetShadowOffset(0, 0)
  c.title:SetText(L["Price history (1 year)"])
  c.plot = CreateFrame("Frame", nil, c)
  c.plot:SetPoint("TOPLEFT", 0, -18)
  c.plot:SetSize(W, H)
  c.bg = c.plot:CreateTexture(nil, "BACKGROUND")
  c.bg:SetAllPoints()
  c.bg:SetColorTexture(0.35, 0.22, 0.08, 0.10)
  local function label(point, rel, relPoint, x, y)
    local f = c.plot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f:SetPoint(point, rel, relPoint, x, y)
    f:SetShadowOffset(0, 0)
    f:SetTextColor(INK[1], INK[2], INK[3], 0.8)
    return f
  end
  c.hiText = label("TOPLEFT", c.plot, "TOPLEFT", 3, -2)
  c.loText = label("BOTTOMLEFT", c.plot, "BOTTOMLEFT", 3, 2)
  c.fromText = label("TOPLEFT", c.plot, "BOTTOMLEFT", 0, -2)
  c.toText = label("TOPRIGHT", c.plot, "BOTTOMRIGHT", 0, -2)
  c.empty = c.plot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c.empty:SetPoint("CENTER")
  c.empty:SetWidth(W - 40)
  c.empty:SetShadowOffset(0, 0)
  c.empty:SetTextColor(INK[1], INK[2], INK[3], 0.8)
  c.empty:SetText(L["No price history yet. Prices are noted at login and after a visit to the auction house."])
  c.stats = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  c.stats:SetPoint("TOPLEFT", c.plot, "BOTTOMLEFT", 0, -16)
  c.stats:SetWidth(W)
  c.stats:SetJustifyH("LEFT")
  c.stats:SetSpacing(3)
  c.stats:SetShadowOffset(0, 0)
  c.stats:SetTextColor(INK[1], INK[2], INK[3])
  c.bars, c.lines = {}, {}
  c.avg = c.plot:CreateTexture(nil, "ARTWORK")
  c.avg:SetColorTexture(INK[1], INK[2], INK[3], 0.45)
  c.avg:SetHeight(1)
  c:Hide()
  return c
end

local function bar(c, i)
  local t = c.bars[i]
  if not t then
    t = c.plot:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(BAR[1], BAR[2], BAR[3], 0.55)
    c.bars[i] = t
  end
  return t
end

local function segment(c, i)
  local l = c.lines[i]
  if not l and c.plot.CreateLine then
    l = c.plot:CreateLine(nil, "OVERLAY")
    l:SetThickness(2)
    l:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    c.lines[i] = l
  end
  return l
end

local function pct(f) return format("%+.0f %%", f * 100) end

--- Paints the chart for an item. Returns true when there was data.
function M.Draw(c, itemID)
  local PH, P = ns.PriceHistory, ns.Prices
  for _, t in ipairs(c.bars) do t:Hide() end
  for _, l in ipairs(c.lines) do l:Hide() end
  c.avg:Hide()
  local list = PH.Series(itemID, 365)
  local s = PH.Stats(itemID, list)
  if #list == 0 or not s then
    c.empty:Show()
    c.hiText:SetText("") c.loText:SetText("") c.fromText:SetText("") c.toText:SetText("")
    c.stats:SetText("")
    return false
  end
  c.empty:Hide()
  local first = list[1].day
  local span = math.max(list[#list].day - first, 30)
  local ymin, ymax = s.min, s.max
  local pad = math.max((ymax - ymin) * 0.08, ymax * 0.02, 1)
  ymin, ymax = math.max(ymin - pad, 0), ymax + pad
  local yr = ymax - ymin
  local function px(day) return (day - first) / span * (W - 6) + 3 end
  local function py(v) return (v - ymin) / yr * (H - 6) + 3 end
  local prevX, prevY
  for i, e in ipairs(list) do
    local x = px(e.day)
    local b = bar(c, i)
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", c.plot, "BOTTOMLEFT", x - 1, py(e.lo))
    b:SetSize(2, math.max(py(e.hi) - py(e.lo), 2))
    b:Show()
    local y = py(e.last)
    if prevX then
      local l = segment(c, i)
      if l then
        l:SetStartPoint("BOTTOMLEFT", c.plot, prevX, prevY)
        l:SetEndPoint("BOTTOMLEFT", c.plot, x, y)
        l:Show()
      end
    end
    prevX, prevY = x, y
  end
  c.avg:ClearAllPoints()
  c.avg:SetPoint("BOTTOMLEFT", c.plot, "BOTTOMLEFT", 3, py(s.avg))
  c.avg:SetWidth(W - 6)
  c.avg:Show()
  c.hiText:SetText(P.Money(s.max))
  c.loText:SetText(P.Money(s.min))
  c.fromText:SetText(date("%d.%m.%Y", PH.Time(first)))
  c.toText:SetText(date("%d.%m.%Y", PH.Time(list[#list].day)))
  local lines = {format("%s %s   %s %s   %s %s   %s %s", L["Min"], P.Money(s.min), L["Max"], P.Money(s.max), "\195\152", P.Money(s.avg), L["Now"], P.Money(s.last))}
  local second = {}
  if s.change30 then second[#second + 1] = format("%s %s", L["30 days"], pct(s.change30)) end
  if s.bestWday then
    local names = _G.CALENDAR_WEEKDAY_NAMES
    local best = names and names[s.bestWday] or tostring(s.bestWday)
    second[#second + 1] = format("%s: %s", L["Best day to sell"], best)
  end
  second[#second + 1] = format(L["%d days of data"], s.n)
  lines[2] = table.concat(second, "   ")
  c.stats:SetText(table.concat(lines, "\n"))
  return true
end

M.WIDTH, M.HEIGHT = W, H + STATS_H + 18
