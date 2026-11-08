local _, ns = ...
local BJ = ns.BJ
-- Double-click dispatcher (port of Glimpse DoubleClick, tested there on Forever only; Ace3 removed).
-- GLOBAL_MOUSE_DOWN detects the second click within WINDOW. Only then the button is bound by an override binding
-- to a secure button (the only way an addon may cast), and the handler's Prepare(ctx) says what to do.
--   BJ.DoubleClick.Register("fishing", {
--     modifier = "SHIFT" | function, button = "RightButton" | function, priority = 10,
--     when = { standing = true }, Match = function(ctx), Prepare = function(ctx) -> {type=...}|nil, Done = function(ctx, action) })
-- In combat the client locks bindings and secure attributes, so nothing happens then.
local DC = BJ:RegisterModule("DoubleClick")
BJ.DoubleClick = DC
DC.handlers = {}
DC.log = {}

local DOUBLE_MIN, BUTTON_NAME = 0.03, "BobbersJournalDoubleClickButton"
-- Time allowed between the two clicks; set with a slider in the options (cast.interval), 0.4 s by default.
local function window()
  local c = BJ.settings and BJ.settings.cast
  local v = c and tonumber(c.interval)
  return v and math.min(math.max(v, 0.15), 1) or 0.4
end
local BINDING = {LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5"}
DC.MODIFIERS = {SHIFT = true, CTRL = true, ALT = true, NONE = true}

local api = {
  GetTime = GetTime, GetUnitSpeed = GetUnitSpeed, IsFalling = IsFalling, IsSwimming = IsSwimming, IsSubmerged = IsSubmerged,
  GetMirrorTimerInfo = GetMirrorTimerInfo, IsMounted = IsMounted, IsFlying = IsFlying, IsFlyableArea = IsFlyableArea,
  IsIndoors = IsIndoors, IsOutdoors = IsOutdoors, InCombatLockdown = InCombatLockdown, UnitAffectingCombat = UnitAffectingCombat,
  IsShiftKeyDown = IsShiftKeyDown, IsControlKeyDown = IsControlKeyDown, IsAltKeyDown = IsAltKeyDown,
  IsMouselooking = IsMouselooking, MouselookStop = MouselookStop, IsMouseButtonDown = IsMouseButtonDown,
  SetOverrideBindingClick = SetOverrideBindingClick, ClearOverrideBindings = ClearOverrideBindings,
  After = C_Timer and C_Timer.After,
}
DC.api = api

function DC:Log(text)
  local log = self.log
  log[#log + 1] = format("%.1f %s", api.GetTime and api.GetTime() or 0, text)
  if #log > 25 then table.remove(log, 1) end
  BJ:Debug("click: " .. text)
end

-- Settings (BJ.settings.doubleclick): central key for all handlers, priority overrides, handlers switched off.
function DC:Option(name)
  local s = BJ.settings and BJ.settings.doubleclick
  return s and s[name]
end

local function value(field, default)
  if type(field) == "function" then field = field() end
  return field or default
end

function DC:KeyOf(name)
  if self:Option("central") then return self:Option("modifier"), self:Option("button") end
  local h = self.handlers[name]
  if not h then return nil end
  return value(h.modifier, "NONE"), value(h.button, "RightButton")
end

function DC:PriorityOf(name)
  local own = (self:Option("priority") or {})[name]
  if own then return own end
  local h = self.handlers[name]
  return h and h.priority or 0
end

function DC:IsOff(name) return (self:Option("off") or {})[name] == true end

function DC:Sorted()
  local names = {}
  for name in pairs(self.handlers) do names[#names + 1] = name end
  table.sort(names, function(a, b)
    local pa, pb = self:PriorityOf(a), self:PriorityOf(b)
    if pa ~= pb then return pa > pb end
    return a < b
  end)
  return names
end

function DC:HasKey(modifier, button)
  for name in pairs(self.handlers) do
    local mod, btn = self:KeyOf(name)
    if mod == modifier and btn == button and not self:IsOff(name) then return true end
  end
  return false
end

--- Registers a handler under a name; the same name replaces it.
function DC.Register(name, handler)
  if type(name) ~= "string" or type(handler) ~= "table" or type(handler.Prepare) ~= "function" then
    error("DoubleClick.Register(name, { Prepare = function }) expected", 2)
  end
  DC.handlers[name] = handler
end

function DC.Unregister(name) DC.handlers[name] = nil end

--- "Shift + Double right click" style text for a registered handler (modifier names from the client).
function DC:Text(name)
  local mod, btn = self:KeyOf(name)
  local buttons = {RightButton = BJ.L["Double right click"], LeftButton = BJ.L["Double left click"],
    MiddleButton = BJ.L["Double middle click"], Button4 = BJ.L["Double click Button4"], Button5 = BJ.L["Double click Button5"]}
  local text = buttons[btn] or btn
  local names = {SHIFT = SHIFT_KEY_TEXT, CTRL = CTRL_KEY_TEXT, ALT = ALT_KEY_TEXT}
  if mod and mod ~= "NONE" then text = format("%s + %s", names[mod] or mod, text) end
  return text
end

-- Situation at the second click ---------------------------------------------------------------------------------

local function ask(func, ...)
  if not func then return false end
  local ok, v = pcall(func, ...)
  if not ok or BJ.Clean(v) == nil then return false end -- secret values are never compared
  return v == true or v == 1
end

local function underwater()
  if api.IsSubmerged then return ask(api.IsSubmerged) end
  if not api.GetMirrorTimerInfo then return false end
  for i = 1, 3 do
    local ok, timer, _, _, scale, paused = pcall(api.GetMirrorTimerInfo, i)
    if ok and timer == "BREATH" and (scale or 0) < 0 and not paused then return true end
  end
  return false
end

function DC:InCombat() return ask(api.InCombatLockdown) or ask(api.UnitAffectingCombat, "player") end

--- "SHIFT", "CTRL", "ALT", "NONE" or nil when several are held
function DC:HeldModifier()
  local s, c, a = ask(api.IsShiftKeyDown), ask(api.IsControlKeyDown), ask(api.IsAltKeyDown)
  local n = (s and 1 or 0) + (c and 1 or 0) + (a and 1 or 0)
  if n == 0 then return "NONE" end
  if n > 1 then return nil end
  return s and "SHIFT" or c and "CTRL" or "ALT"
end

function DC:Situation(modifier, button)
  local speed = 0
  if api.GetUnitSpeed then
    local ok, v = pcall(api.GetUnitSpeed, "player")
    speed = ok and tonumber(BJ.Clean(v)) or 0
  end
  local falling, swimming, mounted = ask(api.IsFalling), ask(api.IsSwimming), ask(api.IsMounted)
  local indoors = ask(api.IsIndoors) or (api.IsOutdoors ~= nil and not ask(api.IsOutdoors))
  return {
    modifier = modifier, button = button, now = api.GetTime and api.GetTime() or 0,
    moving = speed > 0, standing = speed == 0 and not falling, falling = falling, swimming = swimming,
    underwater = underwater(), mounted = mounted, flying = ask(api.IsFlying), flyable = ask(api.IsFlyableArea),
    indoors = indoors, outdoors = not indoors, canMount = not mounted and not swimming and not indoors and not self:InCombat(),
  }
end

local function fits(when, ctx)
  for field, wanted in pairs(when or {}) do
    if ctx[field] ~= wanted then return false end
  end
  return true
end

function DC:Choose(modifier, button, ctx)
  local reason = "no handler on this key"
  for _, name in ipairs(self:Sorted()) do
    local h = self.handlers[name]
    local mod, btn = self:KeyOf(name)
    if mod == modifier and btn == button then
      if self:IsOff(name) then reason = name .. " is switched off"
      elseif not fits(h.when, ctx) then reason = name .. ": conditions not met"
      else
        local ok, match = true, true
        if h.Match then ok, match = pcall(h.Match, ctx) end
        if ok and match then return name, h end
        reason = name .. (ok and ": Match false" or ": Match error " .. tostring(match))
      end
    end
  end
  return nil, reason
end

-- Detection and secure button --------------------------------------------------------------------------------------

function DC:BindingKey(modifier, button)
  local key = BINDING[button]
  if not key then return nil end
  return (modifier == "NONE" or not modifier) and key or (modifier .. "-" .. key)
end

local function stopMouselook(force)
  if force ~= true and api.IsMouseButtonDown and (api.IsMouseButtonDown("LeftButton") or api.IsMouseButtonDown("RightButton")) then return end
  if api.IsMouselooking and api.IsMouselooking() and api.MouselookStop then api.MouselookStop() end
end

local button
local pending
local armed = 0 -- so an old timer cannot clear a newer binding
local lastPress = {}

local function clear()
  if button and api.ClearOverrideBindings and not DC:InCombat() then api.ClearOverrideBindings(button) end
end

local function setAction(a)
  button:SetAttribute("type", a and a.type or nil)
  button:SetAttribute("spell", a and a.spell or nil)
  button:SetAttribute("item", a and a.item or nil)
  button:SetAttribute("macrotext", a and a.macrotext or nil)
end

local function onPreClick(_, mouseButton, down)
  if DC:InCombat() then
    -- attributes of a secure button cannot be changed in combat (ADDON_ACTION_BLOCKED); they were cleared after the last click
    DC:Log("click on the button in combat")
    return
  end
  if not pending then
    DC:Log("click on the button without a pending handler")
    setAction(nil)
    return
  end
  -- Down and up both arrive (the client casts on one of them depending on a CVar): Prepare runs once
  if not pending.prepared then
    pending.prepared = true
    local ok, action = pcall(pending.handler.Prepare, pending.ctx)
    if not ok then BJ:Debug(format("click error %s: %s", pending.name, tostring(action))) action = nil end
    pending.action = type(action) == "table" and action or nil
    DC:Log(format("%s prepared (%s, down=%s): %s", pending.name, tostring(mouseButton), tostring(down),
      pending.action and tostring(pending.action.type) or "nothing"))
  end
  setAction(pending.action)
end

local function onPostClick(_, _, down)
  if down then return end
  stopMouselook()
  if api.After then api.After(0.1, stopMouselook) end
  clear()
  if not DC:InCombat() then setAction(nil) end -- no stale action stays on the button for a later click
  local done = pending
  pending = nil
  if done and done.handler.Done then pcall(done.handler.Done, done.ctx, done.action) end
end

local function ensureButton()
  if button or not CreateFrame then return button end
  button = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
  button:RegisterForClicks("AnyDown", "AnyUp")
  button:SetScript("PreClick", onPreClick)
  button:SetScript("PostClick", onPostClick)
  return button
end

local function onMouseDown(_, mouseButton)
  if not BINDING[mouseButton] then return end
  local modifier = DC:HeldModifier()
  if not modifier or not DC:HasKey(modifier, mouseButton) then return end

  local key = DC:BindingKey(modifier, mouseButton)
  local now = api.GetTime and api.GetTime() or 0
  local gap = lastPress[key] and (now - lastPress[key])
  if not gap or gap <= DOUBLE_MIN or gap >= window() then
    lastPress[key] = now
    return
  end
  lastPress[key] = nil

  if BJ.settings and BJ.settings.debug then
    -- which frame lies under the mouse (an open dialog window takes the click away from the world)
    local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
    local fname = focus and focus.GetName and focus:GetName()
    DC:Log(format("second click %s over frame: %s", key, tostring(fname or (focus == WorldFrame and "WorldFrame") or "?")))
  end
  if DC:InCombat() then DC:Log("double click " .. key .. " ignored: in combat") return end
  local ctx = DC:Situation(modifier, mouseButton)
  local name, handler = DC:Choose(modifier, mouseButton, ctx)
  if not name then DC:Log("double click " .. key .. " ignored: " .. handler) return end

  local frame = ensureButton()
  if not frame then return end
  armed = armed + 1
  pending = {name = name, handler = handler, ctx = ctx, armed = armed}
  api.SetOverrideBindingClick(frame, true, key, BUTTON_NAME)
  DC:Log(format("double click %s: %s", key, name))
  stopMouselook(true) -- the button now owns the up event

  local mine = armed
  if api.After then
    api.After(window(), function()
      if armed == mine and pending and pending.armed == mine and not pending.prepared then
        pending = nil
        clear()
      end
    end)
  end
end

local function onCombatEnd() pending = nil clear() end

function DC:OnEnable()
  BJ:RegisterEvent("GLOBAL_MOUSE_DOWN", "doubleclick", onMouseDown)
  BJ:RegisterEvent("PLAYER_REGEN_ENABLED", "doubleclick", onCombatEnd)
end
