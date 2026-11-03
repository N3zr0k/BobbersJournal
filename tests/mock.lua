-- Smoke-test harness: loads the addon in a simulated client. FLAVOR = "forever" or "retail".
local FLAVOR = FLAVOR or "forever"
local ADDON_DIR = ADDON_DIR
local errors = {}
debug.sethook(function() error("INSTRUCTION LIMIT\n" .. debug.traceback(), 2) end, "", 50000000)
local function record(label, err) errors[#errors + 1] = label .. " -> " .. tostring(err) end

local stub
local stubMT = {}
local frames = {}
local function newStub()
  local t = setmetatable({}, stubMT)
  rawset(t, "SetScript", function(self, name, fn) rawset(self, "_" .. name, fn) end)
  rawset(t, "HookScript", function(self, name, fn) rawset(self, "_" .. name, fn) end)
  rawset(t, "GetText", function() return "" end)
  rawset(t, "GetScript", function(self, name) return rawget(self, "_" .. name) end)
  return t
end
stubMT.__index = function(t, k)
  if type(k) ~= "string" then return nil end
  local f = newStub()
  rawset(t, k, f)
  return f
end
stubMT.__call = function() return newStub() end
stubMT.__add = function() return 0 end stubMT.__sub = function() return 0 end stubMT.__mul = function() return 0 end
stubMT.__div = function() return 1 end stubMT.__unm = function() return 0 end
stubMT.__lt = function() return false end stubMT.__le = function() return false end
stubMT.__concat = function(a, b) return "" end
stubMT.__len = function() return 0 end

local env = {}
local G = setmetatable(env, {__index = _G})
env._G = env
local retail = FLAVOR == "retail"

for _, n in ipairs({"string","table","math","pairs","ipairs","next","select","type","tostring","tonumber","pcall","xpcall","error","assert","setmetatable","getmetatable","rawget","rawset","rawequal","os","print","unpack"}) do end
env.unpack = table.unpack
env.format = string.format
env.strsplit = function(sep, s, n) local out = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out+1] = p end return table.unpack(out) end
env.strjoin = function(sep, ...) return table.concat({...}, sep) end
env.tinsert = table.insert env.tremove = table.remove
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.date = os.date env.time = os.time
env.GetTime = function() return 1000 end
env.bit = {band = function(a, b) return a & b end, bor = function(a, b) return a | b end}
env.strlower = string.lower env.strupper = string.upper env.strfind = string.find env.strsub = string.sub env.strlen = string.len
env.floor = math.floor env.ceil = math.ceil env.max = math.max env.min = math.min env.abs = math.abs
env.geterrorhandler = function() return function(m) record("errorhandler", m) end end
env.GetLocale = function() return "deDE" end
env.WOW_PROJECT_MAINLINE = 1
env.WOW_PROJECT_ID = retail and 1 or 2
if retail then env.C_ClassTalents = newStub() end
env.CreateFrame = function() local f = newStub() frames[#frames + 1] = f return f end
env.UIParent = newStub() env.GameTooltip = newStub() env.WorldMapFrame = nil
env.hooksecurefunc = function() end
local timers = {}
env.C_Timer = {After = function(_, fn) timers[#timers + 1] = {"After", fn} end, NewTicker = function(_, fn) timers[#timers + 1] = {"Ticker", fn} return newStub() end}
env.UnitName = function() return "Nez" end env.UnitGUID = function() return "Player-1-00000001" end
env.UnitClass = function() return "Priester", "PRIEST" end
env.UnitLevel = function() return 60 end
env.GetRealmName = function() return "Test" end
env.InCombatLockdown = function() return false end
env.IsFishingLoot = function() return false end
env.GetUnitSpeed = function() return 0 end env.IsFalling = function() return false end
env.UnitAffectingCombat = function() return false end
env.GetZoneText = function() return "Wald von Elwynn" end env.GetSubZoneText = function() return "Goldhain" end
env.GetNumLootItems = function() return 0 end
env.GetInventoryItemLink = function() return nil end env.GetInventoryItemID = function() return nil end
env.GetInventoryItemTexture = function() return nil end
env.GetItemInfoInstant = function(id) if id == 5486 then return 5486, "Rezept", "Rezept", "", 1, 9, 5 end return 6256, "Waffe", "Angelruten", "INVTYPE_2HWEAPON", 1, 2, 20 end
env.GetItemInfo = function() return "Item" end
env.GetItemCount = function() return 0 end
env.GetItemQualityColor = function() return 1, 1, 1 end
env.GetItemCooldown = function() return 0, 0 end
env.GetSpellInfo = function() return "Angeln" end
env.IsSpellKnown = function() return true end
env.GetSpellBookItemName = function() return nil end
env.GetNumSkillLines = function() return 0 end env.GetSkillLineInfo = function() return nil end
env.GetProfessions = function() return nil end env.GetProfessionInfo = function() return nil end
env.GetNumTrainerServices = function() return 0 end
env.GetMerchantNumItems = function() return 0 end
env.GetAddOnMetadata = function() return "x" end
env.GetCVar = function() return "0" end
env.GetCursorPosition = function() return 0, 0 end
env.IsShiftKeyDown = function() return false end env.IsControlKeyDown = function() return false end env.IsAltKeyDown = function() return false end
env.GetNumSubgroupMembers = function() return 0 end
env.IsInInstance = function() return false end
env.IsPlayerMoving = function() return false end
env.GetMinimapZoneText = function() return "x" end
env.GetChatWindowInfo = function() return nil end
env.NUM_CHAT_WINDOWS = 10 env.NUM_BAG_SLOTS = 4
env.Minimap = newStub() env.C_Map = {GetMapWorldSize = function() return 1000, 800 end, GetBestMapForUnit = function() return 37 end, GetMapInfo = function() return {name = "Elwynn", mapID = 37, parentMapID = 13, mapType = 3} end,
  GetPlayerMapPosition = function() return {GetXY = function() return 0.4, 0.5 end} end, GetMapChildrenInfo = function() return {} end, GetMapArtID = function() return 1 end}
env.C_Container = {GetContainerNumSlots = function() return 0 end, GetContainerItemID = function() return nil end, GetContainerNumFreeSlots = function() return 0, 0 end, GetContainerItemLink = function() return nil end, GetContainerItemInfo = function() return nil end}
env.C_Item = {GetItemInfoInstant = env.GetItemInfoInstant, GetItemNameByID = function() return "Item" end, GetItemCount = function() return 0 end, GetItemQualityByID = function() return 1 end, GetItemIconByID = function() return 1 end, RequestLoadItemDataByID = function() end, GetItemCooldown = function() return 0, 0 end, EquipItemByName = function() end}
env.C_AddOns = {GetAddOnMetadata = function() return "x" end, IsAddOnLoaded = function() return false end}
env.C_Texture = nil
env.C_TooltipInfo = {GetUnit = function() return {lines = {}} end, GetItemByID = function() return {lines = {}} end, GetMerchantItem = function() return {lines = {}} end, GetInventoryItem = function() return {lines = {}} end, GetBagItem = function() return {lines = {}} end}
env.C_GossipInfo = {GetOptions = function() return {} end}
env.TooltipDataProcessor = retail and newStub() or nil
env.Enum = retail and {ItemClass = {Weapon = 2, Profession = 19}, ItemWeaponSubclass = {Fishingpole = 20}, TooltipDataType = {Item = 0, Unit = 7}, ItemProfessionSubclass = {Fishing = 9}} or nil
if retail then
  env.C_TradeSkillUI = {GetAllRecipeIDs = function() return {} end, GetAllProfessionTradeSkillLines = function() return {} end, GetProfessionInfoBySkillLineID = function() return nil end}
  env.C_Spell = {GetSpellName = function() return "Angeln" end, GetSpellInfo = function() return {name = "Angeln", iconID = 1} end, GetSpellTexture = function() return 1 end}
  env.C_UnitAuras = {GetAuraDataByIndex = function() return nil end, GetPlayerAuraBySpellID = function() return nil end}
  env.PlayerHasToy = function() return false end env.C_ToyBox = {}
  env.C_Texture = {GetAtlasInfo = function() return {} end}
  env.EventRegistry = newStub() env.Settings = newStub()
  env.MapCanvasDataProviderMixin = {} env.CreateFromMixins = function(t) return {} end
end
env.LibStub = nil
env.StaticPopupDialogs = {} env.StaticPopup_Show = function() end env.YES = "Ja" env.NO = "Nein" env.UISpecialFrames = {} env.OKAY = "OK" env.CANCEL = "Abbrechen"
env.SlashCmdList = {}
env.DEFAULT_CHAT_FRAME = newStub()
env.ChatFontNormal = {} env.GameFontNormal = {} env.GameFontHighlight = {}

if SETUP then SETUP(env) end
local ns = {}
local ADDON = "BobbersJournal"

local function loadFile(rel)
  local path = ADDON_DIR .. "/" .. rel:gsub("\\", "/")
  local f = assert(io.open(path, "rb"), "missing " .. path)
  local src = f:read("a") f:close()
  local chunk, err = load(src, "@" .. rel, "t", env)
  if not chunk then record("SYNTAX " .. rel, err) return end
  local ok, e = pcall(chunk, ADDON, ns)
  if not ok then record("LOAD " .. rel, e) end
end

local xml = assert(io.open(ADDON_DIR .. "/BobbersJournal.xml", "rb")):read("a")
for file in xml:gmatch('<Script file="([^"]+)"') do
  loadFile(file)
  if file == "Core\\Core.lua" and ns.BJ then
    ns.BJ.Protected = function(label, fn, ...) local ok, err = pcall(fn, ...) if not ok then record(label, err) end return ok end
  end
end

local BJ = ns.BJ
local function fire(event, ...)
  for _, f in ipairs(frames) do
    local fn = rawget(f, "_OnEvent")
    if fn then local ok, e = pcall(fn, f, event, ...) if not ok then record("event " .. event, e) end end
  end
end
if BJ then
  env.BobbersJournal_Settings = nil env.BobbersJournal_DB = nil
  if PRELOAD then local f = assert(load(PRELOAD, "preload", "t", env)) f() end -- saved variables of an earlier session
  fire("ADDON_LOADED", ADDON)
  fire("PLAYER_LOGIN")
  for _, e in ipairs({"PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "SKILL_LINES_CHANGED", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "UNIT_AURA", "LOOT_OPENED", "LOOT_CLOSED", "MERCHANT_SHOW", "TRAINER_SHOW", "TRAINER_UPDATE", "GOSSIP_SHOW", "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "CHAT_MSG_SKILL"}) do fire(e) end
  fire("UNIT_SPELLCAST_CHANNEL_START", "player", "x", 7620)
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 7620)
  fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "x", 7620)
  if SCENARIO then SCENARIO(env, ns, fire, record) end
  -- run every timer and ticker callback once (pins on the minimap, delayed scans ...)
  for i = 1, #timers do local t = timers[i] local ok, e = pcall(t[2]) if not ok then record("timer " .. t[1] .. " #" .. i, e) end end
  -- slash command: journal, options, probe, export
  local cmd = env.SlashCmdList and env.SlashCmdList["BOBBERSJOURNAL"]
  if cmd then for _, a in ipairs({"", "options", "probe", "export"}) do local ok, e = pcall(cmd, a) if not ok then record("/bob " .. a, e) end end
  else record("SLASH", "no handler") end
  if BJ.lastError then record("lastError", BJ.lastError) end
end
return {errors = errors, ns = ns, env = env, record = record, fire = fire, loginDone = true}
