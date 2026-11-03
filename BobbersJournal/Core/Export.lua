local _, ns = ...
local BJ = ns.BJ
local L = BJ.L
-- Developer tool (/bob export): turns a list of item IDs into text that can be copied (Ctrl+C) and handed to the developer,
-- e.g. to build the static recipe database. Per item one line, tab separated:
--   itemID, name, ID and name of the spell the item uses, spell the item triggers (GetFirstTriggeredSpellForItem, Retail; for
--   recipe items this may be the recipe the item teaches), tooltip lines (separated by " | ").
-- With no IDs typed in, all vendor recipes the addon has saved are listed. Not tested in the game.
local Export = {}
ns.Export = Export

local frame

--- IDs from free text (separators: anything that is no digit); duplicates are dropped.
local function parseIDs(text)
  local ids, seen = {}, {}
  for n in (text or ""):gmatch("%d+") do
    local id = tonumber(n)
    if id and not seen[id] then seen[id] = true ids[#ids + 1] = id end
  end
  return ids
end

--- Item IDs of all vendor recipes saved so far.
local function savedRecipes()
  local ids, seen = {}, {}
  for _, npc in pairs(BJ.DB.raw.npcs or {}) do
    for itemID, cat in pairs(npc.items or {}) do
      if cat == "recipe" and not seen[itemID] then seen[itemID] = true ids[#ids + 1] = itemID end
    end
  end
  table.sort(ids)
  return ids
end

local function clean(text)
  text = BJ.Clean(text)
  return type(text) == "string" and (text:gsub("[\t\r\n]+", " ")) or ""
end

--- One line for an item; missing = true while the client has not loaded the item yet.
local function describe(itemID)
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
  local spellName, spellID
  if C_Item and C_Item.GetItemSpell then spellName, spellID = C_Item.GetItemSpell(itemID) end
  local triggered
  if C_Item and C_Item.GetFirstTriggeredSpellForItem then
    local ok, id = pcall(C_Item.GetFirstTriggeredSpellForItem, itemID, 1)
    if ok then triggered = id end
  end
  local lines, args = {}, {}
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if ok and type(data) == "table" then
      for i, line in ipairs(data.lines or {}) do
        local left, right = clean(line.leftText), clean(line.rightText)
        if left ~= "" then lines[#lines + 1] = right ~= "" and (left .. " " .. right) or left end
        -- the data behind a line (type and the values of its args): may hold the ID of the item the recipe makes
        local parts = {}
        for _, a in ipairs(line.args or {}) do
          local v = BJ.Clean(a.intVal) or BJ.Clean(a.stringVal) or BJ.Clean(a.floatVal)
          if v ~= nil then parts[#parts + 1] = tostring(BJ.Clean(a.field)) .. "=" .. clean(tostring(v)) end
        end
        if #parts > 0 then args[#args + 1] = format("L%d/t%s{%s}", i, tostring(BJ.Clean(line.type)), table.concat(parts, ",")) end
      end
    end
  end
  local missing = type(name) ~= "string" or #lines == 0
  if missing and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
  return format("%d\t%s\t%s\t%s\t%s\t%s", itemID, clean(name), tostring(spellID or ""), clean(spellName), tostring(triggered or ""), table.concat(lines, " | ") .. "\t" .. table.concat(args, " ")), missing
end

local function run(retry)
  if not frame then return end
  local ids = parseIDs(frame.input:GetText())
  if #ids == 0 then ids = savedRecipes() end
  local out, missing = {"itemID\tname\tspellID\tspell\ttriggeredSpellID\ttooltip\tlineData"}, 0
  for _, id in ipairs(ids) do
    local line, miss = describe(id)
    out[#out + 1] = line
    if miss then missing = missing + 1 end
  end
  frame.output:SetText(table.concat(out, "\n"))
  frame.status:SetText(format(L["%d items, %d not loaded yet"], #ids, missing))
  -- items the client had to load: one more pass a moment later
  if missing > 0 and not retry and C_Timer then C_Timer.After(1.5, function() BJ.Protected("export", run, true) end) end
end

local function create()
  frame = CreateFrame("Frame", "BobbersJournalExport", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(640, 460)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if frame.TitleText then frame.TitleText:SetText("Bobber's Journal - " .. L["Export"]) end
  table.insert(UISpecialFrames, "BobbersJournalExport")

  local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 14, -32)
  hint:SetPoint("RIGHT", -14, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText(L["Item IDs (any separator); empty = all saved vendor recipes. Then copy the result with Ctrl+C."])

  frame.input = CreateFrame("ScrollFrame", nil, frame, "InputScrollFrameTemplate")
  frame.input:SetPoint("TOPLEFT", 14, -62)
  frame.input:SetSize(600, 70)
  frame.input.EditBox:SetFontObject("ChatFontNormal")
  frame.input.EditBox:SetWidth(580)
  if frame.input.CharCount then frame.input.CharCount:Hide() end
  frame.input = frame.input.EditBox

  local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  button:SetSize(140, 24)
  button:SetPoint("TOPLEFT", 14, -142)
  button:SetText(L["Read items"])
  button:SetScript("OnClick", function() BJ.Protected("export", run) end)

  frame.status = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  frame.status:SetPoint("LEFT", button, "RIGHT", 10, 0)

  local box = CreateFrame("ScrollFrame", nil, frame, "InputScrollFrameTemplate")
  box:SetPoint("TOPLEFT", 14, -176)
  box:SetSize(600, 270)
  box.EditBox:SetFontObject("ChatFontNormal")
  box.EditBox:SetWidth(580)
  box.EditBox:SetMaxLetters(0)
  if box.CharCount then box.CharCount:Hide() end
  frame.output = box.EditBox
end

function Export.Open()
  if not frame then create() end
  frame:Show()
  BJ.Protected("export", run)
end
