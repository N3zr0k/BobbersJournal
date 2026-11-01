local _, ns = ...
local BJ = ns.BJ
local L = BJ.L
-- Journal window in the look of the Blizzard spell book (two pages, header, bookmark ribbon).
-- Left page: tabs + search + list. Right page: details of the selected entry.
-- Art: Retail book atlases when the client has them, otherwise the classic spell book page textures
-- (Interface\Spellbook\Spellbook-Page-1/2). Layout values are derived from Blizzard_SpellBookFrame.xml
-- (wow-ui-source); written for this addon, not copied.
local M = BJ:RegisterModule("Journal")

local WIDTH, HEIGHT = 940, 640
local ROWS, ROW_H = 14, 28
local CURL_W, CURL_H = 100, 103 -- page-curl animation (Blizzard uses 150x155 in its much larger window)
local TABS = {"fish", "junk", "zones", "vendors", "bookmarks"}
local TAB_ICON = {fish = "Fish", zones = "Zones", vendors = "Equipment", bookmarks = "Book"}
local TAB_TEXT = {fish = "Fish", junk = "Junk", zones = "Zones", vendors = "Vendors", bookmarks = "Bookmarks"}
-- Tabs without an icon of our own use a game icon.
local TAB_TEXTURE = {junk = "Interface\\Icons\\INV_Misc_Gear_01"}

local state = {tab = "fish", search = "", offset = 0, selected = nil}
local frame

local function hasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function itemName(id)
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if name then return name end
  if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
  return "[" .. id .. "]"
end

local function itemIcon(id)
  local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  return getInfo and select(5, getInfo(id)) or nil
end

-- Entry lists per tab: { kind, id, text, icon, sub }
local function buildEntries()
  local A, out = BJ.API, {}
  local function add(kind, id, text, icon, sub)
    local q = state.search
    if q ~= "" and not text:lower():find(q, 1, true) then return end
    out[#out + 1] = {kind = kind, id = id, text = text, icon = icon, sub = sub}
  end
  local tab = state.tab
  if tab == "fish" or tab == "junk" or tab == "bookmarks" then
    for _, f in ipairs(A.GetFishList()) do
      -- Junk has its own tab; the fish tab only lists what is no junk.
      local junk = A.IsJunk(f.itemID)
      if (tab == "fish" and not junk) or (tab == "junk" and junk) or (tab == "bookmarks" and A.IsBookmarked("fish", f.itemID)) then
        add("fish", f.itemID, itemName(f.itemID), itemIcon(f.itemID), f.caught)
      end
    end
  end
  if tab == "zones" or tab == "bookmarks" then
    for _, z in ipairs(A.GetZoneList()) do
      if tab == "zones" or A.IsBookmarked("zone", z.zone) then add("zone", z.zone, z.name, nil, z.catches) end
    end
  end
  table.sort(out, function(a, b) return a.text < b.text end)
  return out
end

local function detailLines(entry)
  local A, lines = BJ.API, {}
  if not entry then return {L["Select an entry on the left page."]} end
  if entry.kind == "fish" then
    lines[1] = format(L["Caught: %d"], A.GetCaught(entry.id))
    lines[2] = ""
    lines[3] = L["Where to catch it"]
    for _, z in ipairs(A.GetFishZones(entry.id)) do
      lines[#lines + 1] = format("%s  %d %%  (%d)", A.GetZoneName(z.zone), math.floor(z.chance * 100 + 0.5), z.drops)
    end
  else
    lines[1] = format(L["Catches: %d"], A.GetZoneCatches(entry.id))
    lines[2] = format(L["Fishing spots: %d"], #A.GetZoneSpots(entry.id))
  end
  return lines
end

-- Lines of the item's own game tooltip (name, type, flavour text, price ...), as the game delivers them.
-- C_TooltipInfo where the client has it, else a hidden tooltip of our own. Values that are secret count as missing.
local scanTip
local function blizzardItemLines(id)
  local out = {}
  local function add(left, right, r, g, b)
    left, right = BJ.Clean(left), BJ.Clean(right)
    if type(left) ~= "string" then left = nil end
    if type(right) ~= "string" then right = nil end
    if (left and left ~= "") or (right and right ~= "") then
      out[#out + 1] = {left = left, right = right, r = tonumber(BJ.Clean(r)) or 1, g = tonumber(BJ.Clean(g)) or 1, b = tonumber(BJ.Clean(b)) or 1}
    end
  end
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
    if ok and type(data) == "table" and type(data.lines) == "table" then
      for _, line in ipairs(data.lines) do
        local c = line.leftColor
        add(line.leftText, line.rightText, c and c.r, c and c.g, c and c.b)
      end
      return out
    end
  end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "BobbersJournalScanTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  if pcall(scanTip.SetItemByID, scanTip, id) then
    for i = 1, scanTip:NumLines() do
      local left, right = _G["BobbersJournalScanTipTextLeft" .. i], _G["BobbersJournalScanTipTextRight" .. i]
      local r, g, b = left and left:GetTextColor()
      add(left and left:GetText(), right and right:GetText(), r, g, b)
    end
  end
  return out
end

-- Printed look: dark brown ink instead of the game's light text; the game's own colours (item lines) are darkened so
-- they stay readable and recognisable on the parchment.
local SEPIA_LIGHT = {0.46, 0.32, 0.18}
local INK_TEXT, INK_HEAD = {0.20, 0.12, 0.06}, {0.06, 0.30, 0.30}
local function darken(r, g, b)
  local f = 0.55
  return r * f, g * f, b * f
end
local function colored(text, r, g, b)
  r, g, b = darken(r, g, b)
  return format("|cff%02x%02x%02x%s|r", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5, text)
end
local function plain(text) return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Rows of the right page: {text=..., right=...} or {header=...}; `beside` rows stand next to the big icon.
local BODY_X, BODY_W, ICON_SIZE, LINE_H = 40, 400, 96, 16
local PAGE_DY = 25 -- the content of the right page starts this far lower

local function detailRow(i)
  local row = frame.detailRows[i]
  if row then return row end
  local book = frame.book
  row = {}
  row.left = book:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.left:SetJustifyH("LEFT")
  row.right = book:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.right:SetJustifyH("RIGHT")
  for _, fs in ipairs({row.left, row.right}) do fs:SetShadowOffset(0, 0) fs:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3], 1) end
  row.rule = book:CreateTexture(nil, "ARTWORK")
  row.rule:SetColorTexture(INK_HEAD[1], INK_HEAD[2], INK_HEAD[3], 0.75)
  row.rule:SetHeight(1)
  frame.detailRows[i] = row
  return row
end

local function layoutDetail(rows, beside, hasIcon)
  local book = frame.book
  local y = hasIcon and -(80 + PAGE_DY + ICON_SIZE + 18) or -(130 + PAGE_DY + 12)
  local count = 0
  local besideY = -(80 + PAGE_DY + 30) -- next free spot beside the icon (rows there wrap, so heights are measured)
  for i, entry in ipairs(rows) do
    local row = detailRow(i)
    local x, top = BODY_X + (hasIcon and 0 or 24), y -- pages without a big icon (zone): counters a bit to the right
    if i <= beside then
      x = BODY_X + ICON_SIZE + 14
      top = besideY
    else
      if entry.header and i > 1 then y = y - 8 top = y end
    end
    local width = BODY_W - (x - BODY_X)
    row.left:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", book, "TOP", x, top)
    if entry.header then
      row.left:SetText(plain(entry.header))
      row.left:SetTextColor(INK_HEAD[1], INK_HEAD[2], INK_HEAD[3], 1)
    else
      row.left:SetText(entry.keep and (entry.text or "") or plain(entry.text))
      row.left:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3], 1)
    end
    row.left:SetWidth(entry.right and width * 0.62 or width)
    row.right:ClearAllPoints()
    row.right:SetPoint("TOPRIGHT", book, "TOP", BODY_X + BODY_W, top)
    row.right:SetText(plain(entry.right))
    row.left:Show() row.right:Show()
    row.rule:ClearAllPoints()
    if entry.header then
      row.rule:SetPoint("LEFT", row.left, "RIGHT", 8, 0)
      row.rule:SetPoint("RIGHT", book, "TOP", BODY_X + BODY_W, 0)
      row.rule:SetPoint("TOP", row.left, "TOP", 0, -8)
      row.rule:Show()
    else
      row.rule:Hide()
    end
    local h = math.max(LINE_H, row.left:GetStringHeight() or LINE_H, row.right:GetStringHeight() or LINE_H)
    if i <= beside then
      besideY = top - h - 2
      -- the rows below start under the icon or under the last row beside it, whichever is lower
      if i == beside then y = math.min(y, besideY - 10) end
    else
      y = top - h - (entry.header and 2 or 0)
    end
    count = i
  end
  for i = count + 1, #frame.detailRows do
    local row = frame.detailRows[i]
    row.left:Hide() row.right:Hide() row.rule:Hide()
  end
end

--- Builds the right page of an entry: title, icon and rows.
local function buildDetail(sel, fallbackLines)
  local rows, beside, title, color = {}, 0, nil, nil
  if sel and sel.kind == "fish" then
    local lines = blizzardItemLines(sel.id)
    if #lines > 0 then
      title, color = lines[1].left, {lines[1].r, lines[1].g, lines[1].b}
      for i = 2, #lines do
        local l = lines[i]
        -- Item type line (blue in the game, e.g. crafting material) keeps its colour, darkened; the rest is light sepia.
        local blue = l.b > l.r + 0.25 and l.b > l.g
        local text = l.left
        if text then
          if blue then text = colored(text, l.r, l.g, l.b)
          else text = colored(plain(text), SEPIA_LIGHT[1] / 0.55, SEPIA_LIGHT[2] / 0.55, SEPIA_LIGHT[3] / 0.55) end
        end
        rows[#rows + 1] = {text = text or "", right = l.right, keep = true}
      end
      beside = math.min(#rows, 5)
    end
    local T = BJ.modules.Tooltip
    if T and T.ItemLines then
      for _, l in ipairs(T.ItemLines(sel.id)) do
        if l.header then rows[#rows + 1] = {header = l.header}
        else rows[#rows + 1] = {text = l[1], right = l[2]} end
      end
    end
  end
  if #rows == 0 then
    for _, l in ipairs(fallbackLines) do rows[#rows + 1] = {text = l} end
  end
  return rows, beside, title, color
end

local function pageText()
  local n = state.entries and #state.entries or 0
  return format(L["Page %d/%d"], n > 0 and (state.page or 1) or 0, n)
end

local function selectTabs()
  for _, tab in ipairs(frame.tabs) do tab:Select(tab.key == state.tab) end
end

-- Corner page-curl of the book (flip book animation like the spell book): curls while the mouse is on a paging
-- button, plays once when a page is turned.
local function curl(reverse)
  if frame.curl then frame.curl.anim:Play(reverse and true or false) end
end

local function turn(delta)
  local n = state.entries and #state.entries or 0
  if n == 0 then return end
  state.page = math.min(math.max((state.page or 1) + delta, 1), n)
  state.selected = state.entries[state.page]
  if PlaySound and SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
  curl(false)
  M.Refresh()
end

local function refresh()
  if not (frame and frame:IsShown()) then return end
  local entries = state.tab == "vendors" and {} or buildEntries()
  state.entries = entries
  -- Every entry has its own page: the selected entry decides the page number.
  state.page = nil
  if state.selected then
    for i, e in ipairs(entries) do
      if e.kind == state.selected.kind and e.id == state.selected.id then state.page = i state.selected = e break end
    end
    if not state.page then state.selected = nil end
  end
  -- Visible list rows: the entries; under a selected zone its fish are unfolded (accordion, one zone at a time).
  local map = BJ.modules.ZoneMap
  local visible, selIndex = {}, nil
  for _, e in ipairs(entries) do
    visible[#visible + 1] = e
    if state.selected and state.selected.kind == "zone" and e.kind == "zone" and e.id == state.selected.id then
      selIndex = #visible
      if map then map.SetZone(e.id) end
      for _, f in ipairs(BJ.API.GetZoneFish(e.id)) do
        if not BJ.API.IsJunk(f.itemID) then
          visible[#visible + 1] = {kind = "zonefish", id = f.itemID, text = itemName(f.itemID), icon = itemIcon(f.itemID),
            sub = format("%d %%", math.floor(f.chance * 100 + 0.5)), zone = e.id}
        end
      end
    end
  end
  if state.selected and not selIndex then
    for i, e in ipairs(visible) do if e.kind == state.selected.kind and e.id == state.selected.id then selIndex = i break end end
  end
  -- keep the selected entry visible
  if selIndex then
    if selIndex <= state.offset then state.offset = selIndex - 1
    elseif selIndex > state.offset + ROWS then state.offset = selIndex - ROWS end
  end
  local maxOffset = math.max(#visible - ROWS, 0)
  state.offset = math.max(math.min(state.offset, maxOffset), 0)

  for i, row in ipairs(frame.rows) do
    local e = visible[state.offset + i]
    row.entry = e
    if e then
      local fishRow = e.kind == "zonefish"
      local on = fishRow and map and map.IsSelected(e.id)
      row.text:SetText(e.text)
      row.text:ClearAllPoints()
      row.icon:ClearAllPoints()
      row.icon:SetShown(not fishRow)
      row.stamp:SetShown(fishRow)
      row.ring:SetShown(fishRow)
      if fishRow then
        -- ink stamp: round, dark and slightly transparent; chosen fish stay in colour
        row.stamp:SetTexture(e.icon)
        row.stamp:SetDesaturated(not on)
        if on then row.stamp:SetVertexColor(1, 1, 1) row.stamp:SetAlpha(1) else row.stamp:SetVertexColor(0.30, 0.28, 0.26) row.stamp:SetAlpha(0.85) end
        row.ring:SetVertexColor(0.04, 0.03, 0.03)
        row.ring:SetAlpha(on and 1 or 0.8)
        row.text:SetPoint("LEFT", row, "LEFT", 62, 0)
        row.text:SetFontObject(on and "GameFontHighlight" or "GameFontNormalSmall")
      else
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.icon:SetTexture(e.icon)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetFontObject("GameFontNormal")
      end
      row.sub:SetText(e.sub or "")
      row.mark:SetShown(not fishRow and BJ.API.IsBookmarked(e.kind, e.id))
      row.sel:SetShown(state.selected and state.selected.kind == e.kind and state.selected.id == e.id or (on and true or false))
      row:Show()
    else
      row:Hide()
    end
  end

  local lines
  if state.tab == "vendors" then
    lines = {L["Vendors are not available yet."]}
  elseif #entries == 0 and state.search == "" and state.tab ~= "bookmarks" then
    lines = {L["No data yet. Go fishing!"]}
  else
    lines = detailLines(state.selected)
  end
  local sel = state.selected
  local rows, beside, title, color = buildDetail(sel, lines)
  local hasIcon = sel ~= nil and sel.icon ~= nil
  -- Nothing selected: one larger message in the middle of the right page instead of rows.
  local empty = sel == nil
  frame.emptyText:SetShown(empty)
  if empty then frame.emptyText:SetText(lines[1] or "") rows = {} end
  layoutDetail(rows, beside, hasIcon)
  -- Zone page: map with the fishing spots below the counters.
  local map = BJ.modules.ZoneMap
  if map then
    if sel and sel.kind == "zone" and state.tab ~= "vendors" then
      BJ.Protected("zone map", function() map.Show(frame.book, sel.id, -(130 + PAGE_DY + 12 + #rows * LINE_H + 14)) end)
    else
      map.Hide()
    end
  end
  frame.bookmark:SetShown(sel ~= nil and state.tab ~= "vendors")
  frame.title:ClearAllPoints()
  if sel then
    frame.bookmark:SetText(BJ.API.IsBookmarked(sel.kind, sel.id) and L["Remove bookmark"] or L["Add bookmark"])
    frame.title:SetText(title or sel.text)
    local c = INK_TEXT -- same colour as the title of the zone pages
    frame.title:SetTextColor(c[1], c[2], c[3])
    frame.title:SetShadowOffset(0, 0)
    frame.pageIcon:SetTexture(sel.icon)
    frame.pageIcon:SetShown(hasIcon)
    if hasIcon then frame.title:SetPoint("TOPLEFT", frame.pageIcon, "TOPRIGHT", 14, -2)
    else frame.title:SetPoint("TOPLEFT", frame.book, "TOP", BODY_X + 24, -(85 + PAGE_DY + 12)) end
  else
    frame.title:SetText("")
    frame.pageIcon:Hide()
    frame.title:SetPoint("TOPLEFT", frame.book, "TOP", BODY_X, -(85 + PAGE_DY))
  end
  selectTabs()
  frame.pageText:SetText(pageText())
  local n = #entries
  frame.prev:SetEnabled(n > 0 and (state.page or 1) > 1)
  frame.next:SetEnabled(n > 0 and (state.page or 0) < n)
end
M.Refresh = refresh

local function setTab(key)
  state.tab, state.offset, state.selected = key, 0, nil
  refresh()
end

local function createRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(380, ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  row.sel:SetColorTexture(ns.Colors.aqua[1], ns.Colors.aqua[2], ns.Colors.aqua[3], 0.25)
  row.sel:Hide()
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(22, 22)
  row.icon:SetPoint("LEFT", 4, 0)
  -- round stamp for the fish unfolded under a zone
  row.stamp = row:CreateTexture(nil, "ARTWORK")
  row.stamp:SetSize(22, 22)
  row.stamp:SetPoint("LEFT", 32, 0)
  local mask = row:CreateMaskTexture()
  mask:SetAllPoints(row.stamp) mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  row.stamp:AddMaskTexture(mask)
  row.ring = row:CreateTexture(nil, "OVERLAY")
  row.ring:SetAllPoints(row.stamp)
  row.ring:SetTexture(ns.Icons.ringStamp)
  row.stamp:Hide() row.ring:Hide()
  row.text = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.text:SetJustifyH("LEFT")
  row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.sub:SetPoint("RIGHT", -26, 0)
  row.mark = row:CreateTexture(nil, "OVERLAY")
  row.mark:SetSize(16, 16)
  row.mark:SetPoint("RIGHT", -4, 0)
  row.mark:SetTexture("Interface\\COMMON\\ReputationStar")
  row.mark:SetTexCoord(0, 0.5, 0, 0.5)
  row:SetScript("OnClick", function(self)
    if self.entry and self.entry.kind == "zonefish" then
      -- fish under a zone: choose any number, they filter the spots on the map
      local map = BJ.modules.ZoneMap
      if map then map.Toggle(self.entry.id) end
      refresh()
    elseif self.entry then
      state.selected = self.entry
      if PlaySound and SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
      curl(false)
      refresh()
    end
  end)
  -- Fish rows show the item tooltip (our own section is appended by the Tooltip module).
  row:SetScript("OnEnter", function(self)
    if self.entry and (self.entry.kind == "fish" or self.entry.kind == "zonefish") then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(self.entry.id)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

-- Header strip and pages of the book as in the spell book; falls back to the classic page textures.
local function createBook(parent)
  local book = CreateFrame("Frame", nil, parent)
  book:SetPoint("TOPLEFT", 0, -23)
  book:SetPoint("BOTTOMRIGHT", -6, 4)
  local left, right = book:CreateTexture(nil, "BACKGROUND", nil, 1), book:CreateTexture(nil, "BACKGROUND", nil, 1)
  left:SetPoint("TOPLEFT", 0, -51) left:SetPoint("BOTTOMRIGHT", book, "BOTTOM")
  right:SetPoint("TOPLEFT", book, "TOP", 0, -51) right:SetPoint("BOTTOMRIGHT")
  if hasAtlas("spellbook-background-evergreen-left") then
    left:SetAtlas("spellbook-background-evergreen-left") right:SetAtlas("spellbook-background-evergreen-right")
  else
    left:SetTexture("Interface\\Spellbook\\Spellbook-Page-1") right:SetTexture("Interface\\Spellbook\\Spellbook-Page-2")
  end
  local top = book:CreateTexture(nil, "BACKGROUND", nil, 1)
  top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(54)
  if hasAtlas("spellbook-background-evergreen-header") then top:SetAtlas("spellbook-background-evergreen-header")
  else top:SetColorTexture(0.12, 0.08, 0.05, 1) end
  if hasAtlas("spellbook-background-evergreen-ribbon") then
    local ribbon = book:CreateTexture(nil, "BACKGROUND", nil, 2)
    ribbon:SetAtlas("spellbook-background-evergreen-ribbon", true)
    ribbon:SetPoint("TOPRIGHT", left, "TOPRIGHT", 62, 0)
  end
  if hasAtlas("spellbook-corner-flipbook-evergreen") and book.CreateAnimationGroup then
    local tex = book:CreateTexture(nil, "BACKGROUND", nil, 2)
    tex:SetAtlas("spellbook-corner-flipbook-evergreen", false)
    tex:SetSize(CURL_W, CURL_H)
    tex:SetPoint("BOTTOMRIGHT", book, "BOTTOMRIGHT", -6, 4) -- the page corner of the right page
    local group = tex:CreateAnimationGroup()
    local flip = group:CreateAnimation("FlipBook")
    flip:SetFlipBookRows(2) flip:SetFlipBookColumns(4) flip:SetFlipBookFrames(8)
    flip:SetDuration(0.25) flip:SetSmoothing("NONE")
    group:SetLooping("NONE")
    group:Play() group:Pause() -- rests on the first frame
    parent.curl = {tex = tex, anim = group}
  end
  return book
end

-- Frame tabs below the book. Own simple tabs instead of Blizzard's tab templates: those have a fixed height, and the
-- icon (48 px) is the tab's content. Selected tab: aqua border; the name is a tooltip.
local TAB_W, TAB_H, TAB_ICON_SIZE = 64, 56, 48

local function createTab(parent, key, i)
  local tab = CreateFrame("Button", nil, parent)
  tab.key = key
  tab:SetSize(TAB_W, TAB_H)
  tab.border = tab:CreateTexture(nil, "BACKGROUND")
  tab.border:SetAllPoints()
  tab.back = tab:CreateTexture(nil, "BACKGROUND", nil, 1)
  tab.back:SetPoint("TOPLEFT", 1, -1) tab.back:SetPoint("BOTTOMRIGHT", -1, 1)
  tab.back:SetColorTexture(0.10, 0.10, 0.12, 0.95)
  tab.icon = tab:CreateTexture(nil, "ARTWORK")
  tab.icon:SetSize(TAB_ICON_SIZE, TAB_ICON_SIZE)
  tab.icon:SetPoint("CENTER", 0, -2)
  tab.icon:SetTexture(TAB_TEXTURE[key] or ns.Icons.Path(TAB_ICON[key], 128))
  tab:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
  tab:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
  function tab.Select(self, selected)
    local c = selected and ns.Colors.aqua or {0.35, 0.35, 0.38}
    self.border:SetColorTexture(c[1], c[2], c[3], 1)
    self.icon:SetAlpha(selected and 1 or 0.75)
  end
  tab:Select(false)
  if i == 1 then tab:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 22, 2)
  else tab:SetPoint("LEFT", parent.tabs[i - 1], "RIGHT", 4, 0) end
  tab:SetScript("OnClick", function() setTab(key) end)
  tab:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L[TAB_TEXT[key]])
    GameTooltip:Show()
  end)
  tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return tab
end

local function pagingButton(parent, name, direction)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(32, 32)
  b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "-Up")
  b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "-Down")
  b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "-Disabled")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetScript("OnClick", function() turn(direction) end)
  b:SetScript("OnEnter", function() curl(false) end)
  b:SetScript("OnLeave", function() curl(true) end)
  return b
end

local function createFrame()
  local ok
  ok, frame = pcall(CreateFrame, "Frame", "BobbersJournalFrame", UIParent, "PortraitFrameTemplate")
  local framed = ok
  if not ok then frame = CreateFrame("Frame", "BobbersJournalFrame", UIParent) end
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  if framed then
    -- Title bar and portrait of the standard panel frame, like the spell book window.
    if frame.SetTitle then frame:SetTitle(ns.Colors.Paint("aqua", L["ADDON_NAME"])) end
    pcall(function()
      local book = ns.Icons.Path(ns.Icons.book, 128)
      if frame.SetPortraitTextureRaw then frame:SetPortraitTextureRaw(book)
      elseif frame.SetPortraitToAsset then frame:SetPortraitToAsset(book) end
    end)
    -- The logo is transparent: a black disc behind it, cut to the round portrait like the portrait itself.
    pcall(function()
      local holder = frame.PortraitContainer or frame
      local portrait = holder.portrait or frame.portrait
      if not portrait then return end
      local disc = holder:CreateTexture(nil, "BACKGROUND", nil, 7)
      disc:SetAllPoints(portrait)
      disc:SetColorTexture(0, 0, 0, 1)
      local mask = holder:CreateMaskTexture()
      mask:SetAllPoints(portrait)
      mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      disc:AddMaskTexture(mask)
      -- The book itself is drawn smaller than the portrait so the ring does not cut it off.
      portrait:SetAlpha(0)
      local icon = holder:CreateTexture(nil, "ARTWORK", nil, 2)
      icon:SetPoint("CENTER", portrait, "CENTER", 0, 0)
      local size = (portrait:GetWidth() or 60) * 0.80
      icon:SetSize(size, size)
      icon:SetTexture(ns.Icons.Path(ns.Icons.book, 128))
    end)
    if frame.Bg then frame.Bg:Hide() end
    if frame.Inset then frame.Inset:Hide() end
  else
    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(34, 34)
    logo:SetPoint("TOPLEFT", 20, -9)
    logo:SetTexture(ns.Icons.Path(ns.Icons.book, 64))
    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    title:SetText(L["ADDON_NAME"])
    title:SetTextColor(unpack(ns.Colors.sand))
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end

  local book = createBook(frame)
  frame.book = book
  frame.tabs = {}
  for i, key in ipairs(TABS) do
    frame.tabs[i] = createTab(frame, key, i)
  end

  -- Search: centred in the brown header strip of the book.
  local searchOk, box = pcall(CreateFrame, "EditBox", nil, book, "SearchBoxTemplate")
  if not searchOk then box = CreateFrame("EditBox", nil, book, "InputBoxTemplate") end
  box:SetSize(300, 30)
  box:SetPoint("TOP", book, "TOP", 0, -12)
  box:SetAutoFocus(false)
  -- HookScript, not SetScript: the search box template's own handler hides its "Search" hint text.
  box:HookScript("OnTextChanged", function(self)
    if self.GetText then state.search = (self:GetText() or ""):lower() end
    state.offset = 0
    refresh()
  end)
  box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
  frame.search = box

  frame.list = CreateFrame("Frame", nil, book)
  frame.list:SetSize(400, ROWS * ROW_H)
  frame.list:SetPoint("TOPLEFT", 40, -80)
  frame.list:EnableMouseWheel(true)
  frame.list:SetScript("OnMouseWheel", function(_, delta)
    state.offset = math.max(state.offset - delta * 3, 0)
    refresh()
  end)
  frame.rows = {}
  for i = 1, ROWS do frame.rows[i] = createRow(frame.list, i) end

  frame.emptyText = book:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  frame.emptyText:SetPoint("CENTER", book, "TOP", 240, -330)
  frame.emptyText:SetWidth(380)
  frame.emptyText:SetJustifyH("CENTER")
  frame.emptyText:SetShadowOffset(0, 0)
  frame.emptyText:SetTextColor(INK_TEXT[1], INK_TEXT[2], INK_TEXT[3], 0.85)
  frame.pageIcon = book:CreateTexture(nil, "ARTWORK")
  frame.pageIcon:SetSize(ICON_SIZE, ICON_SIZE)
  frame.pageIcon:SetPoint("TOPLEFT", book, "TOP", BODY_X, -(80 + PAGE_DY))
  -- Painted on the parchment: no colour, brown/sepia like the dark parts of the paper, half transparent, and the
  -- edge fades out through a soft mask (own mask texture, Media\\Mask_Soft_128).
  frame.pageIcon:SetDesaturated(true)
  frame.pageIcon:SetVertexColor(0.50, 0.34, 0.18)
  frame.pageIcon:SetAlpha(0.8)
  local fade = book:CreateMaskTexture()
  fade:SetAllPoints(frame.pageIcon)
  fade:SetTexture(ns.Icons.maskSoft, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  frame.pageIcon:AddMaskTexture(fade)
  frame.title = book:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  frame.title:SetJustifyH("LEFT")
  frame.title:SetWidth(BODY_W - ICON_SIZE - 14)
  frame.detailRows = {}

  frame.bookmark = CreateFrame("Button", nil, book, "UIPanelButtonTemplate")
  frame.bookmark:SetSize(160, 24)
  frame.bookmark:SetPoint("BOTTOMLEFT", book, "BOTTOM", 40, 40)
  frame.bookmark:SetScript("OnClick", function()
    local s = state.selected
    if s then BJ.API.SetBookmark(s.kind, s.id, not BJ.API.IsBookmarked(s.kind, s.id)) end
  end)

  -- Paging: one page per entry; "Page n/N" with arrows at the bottom right, as in the spell book.
  frame.next = pagingButton(book, "NextPage", 1)
  frame.next:SetPoint("BOTTOMRIGHT", -70, 36)
  frame.prev = pagingButton(book, "PrevPage", -1)
  frame.prev:SetPoint("RIGHT", frame.next, "LEFT", -4, 0)
  frame.pageText = book:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  frame.pageText:SetPoint("RIGHT", frame.prev, "LEFT", -8, 0)

  frame:SetScript("OnShow", refresh)
  -- ESC closes the window like other panels
  if UISpecialWindows then tinsert(UISpecialWindows, "BobbersJournalFrame") end
end

function M.Toggle()
  if not frame then createFrame() end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

function M:OnEnable()
  -- Redraw on new data, bookmark changes and when item names arrive; no OnUpdate needed.
  BJ:Listen(function() refresh() end)
  BJ:RegisterEvent("GET_ITEM_INFO_RECEIVED", "journal", function() if frame and frame:IsShown() then refresh() end end)
end
