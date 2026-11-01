local _, ns = ...
local BJ, Skill = ns.BJ, ns.Skill
local L = BJ.L
-- Fishing spell tooltip (Forever and Retail): skill, cast shortcut, catches and counters of the current zone.
-- Lines are only appended in a post-call, the tooltip is never rebuilt from here (no RefreshData -> no taint).
-- Lure/buff split of the bonus from Glimpse is not ported yet.
local M = BJ:RegisterModule("Tooltip")

local C = ns.Colors
local WHITE, GREY, YELLOW = C.sandHex, C.parchmentHex, C.aquaHex
local MAX_FISH = 5
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
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not name then
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return "[" .. id .. "]"
  end
  local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  return c and format("|cff%02x%02x%02x%s|r", c.r * 255 + 0.5, c.g * 255 + 0.5, c.b * 255 + 0.5, name) or name
end

-- Bonus of the lure on the pole, read from the line of the weapon tooltip that names the fishing skill
-- ("... (+75 Fishing) ..."). 0 when there is none or the client does not offer the tooltip data.
local function lureBonus()
  if not (ns.Gear and ns.Gear.GetMainHandEnchant()) then return 0 end
  local stem = (Skill.Name() or ""):sub(1, 4):lower()
  if stem == "" or not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return 0 end
  local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", ns.Gear.MAIN_HAND)
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
  return format("|cff%02x%02x%02x", color[1] * 255 + 0.5, color[2] * 255 + 0.5, color[3] * 255 + 0.5)
end

local BUFF_COLORS = {{0.90, 0.27, 0.27}, {0.95, 0.55, 0.20}, {0.70, 0.35, 0.85}, {0.30, 0.85, 0.45}}
local GEAR_COLOR = {0.26, 0.69, 1}

--- Segments of the skill bar: base skill, lure, equipment (what the total bonus has left after lure and buffs)
--- and one segment per known buff. The client only gives the total bonus; the split is an estimate.
function M.BarData()
  local rank, max, mod = Skill.Info()
  if not rank then return nil end
  mod = mod or 0
  local segments = {{label = L["Fishing skill"], value = rank, color = C.aqua}}
  local lure = lureBonus()
  local buffs, known = {}, lure
  for _, b in pairs(BJ.modules.Buffs and BJ.modules.Buffs.active or {}) do
    if type(b.bonus) == "number" and b.bonus > 0 then buffs[#buffs + 1] = b known = known + b.bonus end
  end
  table.sort(buffs, function(x, y) return tostring(x.name) < tostring(y.name) end)
  local gear = math.max(mod - known, 0)
  if lure > 0 then segments[#segments + 1] = {label = L["Lure"], value = lure, color = C.parchment, plus = true} end
  if gear > 0 then segments[#segments + 1] = {label = L["Equipment"], value = gear, color = GEAR_COLOR, plus = true} end
  for i, b in ipairs(buffs) do
    segments[#segments + 1] = {label = b.name, value = b.bonus, color = BUFF_COLORS[(i - 1) % #BUFF_COLORS + 1], plus = true}
  end
  local total = 0
  for _, seg in ipairs(segments) do total = total + seg.value end
  return {segments = segments, total = total, max = max, scale = math.max(max or total, total, 1),
    remaining = math.max((max or total) - total, 0)}
end

--- Builds the lines for the fishing spell; shared with the bobber HUD. Entries: string, {left, right} or
--- {header = text}; everything after a header is indented by the renderer, the header gets a rule to its right.
function M.Lines(compact)
  local lines, A = {}, BJ.API
  local bar = not compact and M.BarData()
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
        lines[#lines + 1] = {st.name, WHITE .. st.value .. (st.pct and format(" (%.1f %%)", st.pct) or "") .. "|r"}
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
        lines[#lines + 1] = {L["Catch rate"], format("%s%d %%|r", WHITE, math.floor(t.catch / t.cast * 100 + 0.5))}
      end
    end
  end
  if zone and opt("catches") then
    -- Junk is recorded like everything else but only listed (own category) when the player switches it on.
    local fish, junk = {}, {}
    for _, f in ipairs(A.GetZoneFish(zone)) do
      if A.IsJunk(f.itemID) then junk[#junk + 1] = f else fish[#fish + 1] = f end
    end
    local function list(title, entries)
      if #entries == 0 then return end
      lines[#lines + 1] = {header = title}
      for i = 1, math.min(#entries, MAX_FISH) do
        lines[#lines + 1] = {itemLabel(entries[i].itemID),
          format("%d %%  %s(%d)|r", math.floor(entries[i].chance * 100 + 0.5), GREY, entries[i].drops)}
      end
    end
    list(format(L["Catches in %s"], name or A.GetZoneName(zone)), fish)
    if optIn("junk") then list(L["Clean the waters"], junk) end
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
local BAR_W, BAR_H = 240, 12

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
    bar.mark = bar:CreateTexture(nil, "OVERLAY")
    bar.mark:SetSize(2, BAR_H + 4)
    bar.mark:SetColorTexture(1, 1, 1, 0.8)
    tooltip.bjBar = bar
    local function hide() bar:Hide() end
    tooltip:HookScript("OnHide", hide)
    if tooltip:HasScript("OnTooltipCleared") then tooltip:HookScript("OnTooltipCleared", hide) end
  end
  bar:SetFrameLevel(tooltip:GetFrameLevel() + 5)
  bar:ClearAllPoints()
  bar:SetPoint("LEFT", text, "LEFT", 0, 0)
  local x = 1
  for i, seg in ipairs(data.segments) do
    local tex = bar.segs[i]
    if not tex then tex = bar:CreateTexture(nil, "ARTWORK") bar.segs[i] = tex end
    local w = math.floor((BAR_W - 2) * seg.value / data.scale + 0.5)
    if seg.value > 0 and w < 1 then w = 1 end
    tex:ClearAllPoints()
    tex:SetPoint("LEFT", bar, "LEFT", x, 0)
    tex:SetSize(w, BAR_H - 2)
    tex:SetColorTexture(seg.color[1], seg.color[2], seg.color[3], 1)
    tex:Show()
    x = x + w
  end
  for i = #data.segments + 1, #bar.segs do bar.segs[i]:Hide() end
  -- White mark at the maximum when bonuses push the total beyond it.
  if data.max and data.total > data.max then
    bar.mark:ClearAllPoints()
    bar.mark:SetPoint("CENTER", bar, "LEFT", 1 + (BAR_W - 2) * data.max / data.scale, 0)
    bar.mark:Show()
  else
    bar.mark:Hide()
  end
  bar:Show()
end

--- Appends the lines from M.Lines to a tooltip: headers with a rule, content below them indented, the skill bar
--- and its legend (the legend only with the chosen key held, or always, as set in the options).
function M.Render(tooltip, lines)
  local indented, hintText
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
      lines[#lines + 1] = {L["Catch rate"], format("%s%d %%|r", WHITE, math.floor(t.catch / t.cast * 100 + 0.5))}
    end
    local time = A.GetFishingTime()
    if time > 0 then lines[#lines + 1] = {L["Time spent fishing"], WHITE .. duration(time) .. "|r"} end
  end
  return lines
end

--- Lines for a caught item: how often, average quantity and where (zones with chances and the best spots).
--- Empty when the item was never fished. Coordinates are map percent of the zone.
function M.ItemLines(itemID)
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
  lines[#lines + 1] = {header = L["Caught in"]}
  for i = 1, math.min(#zones, MAX_ZONES) do
    local z = zones[i]
    lines[#lines + 1] = {A.GetZoneName(z.zone),
      format("%d %%  %s(%d)|r", math.floor(z.chance * 100 + 0.5), GREY, z.drops)}
    local spots = A.GetZoneSpots(z.zone, itemID)
    table.sort(spots, function(a, b) return a.count > b.count end)
    for k = 1, math.min(#spots, MAX_SPOTS) do
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
  end)
end

function M:OnEnable()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, onSpell)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
  end
end
