local _, ns = ...
local BJ = ns.BJ
-- Menus for both clients: Retail's own dropdown (DropdownButton / MenuUtil), Forever's classic UIDropDownMenu / EasyMenu.
--   BJ.Menu.Choice(parent, {width, values, get, pick, display}) -> control, update(), setEnabled(on)
--       A choice dropdown showing the current value. The caller anchors `control`.
--   BJ.Menu.Popup(owner, title, items)
--       A context menu; items = { {text, checked = function, func = function, disabled = bool}, ... }.
-- A cycling button is the last resort in Choice so the option always works.
local Menu = {}
BJ.Menu = Menu

function Menu.Choice(parent, o)
  local values, get, pick, display = o.values, o.get, o.pick, o.display
  local width = o.width or 180
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(width)
    dd:SetupMenu(function(_, root)
      for _, v in ipairs(values) do
        root:CreateRadio(display(v), function() return get() == v end, function() pick(v) end)
      end
    end)
    return dd, function() if dd.GenerateMenu then dd:GenerateMenu() end end, function(on) dd:SetEnabled(on) end
  end
  if UIDropDownMenu_Initialize and UIDropDownMenu_AddButton then
    local frame = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(frame, width - 20)
    UIDropDownMenu_Initialize(frame, function()
      for _, v in ipairs(values) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = display(v)
        info.checked = get() == v
        info.func = function() pick(v) end
        UIDropDownMenu_AddButton(info)
      end
    end)
    return frame, function() UIDropDownMenu_SetText(frame, display(get())) end, function(on)
      if on then UIDropDownMenu_EnableDropDown(frame) else UIDropDownMenu_DisableDropDown(frame) end
    end
  end
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 24)
  button:SetScript("OnClick", function()
    local cur, nextIndex = get(), 1
    for i, v in ipairs(values) do if v == cur then nextIndex = i % #values + 1 end end
    pick(values[nextIndex])
  end)
  return button, function() button:SetText(display(get())) end, function(on) button:SetEnabled(on) end
end

local classicFrame
function Menu.Popup(owner, title, items)
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner, function(_, root)
      if title then root:CreateTitle(title) end
      for _, it in ipairs(items) do
        if it.disabled then
          root:CreateTitle(it.text)
        else
          root:CreateRadio(it.text, it.checked or function() return false end, it.func)
        end
      end
    end)
  elseif EasyMenu then
    classicFrame = classicFrame or CreateFrame("Frame", "BobbersJournalPopupMenu", UIParent, "UIDropDownMenuTemplate")
    local menu = {}
    if title then menu[#menu + 1] = {text = title, isTitle = true, notCheckable = true} end
    for _, it in ipairs(items) do
      if it.disabled then
        menu[#menu + 1] = {text = it.text, disabled = true, notCheckable = true}
      else
        menu[#menu + 1] = {text = it.text, checked = it.checked and it.checked() or false, func = it.func}
      end
    end
    EasyMenu(menu, classicFrame, "cursor", 0, 0, "MENU")
  end
end
