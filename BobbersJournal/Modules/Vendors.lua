local _, ns = ...
local BJ, Flavor = ns.BJ, ns.Flavor
local L = BJ.L
-- Collects the vendors and teachers: when a merchant window opens, everything fishing-related it sells is saved (fishing poles,
-- lures, fishing and cooking recipes, fish, other items that mention the fishing skill) with the NPC's ID, name and position;
-- when a trainer window with fishing offers opens, the teacher is saved. Position = where the player stands (map and
-- coordinates), which is next to the NPC. Saved in BobbersJournal_DB.npcs. Not tested in the game.
local M = BJ:RegisterModule("Vendors")

local CLASS_WEAPON, SUB_FISHINGPOLE = 2, 20
local CLASS_RECIPE, SUB_COOKING, SUB_FISHING = 9, 5, 9
local BOBBER_ID = 202207 -- Reusable Oversized Bobber (toy and item, same ID as in Cast.lua)
local BOBBER_ITEMS = {[202207] = true, [136377] = true} -- 136377: Oversized Bobber, the item vendors sell (given by Sven)

--- Words that name the fishing skill, lower case: every known name of it (profession, spells, Retail skill lines) and a stem
--- of each (name without the last letter: "angeln" -> "angel" also finds "Angellehrer"). A teacher is recognised by any of them.
local function keywords(noStems)
  local list, seen = {}, {}
  local function add(name)
    if type(name) ~= "string" or #name < 4 then return end
    name = name:lower()
    for _, w in ipairs({name, (not noStems) and #name >= 6 and name:sub(1, #name - 1) or nil}) do
      if not seen[w] then seen[w] = true list[#list + 1] = w end
    end
  end
  add(ns.Skill.Name())
  for _, id in ipairs({7620, 131474}) do
    add(C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or (GetSpellInfo and GetSpellInfo(id)))
  end
  for _, line in ipairs(ns.Skill.RetailLines and ns.Skill.RetailLines() or {}) do add(line.name) end
  return list
end

--- Does the text name the fishing skill (any keyword, case does not matter)?
local function mentions(text, words)
  if type(text) ~= "string" then return false end
  text = text:lower()
  for _, w in ipairs(words or keywords()) do
    local from = 1
    while true do
      local a = text:find(w, from, true)
      if not a then break end
      -- only at the start of a word: "angel" finds "Angellehrer" but not "Rangel"
      local before = a > 1 and text:sub(a - 1, a - 1) or ""
      if not before:match("[%w\128-\255]") then return true end
      from = a + 1
    end
  end
  return false
end

--- Everything the client tells about the NPC in front of the player: tooltip lines, creature data, place. Texts are in the
--- client language (loc). Secret values are left out.
local function npcDetails()
  local d = {loc = GetLocale and GetLocale(), seen = time and time() or nil}
  local function put(key, value)
    value = BJ.Clean(value)
    if value ~= nil and value ~= "" then d[key] = value end
  end
  put("type", UnitCreatureType and UnitCreatureType("npc"))
  put("level", UnitLevel and UnitLevel("npc"))
  put("class", UnitClassification and UnitClassification("npc"))
  put("faction", UnitFactionGroup and (UnitFactionGroup("npc")))
  put("sex", UnitSex and UnitSex("npc"))
  put("race", UnitRace and UnitRace("npc"))
  put("zoneText", GetZoneText and GetZoneText())
  put("subZone", GetSubZoneText and GetSubZoneText())
  if C_TooltipInfo and C_TooltipInfo.GetUnit then
    local ok, data = pcall(C_TooltipInfo.GetUnit, "npc")
    if ok and type(data) == "table" then
      local lines = {}
      for _, line in ipairs(data.lines or {}) do
        local text = BJ.Clean(line.leftText)
        if type(text) == "string" and text ~= "" then lines[#lines + 1] = text end
      end
      if #lines > 0 then d.tip = lines d.title = lines[2] end
    end
  end
  if C_GossipInfo and C_GossipInfo.GetOptions then
    local options = {}
    for _, o in ipairs(C_GossipInfo.GetOptions() or {}) do
      local text = BJ.Clean(o.name)
      if type(text) == "string" and text ~= "" then options[#options + 1] = text end
    end
    if #options > 0 then d.options = options end
  end
  local step = GetTrainerServiceStepIndex and GetTrainerServiceStepIndex()
  if step and GetTrainerServiceInfo then
    local ok, name = pcall(GetTrainerServiceInfo, step)
    name = ok and BJ.Clean(name)
    if type(name) == "string" and name ~= "" then d.step = name end
  end
  local services = GetNumTrainerServices and GetNumTrainerServices() or 0
  if services > 0 and GetTrainerServiceInfo then
    local names = {}
    for i = 1, math.min(services, 60) do
      local ok, name = pcall(GetTrainerServiceInfo, i)
      name = ok and BJ.Clean(name)
      if type(name) == "string" and name ~= "" then names[#names + 1] = name end
    end
    if #names > 0 then d.services = names end
  end
  return d
end

local function npcInfo()
  local guid = UnitGUID and BJ.Clean(UnitGUID("npc"))
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  id = tonumber(id)
  if kind ~= "Creature" or not id then return nil end
  local name = BJ.Clean(UnitName("npc"))
  local info = {n = type(name) == "string" and name or nil, f = Flavor.current, guid = guid, details = npcDetails()}
  local map = C_Map and C_Map.GetBestMapForUnit and BJ.Clean(C_Map.GetBestMapForUnit("player"))
  if map then
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if ok and pos and pos.GetXY then
      local x, y = pos:GetXY()
      x, y = BJ.Clean(x), BJ.Clean(y)
      if x and y and (x > 0 or y > 0) then info.map, info.x, info.y = map, x, y end
    end
  end
  return id, info
end

--- Do the lines of the tooltip of the NPC (name, title like "Fishing Trainer") mention the fishing skill?
local function npcMentionsFishing()
  if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return false end
  local ok, data = pcall(C_TooltipInfo.GetUnit, "npc")
  if not (ok and type(data) == "table") then return false end
  local words = keywords()
  -- line 1 is the NPC's name (a person may be called "Angela"); the title follows
  for i, line in ipairs(data.lines or {}) do
    if i > 1 and mentions(BJ.Clean(line.leftText), words) then return true end
  end
  return false
end

--- One look at the vendor tooltip of the item: is the recipe already known ("Already known"), and which lines are red (what
--- the character lacks: reputation, level, faction, skill). Texts are in the client language.
local function merchantTip(index)
  local known, needs = false, {}
  if not (C_TooltipInfo and C_TooltipInfo.GetMerchantItem) then return known, needs end
  local ok, data = pcall(C_TooltipInfo.GetMerchantItem, index)
  if not (ok and type(data) == "table") then return known, needs end
  local text = _G.ITEM_SPELL_KNOWN
  -- first the recipe check exactly as before; the red lines are a separate step that may fail without harm
  for _, line in ipairs(data.lines or {}) do
    local t = BJ.Clean(line.leftText)
    if type(t) == "string" and type(text) == "string" and t:find(text, 1, true) then known = true end
  end
  pcall(function()
    for _, line in ipairs(data.lines or {}) do
      local t = BJ.Clean(line.leftText)
      local c = line.leftColor
      local r, g, b = BJ.Clean(c and c.r), BJ.Clean(c and c.g), BJ.Clean(c and c.b)
      if type(t) == "string" and t ~= "" and type(r) == "number" and type(g) == "number" and type(b) == "number"
        and r > 0.8 and g < 0.3 and b < 0.3 and #needs < 3
        and not (type(text) == "string" and t:find(text, 1, true)) then -- ("Already known" is red, but no shortcoming)
        needs[#needs + 1] = t
      end
    end
  end)
  return known, needs
end

--- What the merchant asks for the item in slot `index`: { p = price in copper (as shown, with the character's reputation
--- discount), q = stack size, lim = items left (only when limited), cost = { {1|2, id, amount} } extra costs (1 item,
--- 2 currency), need = red tooltip lines }. Nil values are left out.
local function merchantOffer(index, needs)
  local price, stack, avail
  local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and select(2, pcall(C_MerchantFrame.GetItemInfo, index))
  if type(info) == "table" then
    price, stack, avail = info.price, info.stackCount, info.numAvailable
  elseif GetMerchantItemInfo then
    local ok, _, _, p, q, a = pcall(GetMerchantItemInfo, index)
    if ok then price, stack, avail = p, q, a end
  end
  price, stack, avail = BJ.Clean(price), BJ.Clean(stack), BJ.Clean(avail)
  local o = {}
  if type(price) == "number" and price > 0 then o.p = price end
  if type(stack) == "number" and stack > 1 then o.q = stack end
  if type(avail) == "number" and avail >= 0 then o.lim = avail end
  local n = GetMerchantItemCostInfo and BJ.Clean(GetMerchantItemCostInfo(index)) or 0
  for j = 1, type(n) == "number" and n or 0 do
    local ok, _, value, link = pcall(GetMerchantItemCostItem, index, j)
    link, value = ok and BJ.Clean(link), ok and BJ.Clean(value)
    if type(link) == "string" and type(value) == "number" then
      local item, cur = link:match("item:(%d+)"), link:match("currency:(%d+)")
      if item then o.cost = o.cost or {} o.cost[#o.cost + 1] = {1, tonumber(item), value}
      elseif cur then o.cost = o.cost or {} o.cost[#o.cost + 1] = {2, tonumber(cur), value} end
    end
  end
  if needs and #needs > 0 then o.need = needs end
  return o
end

--- Category of a merchant item or nil when it has nothing to do with fishing.
--- Name of the oversized bobber in the client language (from the item data; nil until the game has loaded it).
local function bobberName()
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local ok, name = pcall(getInfo, BOBBER_ID)
  if ok and type(name) == "string" and name ~= "" then return name end
  local saved = BJ.DB.raw and BJ.DB.raw.text and BJ.DB.raw.text.items[BOBBER_ID]
  return saved and saved.n
end

local function category(itemID, name)
  local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local class, sub
  if getInfo then
    local _, _, _, _, _, c, s = getInfo(itemID)
    class, sub = c, s
  end
  if BOBBER_ITEMS[itemID] then return "bobber" end
  -- the item sold may have another ID than the toy it teaches: the same name counts
  if type(name) == "string" and name ~= "" and name == bobberName() then return "bobber" end
  -- Retail: poles are profession tools (class Profession, subclass Fishing), Forever: weapons; ns.Gear knows both
  if ns.Gear.IsPoleItem(itemID) or (class == CLASS_WEAPON and sub == SUB_FISHINGPOLE) then return "pole" end
  if ns.Catalog.Lures()[itemID] then return "lure" end
  -- only IDs are looked at (no tooltip scan, that costs time at every vendor): recipe classes, and the list of recipes with fish
  if class == CLASS_RECIPE and (sub == SUB_COOKING or sub == SUB_FISHING) then return "recipe" end
  if ns.RecipeItems[itemID] then return "recipe" end
  if ns.Catalog.fish[itemID] then return "fish" end
end

--- Wrong entries are never deleted silently: the player is asked first. Declined once = not asked again until the next login.
local declined = {}
local function askRemove(id, name, reason, apply)
  if declined[id] or not StaticPopup_Show then return end
  StaticPopupDialogs["BOBBERSJOURNAL_REMOVE"] = StaticPopupDialogs["BOBBERSJOURNAL_REMOVE"] or {
    text = "%s", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, data) if data and data.apply then BJ.Protected("vendors", data.apply) end end,
    OnCancel = function(_, data) if data then declined[data.id] = true end end,
  }
  StaticPopup_Show("BOBBERSJOURNAL_REMOVE", format(L["Bobber's Journal: %s no longer matches (%s). Remove the entry?"], name, reason), nil, {id = id, apply = apply})
end

local function scanMerchant()
  local count = GetMerchantNumItems and GetMerchantNumItems() or 0
  local items, offers, found = {}, {}, false
  for i = 1, count do
    local link = GetMerchantItemLink(i)
    local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    local cat = itemID and category(itemID, type(link) == "string" and link:match("%[(.-)%]") or nil)
    if itemID and not cat and BJ.settings and BJ.settings.debug then
      local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
      local _, _, _, _, _, c, sc = getInfo(itemID)
      BJ:Debug(format("vendors: slot %d item %d class %s/%s -> %s %s", i, itemID, tostring(c), tostring(sc), tostring(cat), tostring(link:match("%[(.-)%]"))))
    end
    if cat then
      items[itemID] = cat found = true
      -- one look at the tooltip of each fishing item (no scan of the rest of the window): "Already known" marks a learned
      -- recipe for this character (green check in the journal and the pin tooltips), red lines are what the character lacks
      -- (each part on its own, so a problem with the price or the red lines can never stop the recipe detection)
      local okTip, known, needs = pcall(merchantTip, i)
      if not okTip then BJ.lastError = "vendors tip: " .. tostring(known) known, needs = false, {} end
      if cat == "recipe" and known then BJ.DB:SetRecipeKnown(itemID) end
      local okOffer, offer = pcall(merchantOffer, i, needs)
      offers[itemID] = okOffer and offer or {}
    end
  end
  local id, info = npcInfo()
  BJ:Debug(format("vendors: merchant %s, %d items, fishing items found: %s", tostring(id), count, tostring(found)))
  if not id then return end
  local known = BJ.DB.raw.npcs[id]
  local name = info.n or id
  if not found then
    -- nothing fishing-related: an entry from an earlier version is wrong; a teacher stays a teacher (only the items go)
    if known and not known.trainer then
      askRemove(id, name, L["no fishing items"], function()
        BJ.DB:RemoveNPC(id)
        BJ:Print(format(L["Removed wrong entry: %s"], name))
      end)
    elseif known and next(known.items or {}) ~= nil then
      askRemove(id, name, format(L["%d items no longer count"], 0 + (function() local n = 0 for _ in pairs(known.items) do n = n + 1 end return n end)()), function()
        known.items, known.offers = {}, nil
        BJ:Print(format(L["Removed wrong entry: %s"], name))
      end)
    end
    return
  end
  -- saved items that no longer count as fishing items
  local stale = {}
  for itemID in pairs(known and known.items or {}) do
    if not items[itemID] then stale[#stale + 1] = itemID end
  end
  info.items = items
  info.offers = offers
  -- a vendor that repairs gear (only noted for vendors that are saved anyway)
  if CanMerchantRepair and CanMerchantRepair() then info.repair = true end
  BJ.DB:AddNPC(id, info)
  if #stale > 0 then
    askRemove(id, name, format(L["%d items no longer count"], #stale), function()
      for _, itemID in ipairs(stale) do known.items[itemID] = nil if known.offers then known.offers[itemID] = nil end end
      BJ:Print(format(L["Removed wrong entry: %s"], name))
    end)
  end
  if not known then BJ:Print(format(L["Saved fishing vendor: %s"], info.n or id)) end
end

local function serviceName(i)
  local ok, a = pcall(GetTrainerServiceInfo, i)
  if not ok then return nil end
  a = BJ.Clean(a)
  return type(a) == "string" and a or nil
end

--- The services of the open trainer window that belong to fishing: { {n = name, r = rank text, c = cost in copper,
--- k = skill rank needed, l = character level needed} }. `all` takes every service (the window is a fishing step as a whole).
local function lessons(all)
  local out = {}
  local words = keywords()
  for i = 1, math.min(GetNumTrainerServices and GetNumTrainerServices() or 0, 60) do
    local ok, name, sub = pcall(GetTrainerServiceInfo, i)
    name, sub = ok and BJ.Clean(name), ok and BJ.Clean(sub)
    if type(name) == "string" and name ~= "" and (all or mentions(name, words)) then
      local l = {n = name}
      if type(sub) == "string" and sub ~= "" then l.r = sub end
      if GetTrainerServiceCost then
        local okc, cost = pcall(GetTrainerServiceCost, i)
        cost = okc and BJ.Clean(cost)
        if type(cost) == "number" and cost > 0 then l.c = cost end
      end
      if GetTrainerServiceSkillReq then
        local oks, _, rank = pcall(GetTrainerServiceSkillReq, i)
        rank = oks and BJ.Clean(rank)
        if type(rank) == "number" and rank > 0 then l.k = rank end
      end
      if GetTrainerServiceLevelReq then
        local okl, level = pcall(GetTrainerServiceLevelReq, i)
        level = okl and BJ.Clean(level)
        if type(level) == "number" and level > 1 then l.l = level end
      end
      out[#out + 1] = l
    end
  end
  return out
end

local function saveTeacher(how, all)
  local id, info = npcInfo()
  if not id then return end
  local list = lessons(all)
  if #list > 0 then info.lessons = list end
  local known = BJ.DB.raw.npcs[id] and BJ.DB.raw.npcs[id].trainer
  info.trainer = true
  BJ.DB:AddNPC(id, info)
  BJ:Debug("vendors: teacher " .. id .. " (" .. how .. ")")
  if not known then BJ:Print(format(L["Saved fishing teacher: %s"], info.n or id)) end
end

--- A trainer window: teacher when one of its services names fishing, or when the NPC's title does (the list can be empty).
local function stepName()
  -- profession trainers show the profession of the NPC as the "step" above the list (e.g. "Fishing of Midnight - already
  -- known"); the list below it stays empty once everything is known
  local index = GetTrainerServiceStepIndex and GetTrainerServiceStepIndex()
  if index and GetTrainerServiceInfo then
    local ok, name = pcall(GetTrainerServiceInfo, index)
    name = ok and BJ.Clean(name)
    if type(name) == "string" and name ~= "" then return name end
  end
  local button = _G.ClassTrainerFrame and ClassTrainerFrame.skillStepButton
  local text = button and button.name and button.name.GetText and BJ.Clean(button.name:GetText())
  if type(text) == "string" and text ~= "" then return text end
end

--- final = the delayed second look: only then a saved teacher that is none is corrected (the list can arrive late)
local function scanTrainer(final)
  local count = GetNumTrainerServices and GetNumTrainerServices() or 0
  local mention = npcMentionsFishing()
  local step = stepName()
  BJ:Debug(format("vendors: trainer window, %d services, step %s, skill %s, npc text mentions it: %s", count, tostring(step), table.concat(keywords(), "/"), tostring(mention)))
  local words = keywords()
  if #words == 0 then return end
  if mention then saveTeacher("npc text", true) return end
  if mentions(step, words) then saveTeacher("step " .. step, true) return end
  for i = 1, count do
    local name = serviceName(i)
    if mentions(name, words) then saveTeacher("service " .. name) return end
  end
  if final == true then
    local id, info = npcInfo()
    local known = id and BJ.DB.raw.npcs[id]
    if known and known.trainer then
      local name = info.n or id
      askRemove(id, name, L["not a fishing teacher"], function()
        known.trainer = nil
        if next(known.items or {}) == nil then BJ.DB:RemoveNPC(id) end
        BJ:Print(format(L["Removed wrong entry: %s"], name))
      end)
    end
  end
end

--- A conversation: the options name fishing (e.g. "I want to learn fishing") or the NPC's title does.
local function scanGossip()
  local words = keywords()
  if #words == 0 then return end
  local options = C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions() or {}
  local hit = npcMentionsFishing()
  for _, o in ipairs(options) do
    if mentions(BJ.Clean(o.name), words) then hit = true end
  end
  -- only noted: options like "buy fishing supplies" belong to merchants; teachers are saved when their trainer window opens
  BJ:Debug("vendors: conversation, fishing mentioned: " .. tostring(hit))
end

function M:OnEnable()
  BJ:RegisterEvent("MERCHANT_SHOW", "vendors", function() BJ.Protected("vendors", scanMerchant) end)
  -- the list of the trainer can arrive a moment after the window opened
  local function later() if C_Timer then C_Timer.After(0.5, function() BJ.Protected("vendors", scanTrainer, true) end) end end
  BJ:RegisterEvent("TRAINER_SHOW", "vendors", function() BJ.Protected("vendors", scanTrainer) later() end)
  BJ:RegisterEvent("TRAINER_UPDATE", "vendors", later)
  BJ:RegisterEvent("GOSSIP_SHOW", "vendors", function() BJ.Protected("vendors", scanGossip) end)
end
