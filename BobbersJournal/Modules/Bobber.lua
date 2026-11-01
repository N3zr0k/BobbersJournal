local _, ns = ...
local BJ, Skill = ns.BJ, ns.Skill
local L = BJ.L
-- Bobber HUD: a transparent tooltip-like display with logo while fishing. Event driven, no OnUpdate.
-- Shown on the first cast, hidden when the player starts moving or enters combat.
-- Not placed above the bobber: the client exposes no screen position of the bobber object.
-- Position: set in Blizzard's Edit Mode where the client has one (the options window closes and Edit Mode opens),
-- otherwise in a plain drag mode with a Done button. Saved as offset from the screen centre.
local M = BJ:RegisterModule("Bobber")

local frame, editing, blizzardEdit

-- Same nine-slice frame Edit Mode draws around its systems (atlas kit names from Blizzard_EditMode).
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

local function opt(name)
  local b = BJ.settings and BJ.settings.bobber
  return b and b[name]
end

local function create()
  frame = CreateFrame("Frame", "BobbersJournalBobberHud", UIParent)
  frame:SetSize(280, 120)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:Hide()
  frame.logo = frame:CreateTexture(nil, "ARTWORK")
  frame.logo:SetSize(28, 28)
  frame.logo:SetPoint("TOPLEFT", 0, 0)
  frame.logo:SetTexture(ns.Icons.logo(64))
  frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  frame.title:SetPoint("LEFT", frame.logo, "RIGHT", 6, 0)
  frame.title:SetText(L["ADDON_NAME"])
  frame.title:SetTextColor(unpack(ns.Colors.sand))
  frame.rows = {}
  -- Selection frame as in Edit Mode; visual only, the HUD frame itself takes the drag.
  frame.selection = CreateFrame("Frame", nil, frame)
  frame.selection:SetAllPoints()
  frame.selection:SetFrameLevel(frame:GetFrameLevel() + 5)
  frame.selection:EnableMouse(false)
  frame.selection:Hide()
  frame.selection.fallback = frame.selection:CreateTexture(nil, "BACKGROUND")
  frame.selection.fallback:SetAllPoints()
  frame.selection.fallback:SetColorTexture(ns.Colors.aqua[1], ns.Colors.aqua[2], ns.Colors.aqua[3], 0.35)
  frame.selection.fallback:Hide()
  frame.selection.label = frame.selection:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  frame.selection.label:SetPoint("CENTER")
  frame.selection.label:SetText(L["ADDON_NAME"])
  frame.done = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.done:SetSize(100, 22)
  frame.done:SetPoint("TOP", frame, "BOTTOM", 0, -12)
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
    local b = BJ.settings.bobber
    b.point, b.x, b.y = "CENTER", math.floor(x - cx + 0.5), math.floor(y - cy + 0.5)
  end)
end

local function place()
  frame:ClearAllPoints()
  frame:SetPoint(opt("point") or "TOP", UIParent, opt("point") == "CENTER" and "CENTER" or "TOP", opt("x") or 0, opt("y") or -160)
  frame:SetScale(opt("scale") or 1)
end

local ROW_HEIGHT, INDENT, HEAD_HEIGHT = 16, 14, 36

-- One row = left text, right text and a rule; rows are pooled and stacked below the title.
local function getRow(i)
  local row = frame.rows[i]
  if row then return row end
  row = {}
  row.left = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.left:SetJustifyH("LEFT")
  row.left:SetShadowOffset(1, -1)
  row.right = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.right:SetJustifyH("RIGHT")
  row.right:SetShadowOffset(1, -1)
  row.rule = frame:CreateTexture(nil, "ARTWORK")
  row.rule:SetColorTexture(ns.Colors.aqua[1], ns.Colors.aqua[2], ns.Colors.aqua[3], 0.9)
  row.rule:SetHeight(1)
  frame.rows[i] = row
  return row
end

local function layout(lines)
  local y, indented = -HEAD_HEIGHT, false
  for i, line in ipairs(lines) do
    local row = getRow(i)
    local header = type(line) == "table" and line.header
    if header then indented = true end
    local x = (indented and not header) and INDENT or 0
    row.left:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    row.left:SetText(header and ns.Colors.Paint("aqua", header) or (type(line) == "table" and line[1] or line))
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, y)
    row.right:SetText((not header and type(line) == "table" and line[2]) or "")
    row.left:Show() row.right:Show()
    row.rule:ClearAllPoints()
    if header then
      row.rule:SetPoint("LEFT", row.left, "RIGHT", 8, 0)
      row.rule:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
      row.rule:Show()
    else
      row.rule:Hide()
    end
    y = y - ROW_HEIGHT - (header and 2 or 0)
  end
  for i = #lines + 1, #frame.rows do
    local row = frame.rows[i]
    row.left:Hide() row.right:Hide() row.rule:Hide()
  end
  frame:SetHeight(math.max(-y + 4, HEAD_HEIGHT))
end

local function draw()
  if not frame then create() end
  place()
  layout(editing and {L["Drag to move"]} or BJ.modules.Tooltip.Lines(true))
  frame:SetMouseClickEnabled(editing == true)
  frame.selection:SetShown(editing == true)
  frame.done:SetShown(editing == true and not blizzardEdit)
  if editing then skin("editmode-actionbar-highlight") end
  frame:Show()
end

local function stop()
  editing, blizzardEdit = false, false
  if frame then frame:Hide() frame.selection:Hide() frame.done:Hide() end
end

--- Start placing the HUD. With Blizzard's Edit Mode the options window closes and Edit Mode opens; without it
--- (or in combat) the HUD gets a plain drag mode. Shown even without fishing so it can be placed.
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
  if blizzardEdit and EditModeManagerFrame and EditModeManagerFrame:IsShown() and HideUIPanel then
    HideUIPanel(EditModeManagerFrame) -- triggers EditMode.Exit
  end
  stop()
end
function M.IsEditing() return editing == true end

local function hide() if frame and not editing then frame:Hide() end end

function M:OnEnable()
  -- Edit Mode opened by the player: the HUD shows up with its selection frame so it can be moved there too.
  if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("EditMode.Enter", function()
      editing, blizzardEdit = true, true
      BJ.Protected("bobber-edit", draw)
    end, M)
    EventRegistry:RegisterCallback("EditMode.Exit", function() stop() end, M)
  end
  BJ:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", "bobber", function(_, unit, _, spellID)
    if unit == "player" and opt("enabled") and Skill.IsFishingSpell(spellID) then draw() end
  end)
  -- Refresh numbers after each result while visible
  BJ:Listen(function() if frame and frame:IsShown() and not editing then draw() end end)
  BJ:RegisterEvent("PLAYER_STARTED_MOVING", "bobber", hide)
  BJ:RegisterEvent("PLAYER_REGEN_DISABLED", "bobber", hide)
end
