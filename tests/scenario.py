import sys
import os
import lupa
l = lupa.LuaRuntime(unpack_returned_tuples=True)
g = l.globals()
g.FLAVOR = 'forever'
g.ADDON_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'BobbersJournal'))
g.SETUP = l.eval('''function(env)
  env.GetProfessions = nil env.GetProfessionInfo = nil
  env.GetSpellInfo = function(id) if id == 7620 then return "Angeln" end end
  env.GetNumSkillLines = function() return 3 end
  env.GetSkillLineInfo = function(i)
    if i == 1 then return "Berufe", true end
    if i == 2 then return "Kochkunst", false, nil, 10, 0, 0, 75 end
    return "Angeln", false, nil, 100, 0, 5, 150
  end
  env.IsFishingLoot = function() return true end
  env.GetNumLootItems = function() return 1 end
  env.GetLootSlotType = function() return 1 end
  env.GetLootSlotLink = function() return "|cffffffff|Hitem:6291::::::::60:::::|h[Roher glänzender Kleinfisch]|h|r" end
  env.GetLootSlotInfo = function() return 1, "Roher glänzender Kleinfisch", 2 end
  env.GetGameTime = function() return 21, 30 end
end''')
g.SCENARIO = l.eval('''function(env, ns, fire, record)
  local t = 1000
  env.GetTime = function() return t end
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 7620)
  t = t + 12
  fire("LOOT_OPENED")
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 7620)
  t = t + 20
  fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "x", 7620)  -- miss
  local BJ = ns.BJ
  local c = BJ.DB:Char()
  print("skill info:", ns.Skill.Info())
  print("char casts/catch/abort:", c.cast, c.catch, c.abort, "time", c.time)
  print("item 6291 qty:", c.fish and c.fish[6291])
  for _, d in ipairs(BJ.debugLog) do print("  dbg", d) end
  -- database format 2: client container, spots as position codes, sub zone numbers, texts apart
  local DB, A = BJ.DB, BJ.API
  DB:AddCatch(37, 150, {[6291] = 1, [6289] = 2}, {map = 37, x = 0.4751, y = 0.6251}, {sub = "Spiegelsee", hour = 14, pos = {map = 37, x = 0.4751, y = 0.6251}})
  DB:AddCatch(37, 150, {[6291] = 1}, {map = 37, x = 0.4770, y = 0.6240}, {sub = "Spiegelsee", pos = {map = 37, x = 0.4770, y = 0.6240}})
  DB:AddCatch(37, 150, {[6289] = 1}, {map = 37, x = 0.30, y = 0.60}, {sub = "Goldhain"})
  local sp = A.GetZoneSpots(37)
  print("db: client key", DB.key, "format", DB.saved.format, "spots", #sp)
  for _, s in ipairs(sp) do local o = {} for id, n in pairs(s.fish) do o[#o + 1] = id .. "=" .. n end table.sort(o) print("  spot", s.x, s.y, s.count, table.concat(o, ",")) end
  assert(#sp == 3, "three cells expected (one from the scenario catch)")
  assert(#A.GetZoneSpots(37, 6291) == 2, "two cells have 6291")
  local x, y = DB.Decode(DB.Encode(0.475, 0.625))
  assert(x == 0.475 and y == 0.625, "encode/decode")
  assert(DB.Encode(0.462, 0.864) == 4620864000, "GatherMate key")
  for _, s in ipairs(A.GetSubZones(37)) do print("  sub", s.id, s.name, s.catches) end
  assert(#A.GetSubZones(37) == 2, "Goldhain (scenario catch) and Spiegelsee")
  local fz = A.GetSubZoneFish(37, "Spiegelsee")
  assert(#fz == 2 and fz[1].drops >= 1, "sub zone fish")
  assert(#A.GetSubZonePoints(37, "Spiegelsee") == 1, "sub zone points from the log")
  assert(A.GetZoneCatches(37) == 4)
  assert(A.GetZoneFish(37, 2) and #A.GetZoneFish(37, 2) == 0, "other client: nothing")
  assert(DB.raw.zones[37].subs[DB:FindSub(37, "Spiegelsee")].looted == 2)
  assert(DB.raw.points[37] ~= nil and DB.raw.world == nil)
  DB:AddFishRecipe(6291, 777, "Testgericht")
  DB:AddFishRecipe(6289, 777)
  DB:SetRecipeLearned(777, "Testgericht")
  DB:SetRecipeKnown(5485)
  DB:AddNPC(55, {n = "Test", map = 37, x = 0.5, y = 0.5, items = {[6256] = "pole"}})
  assert(DB.raw.recipes[777].fish[6289] and DB.raw.text.recipes[777] == "Testgericht" and DB:Char().learned[777])
  local gr = A.GetFishRecipes(6291)
  local found = false for _, r in ipairs(gr) do if r.id == 777 then found = true end end
  assert(found, "recipe via fish")
  assert(DB:RemoveNPC(55) and DB:RecipeKnown(5485))
  -- merchant with price, extra cost, limited stock, red requirement, repair; then a trainer with lessons
  env.UnitGUID = function(u) if u == "npc" then return "Creature-0-0-0-0-4242-0" end return "Player-1-0" end
  env.UnitName = function() return "Händler Fritz" end
  env.GetMerchantNumItems = function() return 1 end
  env.GetMerchantItemLink = function() return "|cffffffff|Hitem:6256::::::::60:::::|h[Angelrute]|h|r" end
  env.C_MerchantFrame = {GetItemInfo = function() return {price = 25000, stackCount = 1, numAvailable = 3} end}
  env.GetMerchantItemCostInfo = function() return 1 end
  env.GetMerchantItemCostItem = function() return "x", 5, "|Hcurrency:1166|h[Marke]|h" end
  env.CanMerchantRepair = function() return true end
  env.C_TooltipInfo.GetMerchantItem = function() return {lines = {{leftText = "Angelrute"}, {leftText = "Benötigt Wohlwollend", leftColor = {r = 1, g = 0.1, b = 0.1}}}} end
  fire("MERCHANT_SHOW")
  local npc = DB.raw.npcs[4242]
  assert(npc and npc.items[6256] == "pole", "merchant saved")
  local o = npc.offers[6256]
  assert(o.p == 25000 and o.lim == 3 and o.cost[1][1] == 2 and o.cost[1][2] == 1166 and o.cost[1][3] == 5 and o.need[1] == "Benötigt Wohlwollend", "offer")
  assert(npc.repair == true)
  local text = ns.Prices.OfferText(o)
  assert(text:find("5 ") and text:find("3"), text)
  -- a failing price API must not stop the recipe detection
  env.C_MerchantFrame = {GetItemInfo = function() error("boom") end}
  env.GetMerchantItemLink = function() return "|cffffffff|Hitem:5486::::::::60:::::|h[Rezept]|h|r" end
  env.C_TooltipInfo.GetMerchantItem = function() return {lines = {{leftText = _G.ITEM_SPELL_KNOWN or "Bereits bekannt"}}} end
  env.ITEM_SPELL_KNOWN = "Bereits bekannt"
  fire("MERCHANT_SHOW")
  assert(DB:Char().recipes and DB:Char().recipes[5486] == true, "recipe detected although the price API fails")
  env.GetNumTrainerServices = function() return 1 end
  env.GetTrainerServiceInfo = function() return "Angeln Geselle", "Rang 2" end
  env.GetTrainerServiceCost = function() return 1000 end
  env.GetTrainerServiceSkillReq = function() return "Angeln", 50 end
  env.GetTrainerServiceLevelReq = function() return 10 end
  fire("TRAINER_SHOW")
  local l = DB.raw.npcs[4242].lessons
  assert(l and l[1].n == "Angeln Geselle" and l[1].c == 1000 and l[1].k == 50 and l[1].l == 10, "lessons")
  assert(ns.Prices.LessonText(l[1]):find("Angeln Geselle"))
  DB:RemoveNPC(4242)
  assert(DB:SetRank(6291, "Trophy") and DB:Rank(6291) == "Trophy" and not DB:SetRank(6291, "Trophy"))
  -- income per hour in the fish tooltip
  DB:Char().time = 3600
  DB.session.time = 600
  env.GetItemInfo = function(id) return "Fisch", "|cffffffff|Hitem:" .. id .. "|h[Fisch]|h|r", 1, 1, 1, "x", "y", 1, "z", 1, 250 end
  env.Auctionator = {API = {v1 = {GetAuctionPriceByItemID = function() return 12345 end}}}
  local out = {}
  for _, l in ipairs(BJ.modules.Tooltip.ItemLines(6291)) do out[#out + 1] = (l.header and ("[" .. l.header .. "]") or (tostring(l[1]) .. " = " .. tostring(l[2]))) end
  print(table.concat(out, " | "))
  assert(table.concat(out):find("Ø Gefangen pro Stunde =", 1, true), "average sign, session only")
  DB:ResetSession() assert(DB.session.time == 0 and DB.raw.session == DB.session)
  assert(table.concat(out):find("Auktionswert") or table.concat(out):find("Auction value"), "auction row")
  env.Auctionator = nil
  local none = {}
  for _, l in ipairs(BJ.modules.Tooltip.ItemLines(6291)) do none[#none + 1] = tostring(l[1]) end
  assert(not table.concat(none):find("Auktionswert"), "no auction line without a price addon")
  DB.session.time = 600 DB.session.fish[6291] = 10
  local hud, third = BJ.modules.Tooltip.Lines(true), 0
  for _, l in ipairs(hud) do if type(l) == "table" and l[3] then third = third + 1 print("  hud", l[1], l[2], l[3]) end end
  assert(third >= 1, "third column with the value per hour")
  env.Auctionator = {API = {v1 = {GetAuctionPriceByItemID = function() return 500 end}}}
  DB:Char().time = 7200 DB:Char().fish[6291] = 20
  local fn = function(id, bank, charges, reagent, warband) local n = 3 if bank then n = n + 5 end if reagent then n = n + 1 end if warband then n = n + 2 end return n end
  env.GetItemCount = fn env.C_Item.GetItemCount = fn
  DB.session.bankRead = nil
  env.GetItemCount = function(id, bank) return 3 end env.C_Item.GetItemCount = env.GetItemCount
  local sec = BJ.modules.Tooltip.FishSections(6291)
  assert(tostring(sec[1][2][2]):find("bitte die Bank besuchen"), "bank not read yet")
  fire("BANKFRAME_OPENED")
  assert(DB.session.bankRead == true, "bank read flag")
  sec = BJ.modules.Tooltip.FishSections(6291)
  assert(not tostring(sec[1][2][2]):find("bitte"), "bank read")
  local val = sec[2]
  assert(val and val[1] == "Wert des Bestands", "stock value section")
  print("  value", table.concat(val[2], " | "))
  DB.session.bankRead = nil
  env.GetItemCount = fn env.C_Item.GetItemCount = fn
  local jl = BJ.modules.Journal and BJ.modules.Journal.DetailLines and BJ.modules.Journal.DetailLines({kind = "fish", id = 6291})
  print("journal lines", jl and #jl)
  if jl then for _, l in ipairs(jl) do print("  j", l) end end
  -- the journal window: open it and look at every page of a fish, a lure, a zone and a vendor
  local J = BJ.modules.Journal
  J.Toggle()
  DB:AddNPC(4243, {n = "Händler Test", map = 37, x = 0.5, y = 0.5, trainer = true, items = {[6256] = "pole", [5486] = "recipe"}, offers = {[6256] = {p = 100, need = {"Benötigt Ruf"}}}, lessons = {{n = "Angeln", c = 10}}, repair = true})
  DB.raw.prices[6291] = {}
  for d = 0, 40 do DB.raw.prices[6291][ns.PriceHistory.Day() - d] = {100 + d, 200 + d, 150 + d % 7 * 5} end
  for _, tab in ipairs({"fish", "zones", "vendors", "lures", "junk", "bookmarks"}) do
    J.SelectTab(tab)
    local first = J.FirstEntry and J.FirstEntry()
    if not first then print("  tab", tab, "no entries") end
    if first then
      J.Select(first)
      for p = 1, 3 do J.SetPage(p) J.Refresh() end
      print("  tab", tab, first.kind, first.id)
    end
  end
  for _, want in ipairs({{"fish", "fish", 6291}, {"vendors", "npc", 4243}, {"lures", "lure", nil}}) do
    J.SelectTab(want[1])
    for _, e in ipairs(J.Entries()) do
      if e.kind == want[2] and (want[3] == nil or e.id == want[3]) then
        J.Select(e)
        for p = 1, 3 do J.SetPage(p) J.Refresh() end
        print("  picked", want[1], e.kind, e.id, "chart", BJ.modules.Journal and "ok")
        break
      end
    end
  end
  BJ.API.SetBookmark("npc", 4243, true)
  J.SelectTab("bookmarks")
  local sawNpc = false
  for _, e in ipairs(J.Entries()) do if e.kind == "npc" then sawNpc = true J.Select(e) J.Refresh() end end
  assert(sawNpc, "bookmarked vendor listed")
  BJ.API.SetBookmark("npc", 4243, false)
  env.ITEM_SPELL_KNOWN = "Bereits bekannt"
  local needs = ns.Prices.Needs({need = {"Bereits bekannt", "Benötigt Ruf"}})
  assert(#needs == 1 and needs[1] == "Benötigt Ruf", "known line is no shortcoming")
  local st = ns.PriceHistory.Stats(6291)
  assert(st and st.n == 41 and st.min == 100 and st.max == 500 and st.change30 ~= nil, "price stats")
  assert(st.bestWday ~= nil and st.worstWday ~= nil, "weekdays")
  assert(ns.PriceHistory.Record(6291) and #ns.PriceHistory.Series(6291, 365) == 41, "record today")
  print("  stats", st.n, st.min, st.max, math.floor(st.avg), st.change30, st.bestWday)
  print("journal pages: errorCount", BJ.errorCount, BJ.lastError)
  assert((BJ.errorCount or 0) == 0, tostring(BJ.lastError))
  print("db: ok")
  print("errorCount", BJ.errorCount, BJ.lastError)
end''')
res = l.execute(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mock.lua')).read())
errs = res['errors']
print('errors:', len(errs))
for i in range(1, len(errs)+1): print(' ', errs[i])
sys.exit(1 if len(errs) else 0)
