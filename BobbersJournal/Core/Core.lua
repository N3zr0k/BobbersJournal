local ADDON, ns = ...
local BJ = {modules = {}, order = {}, events = {}, debugLog = {}}
ns.BJ = BJ
_G.BobbersJournal = BJ -- API.lua hangs the public API on this table

-- Client locale with enUS fallback; no version checks.
local L = setmetatable({}, {__index = function(_, k) return k end})
local function loadLocale(code)
  for k, v in pairs(ns.locales and ns.locales[code] or {}) do L[k] = v end
end
loadLocale("enUS"); loadLocale(GetLocale())
BJ.L = L

-- Title/version come from the TOC only.
function BJ:GetMeta(field)
  return (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, field)
end

--- "Secret" values must not be compared or computed with: treat them as missing.
function BJ.Clean(value)
  if value ~= nil and issecretvalue and issecretvalue(value) then return nil end
  return value
end

--- pcall that remembers the last error for debugging instead of breaking other handlers.
function BJ.Protected(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    BJ.errorCount = (BJ.errorCount or 0) + 1
    BJ.lastError = label .. ": " .. tostring(err)
  end
  return ok
end

-- Debug output: BugLab when installed, otherwise an own chat window "<Addon>_Debug". The window is created once and
-- looked up by name afterwards. If neither is possible a Lua error is raised once so the problem is not silent.
-- Lines always go to the short ring buffer too (used by /bob probe). Only written out while Debug mode is on.
local DEBUG_WINDOW = ADDON .. "_Debug"
local debugFrame, debugFailed

local function findDebugWindow()
  for i = 1, NUM_CHAT_WINDOWS or 10 do
    local name = GetChatWindowInfo and GetChatWindowInfo(i)
    if name == DEBUG_WINDOW then return _G["ChatFrame" .. i] end
  end
end

local function getDebugFrame()
  if debugFrame then return debugFrame end
  debugFrame = findDebugWindow()
  if not debugFrame and FCF_OpenNewWindow then
    local ok, created = pcall(FCF_OpenNewWindow, DEBUG_WINDOW)
    debugFrame = ok and (created or findDebugWindow()) or nil
  end
  return debugFrame
end

--- With debug on: adds the IDs of the element to the tooltip (label/value pairs; empty values are skipped) and re-shows it.
function BJ:DebugTip(tip, ...)
  if not (self.settings and self.settings.debug and tip) then return end
  local parts = {}
  for i = 1, select("#", ...), 2 do
    local label, value = select(i, ...)
    if value ~= nil and value ~= "" then parts[#parts + 1] = format("%s %s", label, tostring(value)) end
  end
  if #parts == 0 then return end
  tip:AddLine("|cff888888" .. table.concat(parts, "  ") .. "|r")
  tip:Show()
end

--- True when the client knows the atlas (atlas names differ between Retail and Forever).
function BJ.HasAtlas(name)
  return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(name) ~= nil
end

function BJ:Debug(text)
  local log = self.debugLog
  log[#log + 1] = format("%.1f %s", GetTime and GetTime() or 0, text)
  if #log > 100 then table.remove(log, 1) end
  if not (self.settings and self.settings.debug) then return end
  local logger = BugLab and BugLab.GetLogger and BugLab:GetLogger(ADDON)
  if logger then logger:Debug("%s", text) return end
  local frame = getDebugFrame()
  if frame then
    frame:AddMessage(format("|cff22B3A7%s|r %s", L["ADDON_NAME"], text))
  elseif not debugFailed then
    debugFailed = true
    geterrorhandler()(format("%s: no BugLab and the chat window %s could not be created.", ADDON, DEBUG_WINDOW))
  end
end

function BJ:RegisterModule(name)
  local m = {name = name}
  self.modules[name] = m
  self.order[#self.order + 1] = name
  return m
end

-- One shared event frame; handlers are called as fn(event, ...). Registration is idempotent per (event, key).
local frame = CreateFrame("Frame")
function BJ:RegisterEvent(event, key, fn)
  local list = self.events[event]
  if not list then
    list = {}
    self.events[event] = list
    if not pcall(frame.RegisterEvent, frame, event) then self.events[event] = nil return false end
  end
  list[key] = fn
  return true
end

function BJ:UnregisterEvent(event, key)
  local list = self.events[event]
  if list then list[key] = nil end
end

function BJ:Print(text)
  print("|cff4da6ffBobber's Journal|r " .. tostring(text))
end

-- Casting by double click intervenes in game control: off by default.
local defaults = {
  minimap = {hide = false, minimapPos = 200, showInCompartment = false}, -- LibDBIcon reads these; the compartment entry comes from the TOC
  -- Casting intervenes in game control: off by default. weaponSwap only has an effect on Forever.
  cast = {enabled = false, modifier = "SHIFT", button = "RightButton", weaponSwap = true, interval = 0.4, autoLure = false, bobberToy = false, favoriteLure = nil, autoBest = true},
  doubleclick = {central = false, modifier = "SHIFT", button = "RightButton", priority = {}, off = {}},
  tooltip = {enabled = true, catches = true, counters = true, items = true, junk = false, barDetails = "key", barKey = "SHIFT"}, -- junk: listed only on request
  bobber = {enabled = false, hideCatches = false, point = "TOP", x = 0, y = -160, scale = 1},
  journalFilter = "all", -- journal list: "all" or "collected"
  skillBar = {enabled = false, scale = 1}, -- point/x/y only after it was moved; default place: above the experience bars
  diaryList = true, -- Retail: our fish list on the empty Classic page of the fishing journal
  diary = true, -- Retail: add our data to the fish pages of the fishing journal
  npcPins = true, -- show the saved fishing vendors and teachers on the world map and the minimap
  findFish = true, -- keep the minimap tracking Find Fish switched on
  debug = false, -- shows the developer tools in the options
  showDescriptions = true, -- grey explanation texts under the options
}

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" and ... == ADDON then
    BobbersJournal_Settings = BobbersJournal_Settings or {}
    for k, v in pairs(defaults) do
      if BobbersJournal_Settings[k] == nil then BobbersJournal_Settings[k] = v end
    end
    BJ.settings = BobbersJournal_Settings
    BobbersJournal_DB = BJ.DB:Init(BobbersJournal_DB)
    for _, n in ipairs(BJ.order) do
      local m = BJ.modules[n]
      if m.OnInitialize then m:OnInitialize() end
    end
  elseif event == "PLAYER_LOGIN" then
    for _, n in ipairs(BJ.order) do
      local m = BJ.modules[n]
      if m.OnEnable then BJ.Protected(n .. " enable", m.OnEnable, m) end
    end
  end
  local list = BJ.events[event]
  if list then
    for key, fn in pairs(list) do BJ.Protected(event .. " " .. tostring(key), fn, event, ...) end
  end
end)
