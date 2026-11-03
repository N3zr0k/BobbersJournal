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
local cast, tip, bobber, skillBar = section("cast"), section("tooltip"), section("bobber"), section("skillBar")
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

  local control, update, setEnabled = BJ.Menu.Choice(panel, {width = 180, values = values, get = get, pick = pick, display = display})
  control:SetPoint("LEFT", text, "LEFT", control:GetObjectType() == "Frame" and 205 or 220, control:GetObjectType() == "Frame" and -2 or 0)

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
  local _, t3b2 = createCheckbox(p, t3b, L["Show income per hour on fish"],
    L["Adds the fish caught per hour and what they are worth per hour to a fish tooltip: sold to a vendor and, with Auctionator or TradeSkillMaster, at the auction house."],
    function() return tip().income ~= false end, function(v) tip().income = v end, 30)
  local DETAIL_MODES = {"key", "always"}
  local DETAIL_KEYS = {"SHIFT", "CTRL", "ALT"}
  local _, t3c = createChoice(p, t3b2, L["Skill bar details"], DETAIL_MODES, function() return tip().barDetails or "key" end,
    function(v) tip().barDetails = v end, function(v) return v == "always" and L["Always"] or L["Only with key"] end, 30, tipOn)
  local _, t3d = createChoice(p, t3c, L["Key for details"], DETAIL_KEYS, function() return tip().barKey or "SHIFT" end,
    function(v) tip().barKey = v end, modifierName, 30,
    function() return tipOn() and (tip().barDetails or "key") == "key" end)
  local _, t4 = createCheckbox(p, t3d, L["Show junk catches"],
    L["Lists everything that is neither a crafting material, food nor openable (boots, cans) under Clean the waters. Junk is always recorded."],
    function() return tip().junk == true end, function(v) tip().junk = v end, 30, tipOn)

  -- Minimap
  local minimapSection = createSection(p, t4, L["Minimap"])
  local _, m1 = createCheckbox(p, minimapSection, L["Show the minimap icon"], L["Shows the button on the minimap. The addon list entry stays."],
    function() return not (BJ.settings.minimap and BJ.settings.minimap.hide) end, function(v) BJ.modules.Broker.SetShown(v) end)
  local _, m2 = createCheckbox(p, m1, L["Switch on fish tracking automatically"],
    L["Checks whether Find Fish is active in the minimap tracking and switches it on if not. Off: your own choice stays."],
    function() return BJ.settings.findFish == true end, function(v)
      BJ.settings.findFish = v
      if v and BJ.modules.FindFish then BJ.modules.FindFish.Check() end
    end)

  local _, mp = createCheckbox(p, m2, L["Show vendors and teachers on the maps"],
    L["Shows the saved fishing teachers and vendors on the world map and the minimap. Teacher and vendor with an aqua ring."],
    function() return BJ.settings.npcPins == true end, function(v)
      BJ.settings.npcPins = v
      if BJ.modules.Pins then BJ.modules.Pins.Refresh() end
    end)

  local _, m3, m4
  if ns.Flavor.current == ns.Flavor.RETAIL then
    _, m4 = createCheckbox(p, mp, L["Show my fish list on the Classic page"],
      L["Fills the empty Classic Fishing page of the game's fishing journal with your fish list (common and uncommon fish). Takes effect when the journal is opened again."],
      function() return BJ.settings.diaryList == true end, function(v) BJ.settings.diaryList = v end)
    _, m3 = createCheckbox(p, m4, L["Add my data to the fishing journal"],
      L["Adds your catches and the zones with catch chance below the description of a fish in the game's fishing journal."],
      function() return BJ.settings.diary == true end, function(v)
        BJ.settings.diary = v
        if BJ.modules.Diary then BJ.modules.Diary.Refresh() end
      end)
  end

  -- Developer
  local devSection = createSection(p, m3 or mp, L["Developer"])
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

----------------------------------------------------------------------
-- Subcategory: Bobber
----------------------------------------------------------------------

local function buildBobber(overviewName)
  local page = createPanel(L["Bobber"], overviewName)
  local p = createScrollContent(page)
  local header = createHeader(p, L["Bobber"], L["Settings apply to all characters of this account."])
  -- Bobber display
  local bobberSection = createSection(p, header, L["Bobber display"])
  local bobberOn = function() return bobber().enabled end
  local _, b1 = createCheckbox(p, bobberSection, L["Show the bobber display while fishing"],
    L["Shows a transparent display with the zone figures while you fish. It disappears when you move or enter combat."],
    bobberOn, function(v) bobber().enabled = v if BJ.modules.Bobber then BJ.modules.Bobber.Refresh() end end)
  local _, b1b = createCheckbox(p, b1, L["Hide catches and junk in the display"],
    L["The bobber display then shows the skill bar only, without the lists of caught fish and junk. The tooltip of the Fishing spell keeps them."],
    function() return bobber().hideCatches == true end, function(v) bobber().hideCatches = v end, 30, bobberOn)
  local _, b2 = createButton(p, b1b, L["Edit position"], function() BJ.modules.Bobber.StartEdit() end, 30)
  local editHint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  editHint:SetPoint("TOPLEFT", b2, "BOTTOMLEFT", 0, -6)
  editHint:SetPoint("RIGHT", p, "RIGHT", -PADDING, 0)
  editHint:SetJustifyH("LEFT")
  editHint:SetText(L["Closes this window and opens Edit Mode, where you drag the display to its place."])


  -- Fishing skill bar like the experience bar
  local skillSection = createSection(p, editHint, L["Skill bar"])
  local _, s1 = createCheckbox(p, skillSection, L["Show the fishing skill as a bar"],
    L["Shows the fishing skill like the experience and reputation bar, in the colour of the addon. By default it sits above the experience bars."],
    function() return skillBar().enabled == true end,
    function(v) skillBar().enabled = v if BJ.modules.SkillBar then BJ.modules.SkillBar.Refresh() end end)
  local _, s1b = createCheckbox(p, s1, L["Hide the bar at the maximum skill"],
    L["Hides the skill bar once the skill of the current area is at its maximum. The tooltip still shows it."],
    function() return skillBar().hideAtMax == true end,
    function(v) skillBar().hideAtMax = v if BJ.modules.SkillBar then BJ.modules.SkillBar.Refresh() end end,
    30, function() return skillBar().enabled == true end)
  local _, s2 = createButton(p, s1b, L["Edit position"], function() BJ.modules.SkillBar.StartEdit() end, 30)
  editHint = s2

  -- The oversized bobber: toy (Retail) or item in the bags (Retail and Forever)
  local toySection = createSection(p, editHint, L["Oversized bobber"])
  local _, t1 = createCheckbox(p, toySection, L["Always use the oversized bobber toy"],
    L["If you own the toy Reusable Oversized Bobber, or have the item in your bags, the click that casts uses it first when its effect is not active. Needs Casting to be on."],
    function() return cast().bobberToy == true end, function(v) cast().bobberToy = v end)
  local last = t1
  p.last = last
  return page
end

----------------------------------------------------------------------
-- Subcategory: Lures
----------------------------------------------------------------------

local function buildLures(overviewName)
  local page = createPanel(L["Lures"], overviewName)
  local p = createScrollContent(page)
  local header = createHeader(p, L["Lures"], L["Settings apply to all characters of this account."])

  -- Favourite lure: bag slot look; drag a lure onto it, right click removes it, mouse over shows the tooltip,
  -- the dropdown lists the lures in the bags.
  local favSection = createSection(p, header, L["Favorite lure"])
  local slot = CreateFrame("Button", nil, p)
  slot:SetSize(48, 48)
  slot:SetPoint("TOPLEFT", favSection, "BOTTOMLEFT", 0, -10)
  slot.back = slot:CreateTexture(nil, "BACKGROUND")
  slot.back:SetAllPoints()
  if BJ.HasAtlas("bags-item-slot64") then slot.back:SetAtlas("bags-item-slot64")
  else slot.back:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled") slot.back:SetTexCoord(0.15, 0.85, 0.15, 0.85) end
  slot.icon = slot:CreateTexture(nil, "ARTWORK")
  slot.icon:SetPoint("TOPLEFT", 3, -3) slot.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- grey frame like the bag slots
  slot.frameTex = slot:CreateTexture(nil, "OVERLAY")
  slot.frameTex:SetPoint("TOPLEFT", -5, 5) slot.frameTex:SetPoint("BOTTOMRIGHT", 5, -5)
  if BJ.HasAtlas("collections-itemborder-collected") then slot.frameTex:SetAtlas("collections-itemborder-collected")
  else slot.frameTex:SetTexture("Interface\\Common\\WhiteIconFrame") end
  local gray = BAG_ITEM_QUALITY_COLORS and BAG_ITEM_QUALITY_COLORS[1] or COMMON_GRAY_COLOR
  if gray and gray.GetRGB then slot.frameTex:SetVertexColor(gray:GetRGB()) else slot.frameTex:SetVertexColor(0.62, 0.62, 0.62) end
  slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  slot:RegisterForDrag("LeftButton")
  local favName = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  favName:SetPoint("LEFT", slot, "RIGHT", 12, 0)

  local function setFavorite(id)
    cast().favoriteLure = id
    refresh(page)
    if BJ.modules.Journal and BJ.modules.Journal.Refresh then BJ.modules.Journal.Refresh() end
  end
  local function drop()
    local kind, id = GetCursorInfo()
    if kind ~= "item" then return false end
    if ns.Lures and ns.Lures.IsLure(id) then
      setFavorite(id)
      ClearCursor()
    else
      BJ:Print(L["This item is not a fishing lure."])
    end
    return true
  end
  slot:SetScript("OnReceiveDrag", drop)
  slot:SetScript("OnEnter", function(self)
    local id = cast().favoriteLure
    if id then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetItemByID(id) GameTooltip:Show() end
  end)
  slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Dropdown with the lures in the bags
  local function bagLures()
    local list = {}
    for id, info in pairs(ns.Lures and ns.Lures.BagCounts() or {}) do
      local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("[" .. id .. "]")
      list[#list + 1] = {id = id, text = format("%s  x%d", name, info.count)}
    end
    table.sort(list, function(x, y) return x.text < y.text end)
    return list
  end
  -- Left click on the slot opens the list of the lures in the bags
  local function openLureMenu(owner)
    local items = {}
    for _, v in ipairs(bagLures()) do
      items[#items + 1] = {text = v.text, checked = function() return cast().favoriteLure == v.id end, func = function() setFavorite(v.id) end}
    end
    if #items == 0 then items[1] = {text = L["No lures in your bags"], disabled = true} end
    BJ.Menu.Popup(owner, L["Lures in your bags"], items)
  end
  slot:SetScript("OnClick", function(self, button)
    if drop() then return end
    if button == "RightButton" then setFavorite(nil) else openLureMenu(self) end
  end)
  local ddAnchor = slot
  table.insert(p.refreshers, function()
    local id = cast().favoriteLure
    if id then
      local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
      slot.icon:SetTexture(getInfo and select(5, getInfo(id)) or nil)
      favName:SetText((C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("[" .. id .. "]"))
    else
      slot.icon:SetTexture(nil)
      favName:SetText(L["No favorite lure set"])
    end
  end)
  local favHint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  favHint:SetPoint("TOPLEFT", ddAnchor, "BOTTOMLEFT", 0, -6)
  favHint:SetPoint("RIGHT", p, "RIGHT", -PADDING, 0)
  favHint:SetJustifyH("LEFT")
  favHint:SetText(L["Left click opens the lures in your bags, or drag a lure onto the field. Right click removes it."])

  -- Automatic lures
  local autoSection = createSection(p, favHint, L["Automatic lures"])
  local castOn = function() return cast().enabled end
  local _, a1 = createCheckbox(p, autoSection, L["Apply lures automatically"],
    L["If the pole has no lure, the next click applies a lure from your bags (the favorite first); the click after that casts. Needs Casting to be on."],
    function() return cast().autoLure == true end, function(v) cast().autoLure = v end, 0, castOn)
  local _, a2 = createCheckbox(p, a1, L["Best lure as fallback"],
    L["Without a favorite, or when it is not in your bags, the lure with the highest fishing bonus in your bags is used. Off: only the favorite is used."],
    function() return cast().autoBest ~= false end, function(v) cast().autoBest = v end, 30,
    function() return cast().enabled and cast().autoLure == true end)
  p.last = a2
  return page
end

local function register()
  local overview = buildOverview()
  local general = buildGeneral(overview.name)
  local bobberPage = buildBobber(overview.name)
  local lures = buildLures(overview.name)
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(overview, overview.name)
    Settings.RegisterAddOnCategory(cat)
    BJ.settingsSubcategory = Settings.RegisterCanvasLayoutSubcategory(cat, general, general.name)
    Settings.RegisterCanvasLayoutSubcategory(cat, bobberPage, bobberPage.name)
    Settings.RegisterCanvasLayoutSubcategory(cat, lures, lures.name)
    BJ.settingsCategory = cat
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(overview)
    InterfaceOptions_AddCategory(general)
    InterfaceOptions_AddCategory(bobberPage)
    InterfaceOptions_AddCategory(lures)
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
