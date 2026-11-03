local _, ns = ...
local BJ, Skill = ns.BJ, ns.Skill
local L = BJ.L
-- Fishing spell tooltip (Forever and Retail): skill, cast shortcut, catches and counters of the current zone.
-- Lines are only appended in a post-call, the tooltip is never rebuilt from here (no RefreshData -> no taint).
-- Lure/buff split of the bonus from Glimpse is not ported yet.
local M = BJ:RegisterModule("Tooltip")

local C = ns.Colors
local WHITE, GREY = C.sandHex, C.parchmentHex
local MAX_FISH = 5
local AVG = "\195\152 " -- the average sign (U+00D8) and a space
local MIN_SESSION, MIN_TOTAL = 60, 300 -- seconds of fishing (session / all sessions) before a rate is shown
local MAX_ZONES, MAX_SPOTS = 4, 3

-- Switches that are off unless the player turned them on.
local function optIn(name)
  local t = BJ.settings and BJ.settings.tooltip
  return t and t[name] == true
end

local function opt(name)
  local t = BJ.settings and BJ.settings.tooltip
  return t and t[name] ~= false
end

local function itemLabel(id)
  local name = BJ.DB:ItemName(id)
  if not name then
    if Item and Item.CreateFromItemID then
      -- name arrives later: show the tooltip again so the label is replaced
      Item:CreateFromItemID(id):ContinueOnItemLoad(function()
        BJ.DB:ItemName(id)
        if GameTooltip:IsShown() and GameTooltip.RefreshData then GameTooltip:RefreshData() end
      end)
    elseif C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return "[" .. id .. "]"
  end
  local r, g, b = BJ.DB:ItemColor(id)
  return C.Wrap(r, g, b, name)
end

-- Bonus of the lure on the pole, read from the line of the weapon tooltip that names the fishing skill
-- ("... (+75 Fishing) ..."). 0 when there is none or the client does not offer the tooltip data.
local function lureBonus()
  if not (ns.Gear and ns.Gear.GetMainHandEnchant()) then return 0 end
  local stem = (Skill.Name() or ""):sub(1, 4):lower()
  if stem == "" or not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return 0 end
  local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", ns.Gear.PoleSlot() or ns.Gear.MAIN_HAND)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return 0 end
  for _, line in ipairs(data.lines) do
    local text = BJ.Clean(line.leftText)
    if type(text) == "string" and text:lower():find(stem, 1, true) then
      local n = tonumber(text:match("%+(%d+)"))
      if n then return n end
    end
  end
  return 0
end

local function hex(color)
  return C.Escape(color[1], color[2], color[3])
end

local BUFF_COLORS = {{0.90, 0.27, 0.27}, {0.95, 0.55, 0.20}, {0.70, 0.35, 0.85}, {0.30, 0.85, 0.45}}
local GEAR_COLOR = {0.26, 0.69, 1}

--- Segments of the skill bar: base skill, lure, equipment (what the total bonus has left after lure and buffs)
--- and one segment per known buff. The client only gives the total bonus; the split is an estimate.
-- Expansion level of a zone: the level of the fish caught there most often (shipped fish data), nil when unknown.
local function zoneLevel(zone)
  if not (zone and ns.Catalog) then return nil end
  local count, best, bestN = {}, nil, 0
  for _, f in ipairs(BJ.API.GetZoneFish(zone)) do
    local lv = ns.Catalog.fishExp[f.itemID]
    if lv then
      count[lv] = (count[lv] or 0) + f.drops
      if count[lv] > bestN then best, bestN = lv, count[lv] end
    end
  end
  return best
end

M.ZoneLevel = zoneLevel

local LURE_COLOR = {0.12, 1, 0} -- lures are green (as the green uncommon quality)

function M.BarData()
  local rank, max, mod = Skill.Info()
  if not rank then return nil end
  -- Retail: the skill line that can be levelled in this zone (expansion of the zone) instead of the general one
  local zoneLine
  if ns.Flavor.current == ns.Flavor.RETAIL then
    -- a line the player picked by hand (profession window) wins until the zone changes
    if Skill.manualLine then
      for _, e in ipairs(Skill.RetailLines() or {}) do if e.id == Skill.manualLine then zoneLine = e break end end
    end
    if not zoneLine then
      local lv = zoneLevel((ns.Zone.Key()))
      zoneLine = lv and Skill.RetailLineForLevel(lv)
    end
    if zoneLine then rank, max, mod = zoneLine.rank, zoneLine.max, zoneLine.modifier end
  end
  mod = mod or 0
  local segments = {{label = zoneLine and zoneLine.name or L["Fishing skill"], value = rank, color = C.aqua}}
  local lure = lureBonus()
  local buffs, known = {}, lure
  for _, b in pairs(BJ.modules.Buffs and BJ.modules.Buffs.active or {}) do
    if type(b.bonus) == "number" and b.bonus > 0 then buffs[#buffs + 1] = b known = known + b.bonus end
  end
  table.sort(buffs, function(x, y) return tostring(x.name) < tostring(y.name) end)
  -- Equipment = what the game's modifier has left after lure and buffs. When the modifier is smaller than the known bonuses
  -- the game does not count them in it (a buff of +30 beside a modifier of +5), so the modifier is the equipment alone.
  local gear = mod >= known and (mod - known) or mod
  if lure > 0 then
    -- Lure line: item name when known and the time left on the pole
    local label = L["Lure"]
    local tracker = BJ.modules.Lures
    if tracker then
      local item, _, left = tracker.Current()
      local name = item and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
      if name then label = name end
      if left and left > 0 then label = label .. format(" (%d:%02d)", math.floor(left / 60), math.floor(left % 60)) end
    end
    segments[#segments + 1] = {label = label, value = lure, color = LURE_COLOR, plus = true}
  end
  if gear > 0 then segments[#segments + 1] = {label = L["Equipment"], value = gear, color = GEAR_COLOR, plus = true} end
  for i, b in ipairs(buffs) do
    segments[#segments + 1] = {label = b.name, value = b.bonus, color = BUFF_COLORS[(i - 1) % #BUFF_COLORS + 1], plus = true}
  end
  local total = 0
  for _, seg in ipairs(segments) do total = total + seg.value end
  -- Text in the bar: level (rank/max) and what is levelled: Retail the expansion of the skill line, Forever the rank title
  local title
  if ns.Flavor.current == ns.Flavor.RETAIL then
    local pick = zoneLine
    if not pick then
      local lines = Skill.RetailLines() or {}
      for _, e in ipairs(lines) do
        if e.max == max and e.rank == rank then pick = e break end
      end
      pick = pick or lines[#lines]
    end
    title = pick and pick.expansion
  else
    title = Skill.Rank()
  end
  local barText = (title and title ~= "" and (title .. "  ") or "") .. rank .. "/" .. (max or "?")
  -- bonuses in the colour of their segment: " (+5 +3)", for the labels of the skill bar and the bobber display
  local bonus = {}
  for i = 2, #segments do bonus[#bonus + 1] = hex(segments[i].color) .. "+" .. segments[i].value .. "|r" end
  local bonusText = #bonus > 0 and (" (" .. table.concat(bonus, " ") .. ")") or ""
  return {segments = segments, total = total, max = max, text = barText, bonusText = bonusText, scale = math.max(max or total, total, 1),
    remaining = math.max((max or total) - total, 0)}
end

local measure
--- Width of a text in tooltip pixels (colour codes ignored); used to line up columns made of spaces.
function M.TextWidth(text)
  if not measure then
    measure = UIParent:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    measure:Hide()
  end
  measure:SetText((tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
  return math.max(measure:GetStringWidth() or 0, 1)
end

--- Width of one space: a lone space has no measurable width, so it is taken from the difference of two texts.
local spaceWidth
function M.SpaceWidth()
  if not spaceWidth then
    spaceWidth = math.max(M.TextWidth("a a") - M.TextWidth("aa"), 2)
  end
  return spaceWidth
end

--- Segments of a skill bar: one texture per part, 1 px gap between them. The gaps are taken from the width before the
--- values are scaled, so the whole bar still ends exactly at the scale; the white mark at the maximum respects the gaps before it.
function M.LayoutBar(bar, data, width, height)
  local n = 0
  for _, seg in ipairs(data.segments) do if seg.value > 0 then n = n + 1 end end
  local usable = width - 2 - math.max(n - 1, 0)
  local x, shown, gapsBeforeMax, sum = 1, 0, 0, 0
  for i, seg in ipairs(data.segments) do
    local tex = bar.segs[i]
    if not tex then tex = bar:CreateTexture(nil, "ARTWORK") bar.segs[i] = tex end
    if seg.value > 0 then
      if shown > 0 then x = x + 1 end -- the gap
      local w = math.floor(usable * seg.value / data.scale + 0.5)
      if w < 1 then w = 1 end
      tex:ClearAllPoints()
      tex:SetPoint("LEFT", bar, "LEFT", x, 0)
      tex:SetSize(w, height - 2)
      tex:SetColorTexture(seg.color[1], seg.color[2], seg.color[3], 1)
      tex:Show()
      x = x + w
      if shown > 0 and data.max and sum < data.max then gapsBeforeMax = gapsBeforeMax + 1 end
      shown = shown + 1
      sum = sum + seg.value
    else
      tex:Hide()
    end
  end
  for i = #data.segments + 1, #bar.segs do bar.segs[i]:Hide() end
  -- White mark at the maximum when bonuses push the total beyond it.
  if data.max and data.total > data.max then
    bar.mark:ClearAllPoints()
    bar.mark:SetPoint("CENTER", bar, "LEFT", 1 + usable * data.max / data.scale + gapsBeforeMax, 0)
    bar.mark:Show()
  else
    bar.mark:Hide()
  end
end

M.AVG = AVG

--- Fish per hour over all sessions of the current character (what it caught of the fish divided by its recorded fishing
--- time, both saved per character in the database); nil while there is too little fishing time. Used by the journal.
function M.TotalRate(itemID)
  local A = BJ.API
  local time = A.GetFishingTime()
  if time < MIN_TOTAL then return nil end
  return A.GetCaught(itemID) / (time / 3600)
end

--- Sections about a fish that look the same in the journal and in the diary: { { title, { "label: value", ... } }, ... }.
--- Stock (bags, bank, warband bank) and what the fish brings per hour over all sessions of this character: fish, vendor
--- value and, when a price addon knows it, auction house value.
function M.FishSections(itemID)
  local out = {}
  local stock = ns.Stock and ns.Stock.Counts(itemID)
  if stock then
    local lines = {format("%s: %d", L["In bags"], stock.bags)}
    if stock.bankRead then
      lines[#lines + 1] = format("%s: %d", L["In the bank"], stock.bank)
      if stock.warband > 0 then lines[#lines + 1] = format("%s: %d", L["In the warband bank"], stock.warband) end
    else
      lines[#lines + 1] = format("%s: %s", L["In the bank"], GREY .. L["not read yet, please visit the bank"] .. "|r")
    end
    out[#out + 1] = {L["In stock"], lines, key = "stock"}
    -- what the quantity owned is worth (bank and warband bank only when they were read)
    local owned = stock.bags + (stock.bankRead and (stock.bank + stock.warband) or 0)
    local P = ns.Prices
    if owned > 0 and P then
      local values = {}
      local vendor = P.Vendor(itemID)
      if vendor then values[#values + 1] = format("%s: %s", L["Vendor value"], P.Money(owned * vendor)) end
      local price, source -- (an "and" would cut the second return value off)
      price, source = P.Auction(itemID)
      if price then values[#values + 1] = format("%s: %s", format(L["Auction value (%s)"], source), P.Money(owned * price)) end
      if #values > 0 then
        table.insert(values, 1, format("%s: %d", L["Quantity counted"], owned))
        out[#out + 1] = {L["Value of the stock"], values, key = "value"}
      end
    end
  end
  local rate, P = M.TotalRate(itemID), ns.Prices
  if rate then
    local lines = {format("%s%s: %.1f", AVG, L["Caught per hour"], rate)}
    local vendor = P and P.Vendor(itemID)
    if vendor then lines[#lines + 1] = format("%s%s: %s", AVG, L["Vendor value per hour"], P.Money(rate * vendor)) end
    local price, source -- (an "and" would cut the second return value off)
    if P then price, source = P.Auction(itemID) end
    if price then lines[#lines + 1] = format("%s%s: %s", AVG, format(L["Auction value per hour (%s)"], source), P.Money(rate * price)) end
    out[#out + 1] = {L["Per hour, this character"], lines, key = "hour"}
  end
  return out
end

--- Third column of the bobber display: fish per hour and what they are worth per hour at the average of this session
--- ("Ø 12.3/h  1g 50s"); the value is the auction house price when a price addon knows it, otherwise the vendor price,
--- and left out when neither is known. nil while the session is too short.
function M.HourValue(itemID)
  local session = BJ.API.GetSession()
  if session.time < MIN_SESSION then return nil end
  local rate = (session.fish[itemID] or 0) / (session.time / 3600)
  local text = AVG .. format("%.1f/h", rate)
  local P = ns.Prices
  local price = P and (P.Auction(itemID) or P.Vendor(itemID)) -- (the first returns two values, one is enough here)
  if price and rate > 0 then text = text .. "  " .. P.Money(rate * price) end
  return rate > 0 and text or (GREY .. text .. "|r")
end

--- Builds the lines for the fishing spell; shared with the bobber HUD. Entries: string, {left, right} or
--- {header = text}; everything after a header is indented by the renderer, the header gets a rule to its right.
function M.Lines(compact)
  local lines, A = {}, BJ.API
  local bar = M.BarData()
  if bar and compact then
    -- bobber HUD: the skill bar of the zone only (the HUD draws it itself)
    lines[#lines + 1] = {bar = bar}
    bar = nil
  end
  if bar then
    lines[#lines + 1] = {header = L["Fishing skill"]}
    -- Total: every part in the colour of its bar segment (skill, lure, equipment, buffs).
    local parts = {}
    for _, seg in ipairs(bar.segments) do
      parts[#parts + 1] = hex(seg.color) .. (seg.plus and "+" or "") .. seg.value .. "|r"
    end
    local right = #parts > 1 and (table.concat(parts, " ") .. " = ") or ""
    lines[#lines + 1] = {L["Total"], right .. WHITE .. bar.total .. "|r" .. (bar.max and (" / " .. bar.max) or "")}
    lines[#lines + 1] = {bar = bar}
    for _, seg in ipairs(bar.segments) do
      lines[#lines + 1] = {legend = true, color = seg.color, label = seg.label, value = seg.plus and ("+" .. seg.value) or tostring(seg.value)}
    end
    if bar.remaining > 0 then
      lines[#lines + 1] = {legend = true, color = {0.25, 0.28, 0.32}, label = L["Until maximum"], value = tostring(bar.remaining)}
    end
  end
  if not compact then
    -- Retail only: skill per expansion and the gathering bonus stats
    for _, e in ipairs(Skill.RetailLines() or {}) do
      local text = format("%s: %d/%d", e.expansion or "?", e.rank, e.max)
      if e.modifier > 0 then text = text .. format(" |cff1eff00(+%d)|r", e.modifier) end
      lines[#lines + 1] = text
    end
    for _, st in ipairs(Skill.RetailStats() or {}) do
      if st.name and st.value then
        lines[#lines + 1] = {st.name, ns.Format.Value(st.value, st.pct and st.pct / 100)}
      end
    end
  end
  local zone, name = ns.Zone.Key()
  if zone and opt("counters") then
    local t = A.GetTotals(zone)
    if t.cast > 0 or t.abort > 0 then
      lines[#lines + 1] = {header = format(L["Zone: %s"], name or A.GetZoneName(zone))}
      lines[#lines + 1] = {L["Casts"], WHITE .. t.cast .. "|r"}
      lines[#lines + 1] = {L["Catches"], WHITE .. t.catch .. "|r"}
      -- Failed: bobber not clicked or nothing looted. Aborted: moved away or attacked; aborted casts are not part of "Casts".
      lines[#lines + 1] = {L["Failed casts"], WHITE .. math.max(t.cast - t.catch, 0) .. "|r"}
      lines[#lines + 1] = {L["Aborted casts"], WHITE .. t.abort .. "|r"}
      if t.cast > 0 then
        lines[#lines + 1] = {L["Catch rate"], ns.Format.Percent(t.catch / t.cast)}
      end
    end
  end
  local hideCatches = compact and BJ.settings and BJ.settings.bobber and BJ.settings.bobber.hideCatches == true
  if zone and opt("catches") and not hideCatches then
    -- Junk is recorded like everything else but only listed (own category) when the player switches it on.
    local fish, junk = {}, {}
    for _, f in ipairs(A.GetZoneFish(zone)) do
      if A.IsJunk(f.itemID) then junk[#junk + 1] = f else fish[#fish + 1] = f end
    end
    local function list(title, entries)
      if #entries == 0 then return end
      lines[#lines + 1] = {header = title}
      -- Retail: catch rank read from the fish page; names are padded with spaces so the ranks stand in one column
      local shown, widest, hasRank = math.min(#entries, MAX_FISH), 0, false
      local labels, ranks = {}, {}
      for i = 1, shown do
        ranks[i] = ns.Flavor.current == ns.Flavor.RETAIL and BJ.DB:Rank(entries[i].itemID) or nil
        hasRank = hasRank or ranks[i] ~= nil
        labels[i] = itemLabel(entries[i].itemID)
        widest = math.max(widest, M.TextWidth(labels[i]))
      end
      for i = 1, shown do
        local label = labels[i]
        if hasRank then
          local pad = math.max(math.floor((widest - M.TextWidth(label)) / M.SpaceWidth() + 0.5), 0) + 2
          label = label .. string.rep(" ", pad) .. (ranks[i] or "")
        end
        lines[#lines + 1] = {label, ns.Format.Value(entries[i].drops, entries[i].chance), compact and M.HourValue(entries[i].itemID) or nil}
      end
    end
    list(format(L["Catches in %s"], name or A.GetZoneName(zone)), fish)
    if optIn("junk") then list(L["Clean the waters"], junk) end
  end
  -- Retail: oversized bobber toy (buff and cooldown), only when the toy is owned
  local toy = BJ.modules.Cast and BJ.modules.Cast.ToyStatus and BJ.modules.Cast.ToyStatus()
  if toy then
    local function clock(sec) sec = math.floor(sec or 0) return sec >= 60 and format("%d:%02d", math.floor(sec / 60), sec % 60) or format("%d s", sec) end
    lines[#lines + 1] = {header = L["Oversized bobber"]}
    lines[#lines + 1] = {L["Buff"], toy.active and (hex(C.aqua) .. L["Active"] .. (toy.left and (" (" .. clock(toy.left) .. ")") or "") .. "|r") or (GREY .. L["Inactive"] .. "|r")}
    lines[#lines + 1] = {L["Cooldown"], toy.cooldown and (WHITE .. clock(toy.cooldown) .. "|r") or (hex(C.aqua) .. L["Ready"] .. "|r")}
  end
  return lines
end

local INDENT = "   "

-- Rules in the tooltip, like the settings sections: from the right edge of a header text to the right edge of the
-- tooltip. Anchored to the text instead of measuring it (text width can be a secret value). Pooled per tooltip and
-- hidden again when the tooltip is cleared or hidden.
local function rule(tooltip)
  local text = tooltip.GetName and tooltip:GetName() and _G[tooltip:GetName() .. "TextLeft" .. tooltip:NumLines()]
  if not text then return end
  local pool = tooltip.bjRules
  if not pool then
    pool = {used = 0}
    tooltip.bjRules = pool
    local function reset() for i = 1, pool.used do pool[i]:Hide() end pool.used = 0 end
    tooltip:HookScript("OnHide", reset)
    if tooltip:HasScript("OnTooltipCleared") then tooltip:HookScript("OnTooltipCleared", reset) end
  end
  pool.used = pool.used + 1
  local line = pool[pool.used]
  if not line then
    line = tooltip:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.aqua[1], C.aqua[2], C.aqua[3], 0.9)
    if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(line, 1) else line:SetHeight(1) end
    if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(true) line:SetTexelSnappingBias(0) end
    pool[pool.used] = line
  end
  line:ClearAllPoints()
  line:SetPoint("LEFT", text, "RIGHT", 8, 0)
  line:SetPoint("RIGHT", tooltip, "RIGHT", -10, 0)
  line:Show()
end

--- Title line: icon, name and a rule.
function M.AddHeader(tooltip)
  tooltip:AddLine("|T" .. ns.Icons.Path(ns.Icons.bobber, 64) .. ":0|t " .. C.Paint("aqua", L["ADDON_NAME"]))
  rule(tooltip)
end

--- Appends the lines from M.Lines to a tooltip: headers with a rule, content below them indented.
local BAR_W, BAR_H = 240, 16

local function detailsShown()
  local t = BJ.settings and BJ.settings.tooltip or {}
  if t.barDetails == "always" then return true end
  local key = t.barKey or "SHIFT"
  if key == "CTRL" then return IsControlKeyDown() end
  if key == "ALT" then return IsAltKeyDown() end
  return IsShiftKeyDown()
end

local function swatch(color)
  return format("|TInterface\\Buttons\\WHITE8X8:10:10:0:0:1:1:0:1:0:1:%d:%d:%d|t ",
    color[1] * 255 + 0.5, color[2] * 255 + 0.5, color[3] * 255 + 0.5)
end

--- Draws the segmented bar over the placeholder line that was just added. The line holds an inline texture of the
--- bar's size (fixed width, so no text measuring); the bar itself is a frame with one texture per segment.
local function drawBar(tooltip, data)
  local name = tooltip.GetName and tooltip:GetName()
  local text = name and _G[name .. "TextLeft" .. tooltip:NumLines()]
  if not text then return end
  local bar = tooltip.bjBar
  if not bar then
    bar = CreateFrame("Frame", nil, tooltip)
    bar:SetSize(BAR_W, BAR_H)
    bar.border = bar:CreateTexture(nil, "BACKGROUND")
    bar.border:SetAllPoints()
    bar.border:SetColorTexture(0, 0, 0, 1)
    bar.back = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar.back:SetPoint("TOPLEFT", 1, -1) bar.back:SetPoint("BOTTOMRIGHT", -1, 1)
    bar.back:SetColorTexture(0.10, 0.13, 0.17, 1)
    bar.segs = {}
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.label:SetShadowOffset(1, -1)
    bar.mark = bar:CreateTexture(nil, "OVERLAY")
    bar.mark:SetSize(2, BAR_H + 4)
    bar.mark:SetColorTexture(1, 1, 1, 0.8)
    tooltip.bjBar = bar
    -- The bar is as wide as the tooltip (text inset 10 px on both sides); segments and mark follow the width.
    function bar.layout()
      local cur = bar.data
      if not cur then return end
      local width = math.max(BAR_W, (tooltip:GetWidth() or 0) - 20)
      bar:SetWidth(width)
      M.LayoutBar(bar, cur, width, BAR_H)
    end
    tooltip:HookScript("OnSizeChanged", function() if bar:IsShown() then bar.layout() end end)
    local function hide() bar:Hide() end
    tooltip:HookScript("OnHide", hide)
    if tooltip:HasScript("OnTooltipCleared") then tooltip:HookScript("OnTooltipCleared", hide) end
  end
  bar:SetFrameLevel(tooltip:GetFrameLevel() + 5)
  bar.label:SetText(data.text or "")
  bar:ClearAllPoints()
  bar:SetPoint("LEFT", text, "LEFT", 0, 0)
  bar.data, bar.text = data, text
  bar.layout()
  bar:Show()
end

--- Appends the lines from M.Lines to a tooltip: headers with a rule, content below them indented, the skill bar
--- and its legend (the legend only with the chosen key held, or always, as set in the options).
-- Widest "left + gap + right" pair of the double lines; the tooltip gets at least this width so the columns never overlap.
local function neededWidth(lines)
  measure = measure or UIParent:CreateFontString(nil, "ARTWORK", "GameTooltipText")
  local widest = 0
  local indented
  for _, line in ipairs(lines) do
    if type(line) == "table" and line.header then indented = true
    elseif type(line) == "table" and line[1] and line[2] then
      measure:SetText((indented and INDENT or "") .. line[1])
      local l = tonumber(measure:GetStringWidth()) or 0
      measure:SetText(line[2])
      local r = tonumber(measure:GetStringWidth()) or 0
      widest = math.max(widest, l + r)
    end
  end
  return widest
end

--- Mouse over a skill bar (the one of the screen and the one of the bobber display): heading with icon and rule, the
--- fishing skill in white, then the split of the value, each part in the colour of its piece of the bar, and the total score.
function M.ShowSplit(owner, anchor)
  local data = M.BarData()
  if not data then return end
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_TOP")
  GameTooltip:AddLine("|T" .. ns.Icons.Path(ns.Icons.bobber, 64) .. ":0|t " .. C.Paint("aqua", L["ADDON_NAME"]))
  rule(GameTooltip)
  GameTooltip:AddLine(L["Fishing skill"], 1, 1, 1)
  for _, seg in ipairs(data.segments) do
    GameTooltip:AddDoubleLine(INDENT .. hex(seg.color) .. seg.label .. "|r", (seg.plus and "+" or "") .. seg.value, 1, 1, 1, 1, 1, 1)
  end
  GameTooltip:AddDoubleLine(INDENT .. C.Paint("aqua", L["Total score:"]), data.total .. (data.max and ("/" .. data.max) or ""), 1, 1, 1, 1, 1, 1)
  GameTooltip:Show()
end

function M.Render(tooltip, lines)
  local indented, hintText
  if tooltip.SetMinimumWidth then
    local w = neededWidth(lines)
    if w > 0 then tooltip:SetMinimumWidth(w + 20 + 30) end -- 20 px inset, 30 px gap between the columns
    if not tooltip.bjMinWidthReset then
      tooltip.bjMinWidthReset = true
      tooltip:HookScript("OnHide", function() tooltip:SetMinimumWidth(0) end) -- other tooltips keep their own width
    end
  end
  local showLegend = detailsShown()
  for _, line in ipairs(lines) do
    if type(line) == "table" and line.header then
      tooltip:AddLine(C.Paint("aqua", line.header))
      rule(tooltip)
      indented = true
    elseif type(line) == "table" and line.bar then
      tooltip:AddLine("|TInterface\\Buttons\\WHITE8X8:" .. BAR_H .. ":" .. BAR_W .. ":0:0:1:1:0:1:0:1:0:0:0|t")
      drawBar(tooltip, line.bar)
    elseif type(line) == "table" and line.legend then
      if showLegend then
        tooltip:AddDoubleLine(INDENT .. swatch(line.color) .. hex(line.color) .. line.label .. "|r", hex(line.color) .. line.value .. "|r", 1, 1, 1, 1, 1, 1)
      elseif not hintText then
        local key = (BJ.settings and BJ.settings.tooltip and BJ.settings.tooltip.barKey) or "SHIFT"
        hintText = format(L["%s: details"], ({SHIFT = SHIFT_KEY_TEXT, CTRL = CTRL_KEY_TEXT, ALT = ALT_KEY_TEXT})[key] or key)
      end
    elseif type(line) == "table" then
      tooltip:AddDoubleLine((indented and INDENT or "") .. line[1], line[2], 1, 1, 1, 1, 1, 1)
    else
      tooltip:AddLine((indented and INDENT or "") .. line)
    end
  end
  return hintText -- details hint: the caller puts it in blue below the click hint
end

local function duration(seconds)
  seconds = math.floor(seconds or 0)
  if SecondsToTime and seconds > 0 then return SecondsToTime(seconds) end
  return format("%d:%02d h", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

--- Lines for the minimap button: skill with rank (when the client has one) and the totals of this character over
--- all zones. Entries as in M.Lines.
function M.SummaryLines()
  local lines, A = {}, BJ.API
  local rank, max, mod = Skill.Info()
  if rank then
    lines[#lines + 1] = {header = L["Fishing"]}
    local text = format("%d/%d", rank, max)
    if mod and mod > 0 then text = text .. format(" |cff1eff00(+%d)|r", mod) end
    lines[#lines + 1] = {L["Fishing skill"], WHITE .. text .. "|r"}
    local title = Skill.Rank()
    if title then lines[#lines + 1] = {L["Rank"], WHITE .. title .. "|r"} end
    for _, e in ipairs(Skill.RetailLines() or {}) do
      lines[#lines + 1] = {e.expansion or "?", WHITE .. format("%d/%d", e.rank, e.max) .. "|r"}
    end
  end
  local t = A.GetTotals()
  if t.cast > 0 or t.abort > 0 then
    lines[#lines + 1] = {header = L["Statistics of this character"]}
    lines[#lines + 1] = {L["Casts"], WHITE .. t.cast .. "|r"}
    lines[#lines + 1] = {L["Catches"], WHITE .. t.catch .. "|r"}
    lines[#lines + 1] = {L["Failed casts"], WHITE .. math.max(t.cast - t.catch, 0) .. "|r"}
    lines[#lines + 1] = {L["Aborted casts"], WHITE .. t.abort .. "|r"}
    if t.cast > 0 then
      lines[#lines + 1] = {L["Catch rate"], ns.Format.Percent(t.catch / t.cast)}
    end
    local time = A.GetFishingTime()
    if time > 0 then lines[#lines + 1] = {L["Time spent fishing"], WHITE .. duration(time) .. "|r"} end
  end
  return lines
end

-- Fish per hour and what they are worth per hour (vendor, auction house): the character's totals and this session.
-- The time is the time of the casts (cast start to cast end), without walking or waiting.
local function incomeLines(itemID)
  local A, P = BJ.API, ns.Prices
  local session = A.GetSession()
  if session.time < MIN_SESSION then return {} end
  -- average over all catches since the login (the session is reset by a new login only, a /reload keeps it)
  local rate = (session.fish[itemID] or 0) / (session.time / 3600)
  local lines = {{header = L["Per hour"]}}
  lines[#lines + 1] = {AVG .. L["Caught per hour"], WHITE .. format("%.1f", rate) .. "|r"}
  local vendor = P and P.Vendor(itemID)
  if vendor then lines[#lines + 1] = {AVG .. L["Vendor value per hour"], P.Money(rate * vendor)} end
  local price, source -- (an "and" would cut the second return value off)
  if P then price, source = P.Auction(itemID) end
  if price then lines[#lines + 1] = {AVG .. format(L["Auction value per hour (%s)"], source), P.Money(rate * price)} end
  -- no price addon: no auction line at all (the option text names the addons)
  return lines
end

--- Lines for a caught item: how often, average quantity and where (zones with chances and the best spots).
--- Empty when the item was never fished. Coordinates are map percent of the zone.
--- forJournal: the journal shows the spots on its map page and the value on its sales page, so the coordinates stay out here.
function M.ItemLines(itemID, forJournal)
  local A = BJ.API
  local zones = A.GetFishZones(itemID)
  if #zones == 0 then return {} end
  local lines, drops, qty = {}, 0, 0
  for _, z in ipairs(zones) do
    drops = drops + z.drops
    for _, f in ipairs(A.GetZoneFish(z.zone)) do
      if f.itemID == itemID then qty = qty + f.avgQuantity * f.drops end
    end
  end
  lines[1] = {header = L["Fishing"]}
  lines[2] = {L["Caught by this character"], WHITE .. A.GetCaught(itemID) .. "|r"}
  local account = A.GetCaught(itemID, true)
  if account ~= A.GetCaught(itemID) then lines[#lines + 1] = {L["Caught on the account"], WHITE .. account .. "|r"} end
  lines[#lines + 1] = {L["Times looted"], WHITE .. drops .. "|r"}
  lines[#lines + 1] = {L["Average quantity"], WHITE .. format("%.1f", qty / math.max(drops, 1)) .. "|r"}
  if opt("income") then
    for _, l in ipairs(incomeLines(itemID)) do lines[#lines + 1] = l end
  end
  lines[#lines + 1] = {header = L["Caught in"]}
  for i = 1, math.min(#zones, MAX_ZONES) do
    local z = zones[i]
    lines[#lines + 1] = {A.GetZoneName(z.zone),
      ns.Format.Value(z.drops, z.chance)}
    local spots = A.GetZoneSpots(z.zone, itemID)
    table.sort(spots, function(a, b) return a.count > b.count end)
    for k = 1, forJournal and 0 or math.min(#spots, MAX_SPOTS) do
      lines[#lines + 1] = {GREY .. "   " .. format("%.1f / %.1f", spots[k].x * 100, spots[k].y * 100) .. "|r",
        GREY .. "x" .. spots[k].count .. "|r"}
    end
  end
  return lines
end

local function onItem(tooltip, data)
  if tooltip ~= GameTooltip or not opt("items") or type(data) ~= "table" then return end
  local id = BJ.Clean(data.id)
  if type(id) ~= "number" then return end
  BJ.Protected("item tooltip", function()
    local lines = M.ItemLines(id)
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    M.AddHeader(tooltip)
    M.Render(tooltip, lines)
    tooltip:Show() -- recalculate the width
  end)
end

-- Blizzard's info icon (friends frame), desaturated and tinted blue. Inline texture markup cannot do that, so it is a
-- real texture on the tooltip, anchored to the left edge of the last line (the line starts with blank space for it).
-- One per tooltip, hidden again when the tooltip is cleared or hidden.
function M.InfoIcon(tooltip)
  local name = tooltip.GetName and tooltip:GetName()
  local text = name and _G[name .. "TextLeft" .. tooltip:NumLines()]
  if not text then return end
  local icon = tooltip.bjInfoIcon
  if not icon then
    icon = tooltip:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\FriendsFrame\\InformationIcon")
    icon:SetSize(16, 16)
    icon:SetDesaturated(true)
    icon:SetVertexColor(0.26, 0.69, 1)
    tooltip.bjInfoIcon = icon
    local function hide() icon:Hide() end
    tooltip:HookScript("OnHide", hide)
    if tooltip:HasScript("OnTooltipCleared") then tooltip:HookScript("OnTooltipCleared", hide) end
  end
  icon:ClearAllPoints()
  icon:SetPoint("LEFT", text, "LEFT", 0, 0)
  icon:Show()
end

local function onSpell(tooltip, data)
  if tooltip ~= GameTooltip or not opt("enabled") or type(data) ~= "table" then return end
  local id = BJ.Clean(data.id)
  if type(id) ~= "number" or not Skill.IsFishingSpell(id) then return end
  BJ.Protected("tooltip", function()
    tooltip:AddLine(" ") -- gap to the lines above (Blizzard text, other addons)
    M.AddHeader(tooltip)
    local hint = M.Render(tooltip, M.Lines(false))
    -- The cast hint comes last in the tooltip, the blue details hint right below it.
    local cast = BJ.modules.Cast
    if cast and cast.Enabled() then
      tooltip:AddLine("     |cff42b1fe" .. cast.ShortcutText() .. "|r")
      M.InfoIcon(tooltip)
    end
    if hint then tooltip:AddLine("     |cff42b1fe" .. hint .. "|r") end
    tooltip:Show() -- recalculate the width: long item names overlapped the right column
  end)
end

-- Is the player fishing right now (channelling a fishing spell)?
local function fishing()
  if not UnitChannelInfo then return false end
  local ok, _, _, _, _, _, _, _, spellID = pcall(UnitChannelInfo, "player")
  spellID = ok and BJ.Clean(spellID)
  return type(spellID) == "number" and Skill.IsFishingSpell(spellID)
end

-- Without the bobber display the figures appear in the tooltip of the bobber itself (mouse over the bobber in the water).
local function onObject(tooltip, data)
  if tooltip ~= GameTooltip or not opt("enabled") or type(data) ~= "table" then return end
  local hud = BJ.settings and BJ.settings.bobber
  if hud and hud.enabled then return end
  if not fishing() then return end
  BJ.Protected("bobber tooltip", function()
    tooltip:AddLine(" ")
    M.AddHeader(tooltip)
    M.Render(tooltip, M.Lines(false))
    tooltip:Show() -- recalculate the width
  end)
end

function M:OnEnable()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, onSpell)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
    if Enum.TooltipDataType.Object then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, onObject) end
    -- Debug: toys (toy box) show their item ID, to find the ID of the bobber toy
    if Enum.TooltipDataType.Toy then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Toy, function(tooltip, data)
        if tooltip ~= GameTooltip or not (BJ.settings and BJ.settings.debug) then return end
        local id = type(data) == "table" and BJ.Clean(data.id)
        if type(id) == "number" then BJ:DebugTip(tooltip, "Toy item", id) end
      end)
    end
  end
end
