local _, ns = ...
local BJ = ns.BJ
local L = BJ.L
-- Fishing skill bar in the style of the experience and reputation bars (Blizzard StatusTrackingBar: bar background
-- and fill atlases of the experience bar, original frame graphic on top, text in the middle). Colour: main colour of
-- the addon; the divisions come from the original frame graphic. Option "skillBar.enabled"; position in Edit Mode or by dragging.
-- Event driven, no OnUpdate. Default place: directly above the experience bars.
local M = BJ:RegisterModule("SkillBar")

local frame, editing, blizzardEdit
local BAR_W, BAR_H = 571, 17 -- as the experience bar container

local function opt(name)
  local s = BJ.settings and BJ.settings.skillBar
  return s and s[name]
end

local SELECTION_LAYOUT = {
  TopRightCorner = {atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8},
  TopLeftCorner = {atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8},
  BottomLeftCorner = {atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8},
  BottomRightCorner = {atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8},
  TopEdge = {atlas = "_%s-NineSlice-EdgeTop"},
  BottomEdge = {atlas = "_%s-NineSlice-EdgeBottom"},
  LeftEdge = {atlas = "!%s-NineSlice-EdgeLeft"},
  RightEdge = {atlas = "!%s-NineSlice-EdgeRight"},
  Center = {atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8},
}

local function skin(kit)
  local sel = frame.selection
  if sel.kit == kit then return end
  sel.kit = kit
  local ok = NineSliceUtil and NineSliceUtil.ApplyLayout and pcall(NineSliceUtil.ApplyLayout, sel, SELECTION_LAYOUT, kit)
  sel.fallback:SetShown(not ok)
end

local hasAtlas = BJ.HasAtlas

-- Geometry as in Blizzard's StatusTrackingBarContainer: container = size of the frame graphic (571 x 17), the bar
-- (StatusBar, 6 px smaller each way) sits at BOTTOMLEFT 1/5, the frame graphic lies on top of it.
local ART_ATLAS = "UI-HUD-ExperienceBar-Frame"

local function innerSize()
  local w, h = frame.inner:GetWidth(), frame.inner:GetHeight()
  return (w and w > 1) and w or BAR_W - 6, (h and h > 1) and h or BAR_H - 6
end

local function create()
  frame = CreateFrame("Frame", "BobbersJournalSkillBar", UIParent)
  local info = hasAtlas(ART_ATLAS) and C_Texture.GetAtlasInfo(ART_ATLAS)
  local aw, ah = info and info.width or BAR_W, info and info.height or BAR_H
  frame:SetSize(aw, ah)
  frame:SetFrameStrata("MEDIUM") -- above the status bars of the game, so the mouse reaches it
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:Hide()
  local aqua = ns.Colors.aqua
  -- the bar itself: a real StatusBar with the experience bar fill atlas, only the colour differs
  frame.inner = CreateFrame("StatusBar", nil, frame)
  frame.inner:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 5)
  frame.inner:SetSize(aw - 6, ah - 6)
  frame.inner:SetMinMaxValues(0, 1)
  frame.inner:SetValue(0)
  frame.inner:SetStatusBarTexture(hasAtlas("UI-HUD-ExperienceBar-Fill-Experience") and "UI-HUD-ExperienceBar-Fill-Experience" or "Interface\\TargetingFrame\\UI-StatusBar")
  local fillTex = frame.inner:GetStatusBarTexture()
  if fillTex then fillTex:SetDesaturated(true) end
  frame.inner:SetStatusBarColor(aqua[1], aqua[2], aqua[3])
  -- the desaturated atlas is dark: an additive layer of the main colour over the filled part makes the bar bright
  if fillTex then
    frame.shine = frame.inner:CreateTexture(nil, "ARTWORK", nil, 2)
    frame.shine:SetAllPoints(fillTex)
    frame.shine:SetColorTexture(aqua[1], aqua[2], aqua[3], 1)
    frame.shine:SetBlendMode("ADD")
    frame.shine:SetAlpha(0.6)
  end
  frame.back = frame.inner:CreateTexture(nil, "BACKGROUND")
  frame.back:SetAllPoints(frame.inner)
  if hasAtlas("UI-HUD-ExperienceBar-Background") then frame.back:SetAtlas("UI-HUD-ExperienceBar-Background")
  else frame.back:SetColorTexture(0.05, 0.07, 0.09, 1) end
  -- rounded ends: the fill, its shine, the bonus and the background are cut with an own rounded-rectangle mask (the experience bar mask is a square flipbook mask)
  if frame.inner.CreateMaskTexture then
    local mask = frame.inner:CreateMaskTexture()
    mask:SetAllPoints(frame.inner)
    mask:SetTexture(ns.Icons.maskBar, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    for _, tex in ipairs({fillTex, frame.shine, frame.back}) do
      if tex and tex.AddMaskTexture then tex:AddMaskTexture(mask) end
    end
    frame.mask = mask
  end
  -- the frame graphic lies ON TOP of the bar (its own divisions included), then the pip and the text
  frame.artFrame = CreateFrame("Frame", nil, frame)
  frame.artFrame:SetAllPoints(frame)
  frame.artFrame:SetFrameLevel(frame:GetFrameLevel() + 3)
  frame.artFrame:EnableMouse(false)
  frame.artTex = frame.artFrame:CreateTexture(nil, "OVERLAY")
  frame.artTex:SetAllPoints(frame.artFrame)
  if info then frame.artTex:SetAtlas(ART_ATLAS) end
  frame.pip = frame.artFrame:CreateTexture(nil, "OVERLAY", nil, 2)
  if hasAtlas("UI-HUD-ExperienceBar-Frame-Pip") then frame.pip:SetAtlas("UI-HUD-ExperienceBar-Frame-Pip") end
  frame.pip:SetSize(10, 14)
  frame.pip:Hide()
  frame.text = frame.artFrame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
  frame.text:SetPoint("CENTER", 0, 3) -- 2 px higher than the original text position
  frame.selection = CreateFrame("Frame", nil, frame)
  frame.selection:SetAllPoints()
  frame.selection:SetFrameLevel(frame:GetFrameLevel() + 5)
  frame.selection:EnableMouse(false)
  frame.selection:Hide()
  frame.selection.fallback = frame.selection:CreateTexture(nil, "BACKGROUND")
  frame.selection.fallback:SetAllPoints()
  frame.selection.fallback:SetColorTexture(aqua[1], aqua[2], aqua[3], 0.35)
  frame.selection.fallback:Hide()
  frame.selection.label = frame.selection:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.selection.label:SetPoint("CENTER")
  frame.selection.label:SetText(L["Fishing skill"])
  frame.done = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.done:SetSize(100, 22)
  frame.done:SetPoint("BOTTOM", frame, "TOP", 0, 12)
  frame.done:SetText(L["Done editing"])
  frame.done:SetScript("OnClick", function() M.StopEdit() end)
  frame.done:Hide()
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if editing then skin("editmode-actionbar-selected") self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    skin("editmode-actionbar-highlight")
    local cx, cy = UIParent:GetCenter()
    local x, y = self:GetCenter()
    local s = BJ.settings.skillBar
    s.point, s.x, s.y = "CENTER", math.floor(x - cx + 0.5), math.floor(y - cy + 0.5)
  end)
  local function showSplit(self)
    if editing then return end
    if BJ.modules.Tooltip and BJ.modules.Tooltip.ShowSplit then BJ.modules.Tooltip.ShowSplit(self, "ANCHOR_TOP") end
  end
  frame:SetScript("OnEnter", function(self)
    BJ:Debug("skill bar: mouse over")
    BJ.Protected("skill bar tooltip", showSplit, self)
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function place()
  frame:ClearAllPoints()
  local s = BJ.settings.skillBar
  if s.point then
    frame:SetPoint("CENTER", UIParent, "CENTER", s.x or 0, s.y or 0)
  else
    -- default: directly above the experience bars
    local mgr = _G.StatusTrackingBarManager
    if mgr then frame:SetPoint("BOTTOM", mgr, "TOP", 0, 4) else frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 40) end
  end
  frame:SetScale(s.scale or 1)
end

local function draw()
  if not opt("enabled") and not editing then if frame then frame:Hide() end return end
  if not frame then create() end
  place()
  local data = BJ.modules.Tooltip and BJ.modules.Tooltip.BarData and BJ.modules.Tooltip.BarData()
  local rank, max, total = 0, 300, 0
  if data then
    rank, max, total = data.segments[1].value, data.max or data.scale, data.total
  elseif not editing then frame:Hide() return end
  max = math.max(max, 1)
  -- maximum reached: the bar is hidden when the option says so (the tooltip keeps the values)
  if opt("hideAtMax") and not editing and data and rank >= max then frame:Hide() return end
  local width = innerSize()
  -- the bonuses as own pieces behind the fill, each in the colour of its part (lure, equipment, buffs), 1 px gap between
  -- all pieces; the gaps are taken from the width before the values are scaled
  local pieces = {}
  if data then
    for i = 2, #data.segments do
      local seg = data.segments[i]
      if seg.value > 0 then pieces[#pieces + 1] = seg end
    end
  end
  local scale = math.max(max, total, 1)
  local gaps = #pieces
  local unit = math.max(width - gaps, 1) / scale
  local fillW = math.min(rank, scale) * unit
  frame.inner:SetValue(math.min(fillW / width, 1))
  frame.bonusSegs = frame.bonusSegs or {}
  local x = fillW + (rank > 0 and 1 or 0)
  for i, seg in ipairs(pieces) do
    local tex = frame.bonusSegs[i]
    if not tex then
      tex = frame.inner:CreateTexture(nil, "ARTWORK", nil, 3)
      tex:SetHeight(select(2, innerSize()))
      if frame.mask and tex.AddMaskTexture then tex:AddMaskTexture(frame.mask) end
      frame.bonusSegs[i] = tex
    end
    local w = math.max(seg.value * unit, 1)
    tex:ClearAllPoints()
    tex:SetPoint("BOTTOMLEFT", frame.inner, "BOTTOMLEFT", x, 0)
    tex:SetWidth(w)
    tex:SetColorTexture(seg.color[1], seg.color[2], seg.color[3], 1)
    tex:Show()
    x = x + w + 1
  end
  for i = #pieces + 1, #frame.bonusSegs do frame.bonusSegs[i]:Hide() end
  frame.pip:Hide()
  local endX = x - (#pieces > 0 and 1 or 0)
  if #pieces > 0 and endX / width >= 0.01 and endX / width <= 0.99 then
    frame.pip:ClearAllPoints()
    frame.pip:SetPoint("CENTER", frame.inner, "LEFT", endX, 2)
    frame.pip:Show()
  end
  local text = data and (L["Fishing"] .. ": " .. data.text) or L["Fishing skill"]
  if data and data.bonusText ~= "" then text = text .. data.bonusText elseif total > rank then text = text .. format(" |cff1eff00(+%d)|r", total - rank) end
  frame.text:SetText(text)
  frame:EnableMouse(true)
  frame.selection:SetShown(editing == true)
  frame.done:SetShown(editing == true and not blizzardEdit)
  if editing then skin("editmode-actionbar-highlight") end
  frame:Show()
end

local function stop()
  editing, blizzardEdit = false, false
  if frame then frame.selection:Hide() frame.done:Hide() end
  BJ.Protected("skillbar", draw)
end

function M.StartEdit()
  if InCombatLockdown() then BJ:Print(L["Not possible in combat."]) return end
  if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
  editing = true
  if EditModeManagerFrame and ShowUIPanel and EventRegistry then
    blizzardEdit = true
    draw()
    if not EditModeManagerFrame:IsShown() then ShowUIPanel(EditModeManagerFrame) end
  else
    blizzardEdit = false
    draw()
  end
end

function M.StopEdit()
  if blizzardEdit and EditModeManagerFrame and EditModeManagerFrame:IsShown() and HideUIPanel then HideUIPanel(EditModeManagerFrame) end
  stop()
end

--- Called by the options when the setting changes.
function M.Refresh() BJ.Protected("skillbar", draw) end

function M:OnEnable()
  if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("EditMode.Enter", function() editing, blizzardEdit = true, true BJ.Protected("skillbar-edit", draw) end, M)
    EventRegistry:RegisterCallback("EditMode.Exit", function() stop() end, M)
  end
  local function refresh() BJ.Protected("skillbar", draw) end
  BJ:RegisterEvent("PLAYER_ENTERING_WORLD", "skillbar", refresh)
  BJ:RegisterEvent("SKILL_LINES_CHANGED", "skillbar", refresh)
  BJ:RegisterEvent("TRADE_SKILL_LIST_UPDATE", "skillbar", refresh) -- profession data arrived
  BJ:RegisterEvent("ZONE_CHANGED_NEW_AREA", "skillbar", function() ns.Skill.manualLine = nil refresh() end) -- the zone decides again
  -- Another skill line picked in the profession window: the bar follows it. The first value after opening the
  -- window is only the starting point (the window shows its last line), a later change is the player's choice.
  local baseline
  BJ:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED", "skillbar", function()
    local base = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    if type(base) ~= "table" or base.profession ~= Enum.Profession.Fishing then return end
    local id = C_TradeSkillUI.GetProfessionChildSkillLineID and C_TradeSkillUI.GetProfessionChildSkillLineID()
    if type(id) == "number" then
      if baseline == nil then
        baseline = id
      elseif id ~= baseline then
        baseline = id
        for _, e in ipairs(ns.Skill.RetailLines() or {}) do
          if e.id == id then ns.Skill.manualLine = id break end
        end
      end
    end
    refresh()
  end)
  BJ:RegisterEvent("TRADE_SKILL_CLOSE", "skillbar", function() baseline = nil end)
  -- aura and inventory events come in bursts: redraw once shortly after the last one
  local queued
  local function refreshLater()
    if queued or not opt("enabled") then return end
    queued = true
    if C_Timer and C_Timer.After then
      C_Timer.After(0.25, function() queued = false refresh() end)
    else queued = false refresh() end
  end
  BJ:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "skillbar", refreshLater)
  BJ:RegisterEvent("UNIT_INVENTORY_CHANGED", "skillbar", function(_, unit) if unit == "player" then refreshLater() end end)
  BJ:RegisterEvent("UNIT_AURA", "skillbar", function(_, unit) if unit == "player" then refreshLater() end end)
  BJ:Listen(function() if opt("enabled") and not editing then refresh() end end)
end
