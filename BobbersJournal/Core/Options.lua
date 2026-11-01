local ADDON, ns = ...
local BJ = ns.BJ
local L = BJ.L
local C = ns.Colors
-- Settings in the Blizzard options window: main category "Bobber's Journal" (overview) + subcategory "General".
-- Plain canvas widgets so it runs on Forever and Retail without templates that differ between clients.
-- Layout follows N3zr0k/Binds: scrolling page, coloured header, sections with a thin rule, checkboxes with a grey
-- description underneath (switchable; off = description as tooltip), widgets chained by anchors.

local PADDING = 16
local SECTION_GAP = 22
local MODIFIERS = {"SHIFT", "CTRL", "ALT", "NONE"}
local BUTTONS = {"RightButton", "LeftButton", "MiddleButton", "Button4", "Button5"}

local function modifierName(v)
  return ({SHIFT = SHIFT_KEY_TEXT, CTRL = CTRL_KEY_TEXT, ALT = ALT_KEY_TEXT, NONE = NONE})[v] or v
end
local function buttonName(v)
  return ({RightButton = L["Right button"], LeftButton = L["Left button"], MiddleButton = L["Middle button"],
    Button4 = L["Button 4"], Button5 = L["Button 5"]})[v] or v
end

local function section(key) return function() return BJ.settings and BJ.settings[key] or {} end end
local cast, tip, bobber = section("cast"), section("tooltip"), section("bobber")
local function descriptionsOn() return not (BJ.settings and BJ.settings.showDescriptions == false) end

----------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------

StaticPopupDialogs["BOBBERSJOURNAL_RESET"] = {
  text = L["Delete all recorded fishing data, bookmarks and the debug log? This cannot be undone."],
  button1 = L["Delete all"],
  button2 = CANCEL,
  OnAccept = function()
    BJ.DB:Reset()
    BJ:Print(L["All recorded data was deleted."])
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function createPanel(name, parentName)
  local panel = CreateFrame("Frame")
  panel.name, panel.parent = name, parentName
  panel.refreshers = {}
  panel:Hide()
  panel:SetScript("OnShow", function(self)
    for _, refresh in ipairs(self.refreshers) do refresh() end
  end)
  return panel
end

local function refresh(panel)
  for _, fn in ipairs(panel.refreshers) do fn() end
end

-- Pages can be taller than the settings window: widgets sit on a scrolling content frame. `content.last` is the
-- lowest widget and decides the scroll height.
local function createScrollContent(page)
  local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -28, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 800)
  content.refreshers = page.refreshers
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(_, width)
    if width and width > 1 then content:SetWidth(width) end
  end)
  -- Text wraps only once it is laid out, so the height is measured shortly after every refresh.
  local function updateHeight()
    local top, bottom = content:GetTop(), content.last and content.last:GetBottom()
    if type(top) == "number" and type(bottom) == "number" then
      content:SetHeight(math.max(top - bottom + PADDING + 20, 1))
    end
  end
  local function schedule()
    if C_Timer and C_Timer.After then C_Timer.After(0.05, updateHeight) end
  end
  table.insert(page.refreshers, schedule)
  page:HookScript("OnShow", function()
    content:SetWidth(math.max(scroll:GetWidth(), 1))
    schedule()
  end)
  return content
end

local function createHeader(panel, title, subtitle)
  local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  text:SetPoint("TOPLEFT", PADDING, -PADDING)
  text:SetText(C.Paint("aqua", title))
  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
  sub:SetPoint("RIGHT", -PADDING, 0)
  sub:SetJustifyH("LEFT")
  sub:SetText(subtitle or "")
  return sub
end

-- Section title with a thin rule, so groups read as blocks instead of a loose list.
local function createSection(panel, anchor, title)
  local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
  text:SetText(C.Paint("parchment", title))
  local line = panel:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(C.sand[1], C.sand[2], C.sand[3], 0.35)
  if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(line, 1) else line:SetHeight(1) end
  if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(true) line:SetTexelSnappingBias(0) end
  line:SetPoint("LEFT", text, "RIGHT", 8, 0)
  line:SetPoint("RIGHT", panel, "RIGHT", -PADDING, 0)
  return text
end

-- Invisible frame that spans a widget and its description; the next widget anchors below it.
local function createAnchor(panel, top, indent, bottomOf)
  local a = CreateFrame("Frame", nil, panel)
  a:SetSize(1, 1)
  a:SetPoint("TOPLEFT", top, "LEFT", -(indent or 0), 0)
  a:SetPoint("BOTTOM", bottomOf, "BOTTOM")
  return a
end

-- Without the grey texts the explanation shows as a tooltip on the widget.
local function tooltipFor(widget, label, description)
  widget:SetScript("OnEnter", function(self)
    if not descriptionsOn() then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(label, 1, 1, 1)
      GameTooltip:AddLine(description, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function createDescription(panel, owner, text, description)
  local desc = owner:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  desc:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -2)
  desc:SetPoint("RIGHT", panel, "RIGHT", -PADDING, 0)
  desc:SetJustifyH("LEFT")
  desc:SetText(description)
  return desc
end

-- Returns the checkbox and an anchor frame below it for the next widget.
local function createCheckbox(panel, anchor, label, description, get, set, indent, enabled)
  local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  check:SetSize(26, 26)
  check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", indent or 0, -8)
  local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("LEFT", check, "RIGHT", 4, 1)
  text:SetText(label)
  check.label = text
  local desc = description and createDescription(panel, check, text, description)
  check:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    refresh(panel)
  end)
  local anchorFrame = createAnchor(panel, check, indent, desc or check)
  table.insert(panel.refreshers, function()
    check:SetChecked(get())
    local on = enabled == nil or enabled()
    check:SetEnabled(on)
    text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
    if desc then
      local show = descriptionsOn()
      desc:SetShown(show)
      anchorFrame:SetPoint("BOTTOM", show and desc or check, "BOTTOM")
    end
  end)
  if desc then
    local width = text:GetStringWidth()
    if type(width) == "number" then check:SetHitRectInsets(0, -(width + 8), 0, 0) end
    tooltipFor(check, label, description)
  end
  return check, anchorFrame
end

-- Choice as a dropdown: label left, dropdown right. Retail's own dropdown button where the client has it, the classic
-- UIDropDownMenu otherwise; a cycling button is the last resort so the option always works.
local function createChoice(panel, anchor, label, values, get, set, display, indent, enabled)
  local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (indent or 0) + 30, -14)
  text:SetText(label)
  local function pick(v) set(v) refresh(panel) end

  local control, update, setEnabled
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    control = dd
    dd:SetWidth(180)
    dd:SetPoint("LEFT", text, "LEFT", 220, 0)
    dd:SetupMenu(function(_, root)
      for _, v in ipairs(values) do
        root:CreateRadio(display(v), function() return get() == v end, function() pick(v) end)
      end
    end)
    update = function() if dd.GenerateMenu then dd:GenerateMenu() end end
    setEnabled = function(on) dd:SetEnabled(on) end
  elseif UIDropDownMenu_Initialize and UIDropDownMenu_AddButton then
    local frame = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    control = frame
    frame:SetPoint("LEFT", text, "LEFT", 205, -2)
    UIDropDownMenu_SetWidth(frame, 160)
    UIDropDownMenu_Initialize(frame, function()
      for _, v in ipairs(values) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = display(v)
        info.checked = get() == v
        info.func = function() pick(v) end
        UIDropDownMenu_AddButton(info)
      end
    end)
    update = function() UIDropDownMenu_SetText(frame, display(get())) end
    setEnabled = function(on)
      if on then UIDropDownMenu_EnableDropDown(frame) else UIDropDownMenu_DisableDropDown(frame) end
    end
  else
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    control = button
    button:SetSize(180, 24)
    button:SetPoint("LEFT", text, "LEFT", 220, 0)
    button:SetScript("OnClick", function()
      local cur, nextIndex = get(), 1
      for i, v in ipairs(values) do if v == cur then nextIndex = i % #values + 1 end end
      pick(values[nextIndex])
    end)
    update = function() button:SetText(display(get())) end
    setEnabled = function(on) button:SetEnabled(on) end
  end

  local anchorFrame = createAnchor(panel, text, (indent or 0) + 30, control)
  table.insert(panel.refreshers, function()
    update()
    local on = enabled == nil or enabled()
    setEnabled(on)
    text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
  end)
  return control, anchorFrame
end

-- Slider with value text: label left, slider right. Uses OptionsSliderTemplate where it exists, else a plain slider.
local function createSlider(panel, anchor, label, minV, maxV, step, get, set, format_, indent, enabled)
  local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (indent or 0) + 30, -16)
  text:SetText(label)
  local ok, s = pcall(CreateFrame, "Slider", nil, panel, "OptionsSliderTemplate")
  if not ok or not s then
    s = CreateFrame("Slider", nil, panel)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(16)
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetPoint("LEFT") s.bg:SetPoint("RIGHT") s.bg:SetHeight(4)
    s.bg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  end
  s:SetWidth(180)
  s:SetPoint("LEFT", text, "LEFT", 220, 0)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  -- the template's own captions (low/high/title) are not wanted
  for _, n in ipairs({"Low", "High", "Text"}) do if s[n] then s[n]:SetText("") end end
  local value = s:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  value:SetPoint("LEFT", s, "RIGHT", 10, 0)
  local updating
  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / step + 0.5) * step
    value:SetText(format_(v))
    if not updating then set(v) end
  end)
  local anchorFrame = createAnchor(panel, text, (indent or 0) + 30, s)
  table.insert(panel.refreshers, function()
    updating = true
    s:SetValue(get())
    value:SetText(format_(get()))
    updating = false
    local on = enabled == nil or enabled()
    s:SetEnabled(on)
    text:SetFontObject(on and "GameFontHighlight" or "GameFontDisable")
  end)
  return s, anchorFrame
end

local function createButton(panel, anchor, label, onClick, indent)
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(200, 24)
  b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", indent or 0, -12)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b, createAnchor(panel, b, indent, b)
end

----------------------------------------------------------------------
-- Main page: overview
----------------------------------------------------------------------

local function buildOverview()
  -- Icon and colour in the category list; plain title stays for headers and chat.
  local p = createPanel("|T" .. ns.Icons.Path(ns.Icons.bobber, 64) .. ":0|t " .. C.Paint("aqua", L["ADDON_NAME"]))
  local logo = p:CreateTexture(nil, "ARTWORK")
  logo:SetSize(128, 128)
  logo:SetPoint("TOPLEFT", PADDING, -PADDING)
  logo:SetTexture(ns.Icons.logoStacked)
  local info = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  info:SetPoint("LEFT", logo, "RIGHT", PADDING, 0)
  info:SetJustifyH("LEFT")
  local muted = "|cffada09a"
  info:SetText(format("%s%s|r %s\n%s%s|r %s", muted, L["Version"] .. ":", BJ:GetMeta("Version") or "?",
    muted, L["Author"] .. ":", BJ:GetMeta("Author") or "?"))
  local intro = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  intro:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -PADDING)
  intro:SetPoint("RIGHT", -PADDING, 0)
  intro:SetJustifyH("LEFT")
  intro:SetSpacing(3)
  intro:SetText(BJ:GetMeta("Notes") or "")
  local hint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
  hint:SetText(L["All settings are on the General page."])
  createButton(p, hint, L["Open the journal"], function() BJ.modules.Journal.Toggle() end)
  return p
end

----------------------------------------------------------------------
-- Subcategory: General
----------------------------------------------------------------------

local function buildGeneral(overviewName)
  local page = createPanel(L["General"], overviewName)
  local p = createScrollContent(page)
  local isForever = ns.Flavor.current == ns.Flavor.FOREVER
  local header = createHeader(p, L["General"], L["Settings apply to all characters of this account."])

  -- Display
  local displaySection = createSection(p, header, L["Display"])
  local _, after = createCheckbox(p, displaySection, L["Descriptions below the options"],
    L["Shows the grey explanation texts below the options. Off: the explanation appears as a tooltip instead."],
    descriptionsOn, function(v) BJ.settings.showDescriptions = v end)

  -- Casting
  local castSection = createSection(p, after, L["Casting"])
  local castOn = function() return cast().enabled end
  local _, a1 = createCheckbox(p, castSection, L["Cast the fishing rod by double click or key"],
    L["Casts the fishing rod when you press the key or click twice. Off by default because it takes over a mouse button."],
    castOn, function(v) cast().enabled = v end)
  local _, a2 = createChoice(p, a1, L["Modifier key"], MODIFIERS, function() return cast().modifier end,
    function(v) cast().modifier = v end, modifierName, 0, castOn)
  local _, a3 = createChoice(p, a2, L["Mouse button"], BUTTONS, function() return cast().button end,
    function(v) cast().button = v end, buttonName, 0, castOn)
  _, a3 = createSlider(p, a3, L["Double click speed"], 0.15, 0.8, 0.05,
    function() return cast().interval or 0.4 end, function(v) cast().interval = v end,
    function(v) return format("%.2f s", v) end, 0, castOn)
  if isForever then
    _, a3 = createCheckbox(p, a3, L["Put away weapons and equip the pole"],
      L["Remembers your weapons, equips the pole and puts the weapons back after 5 minutes or when you are attacked."],
      function() return cast().weaponSwap ~= false end, function(v) cast().weaponSwap = v end, 30, castOn)
  end
  _, a3 = createCheckbox(p, a3, L["Switch on fish tracking automatically"],
    L["Checks whether Find Fish is active in the minimap tracking and switches it on if not. Off: your own choice stays."],
    function() return BJ.settings.findFish == true end, function(v)
      BJ.settings.findFish = v
      if v and BJ.modules.FindFish then BJ.modules.FindFish.Check() end
    end)
  local keyNote = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  keyNote:SetPoint("TOPLEFT", a3, "BOTTOMLEFT", 0, -10)
  keyNote:SetPoint("RIGHT", p, "RIGHT", -PADDING, 0)
  keyNote:SetJustifyH("LEFT")
  table.insert(p.refreshers, function()
    local key = BJ.modules.Cast and BJ.modules.Cast.BoundKey()
    keyNote:SetText(format(L["Key binding: %s"], key or L["not set"]) .. "  -  " .. L["Set a key under Options > Key Bindings > AddOns."])
  end)

  -- Tooltip
  local tipSection = createSection(p, keyNote, L["Tooltips"])
  local tipOn = function() return tip().enabled ~= false end
  local _, t1 = createCheckbox(p, tipSection, L["Extend the Fishing tooltip"],
    L["Adds your fishing skill, buffs and zone figures to the tooltip of the Fishing spell."],
    tipOn, function(v) tip().enabled = v end)
  local _, t2 = createCheckbox(p, t1, L["Show the catches of the zone"], L["Lists what you caught in the current zone."],
    function() return tip().catches ~= false end, function(v) tip().catches = v end, 30, tipOn)
  local _, t3 = createCheckbox(p, t2, L["Show the counters of the zone"], L["Shows casts, catches and the catch rate of the current zone."],
    function() return tip().counters ~= false end, function(v) tip().counters = v end, 30, tipOn)
  local _, t3b = createCheckbox(p, t3, L["Show fishing data on items"],
    L["Adds where and how often you caught an item, with coordinates and average quantity, to its tooltip."],
    function() return tip().items ~= false end, function(v) tip().items = v end, 30)
  local DETAIL_MODES = {"key", "always"}
  local DETAIL_KEYS = {"SHIFT", "CTRL", "ALT"}
  local _, t3c = createChoice(p, t3b, L["Skill bar details"], DETAIL_MODES, function() return tip().barDetails or "key" end,
    function(v) tip().barDetails = v end, function(v) return v == "always" and L["Always"] or L["Only with key"] end, 30, tipOn)
  local _, t3d = createChoice(p, t3c, L["Key for details"], DETAIL_KEYS, function() return tip().barKey or "SHIFT" end,
    function(v) tip().barKey = v end, modifierName, 30,
    function() return tipOn() and (tip().barDetails or "key") == "key" end)
  local _, t4 = createCheckbox(p, t3d, L["Show junk catches"],
    L["Lists everything that is neither a crafting material, food nor openable (boots, cans) under Clean the waters. Junk is always recorded."],
    function() return tip().junk == true end, function(v) tip().junk = v end, 30, tipOn)

  -- Bobber display
  local bobberSection = createSection(p, t4, L["Bobber display"])
  local bobberOn = function() return bobber().enabled end
  local _, b1 = createCheckbox(p, bobberSection, L["Show the bobber display while fishing"],
    L["Shows a transparent display with the zone figures while you fish. It disappears when you move or enter combat."],
    bobberOn, function(v) bobber().enabled = v end)
  local _, b2 = createButton(p, b1, L["Edit position"], function() BJ.modules.Bobber.StartEdit() end, 30)
  local editHint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  editHint:SetPoint("TOPLEFT", b2, "BOTTOMLEFT", 0, -6)
  editHint:SetPoint("RIGHT", p, "RIGHT", -PADDING, 0)
  editHint:SetJustifyH("LEFT")
  editHint:SetText(L["Closes this window and opens Edit Mode, where you drag the display to its place."])

  -- Minimap
  local minimapSection = createSection(p, editHint, L["Minimap"])
  local _, m1 = createCheckbox(p, minimapSection, L["Show the minimap icon"], L["Shows the button on the minimap. The addon list entry stays."],
    function() return not (BJ.settings.minimap and BJ.settings.minimap.hide) end, function(v) BJ.modules.Broker.SetShown(v) end)

  -- Developer
  local devSection = createSection(p, m1, L["Developer"])
  local _, d1 = createCheckbox(p, devSection, L["Debug mode"], L["Shows the developer tools below. Debug lines are kept in a short list; /bob probe prints the state."],
    function() return BJ.settings.debug == true end, function(v) BJ.settings.debug = v end)
  local reset, d2 = createButton(p, d1, L["Delete all data"], function() StaticPopup_Show("BOBBERSJOURNAL_RESET") end, 30)
  local resetHint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  resetHint:SetPoint("TOPLEFT", d2, "BOTTOMLEFT", 0, -6)
  resetHint:SetPoint("RIGHT", p, "RIGHT", -PADDING, 0)
  resetHint:SetJustifyH("LEFT")
  resetHint:SetText(L["Deletes all recorded fishing data, bookmarks and the debug log. Settings stay."])
  table.insert(p.refreshers, function()
    local on = BJ.settings.debug == true
    reset:SetShown(on)
    resetHint:SetShown(on)
    d2:SetShown(on)
  end)
  p.last = resetHint
  return page
end

local function register()
  local overview = buildOverview()
  local general = buildGeneral(overview.name)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(overview, overview.name)
    Settings.RegisterAddOnCategory(cat)
    BJ.settingsSubcategory = Settings.RegisterCanvasLayoutSubcategory(cat, general, general.name)
    BJ.settingsCategory = cat
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(overview)
    InterfaceOptions_AddCategory(general)
  end
end

function BJ:OpenOptions()
  if InCombatLockdown() then BJ:Print(L["Not possible in combat."]) return end
  if Settings and Settings.OpenToCategory and BJ.settingsCategory then
    Settings.OpenToCategory((BJ.settingsSubcategory or BJ.settingsCategory):GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(ADDON)
  end
end

local m = BJ:RegisterModule("Options")
function m:OnEnable() BJ.Protected("options", register) end
