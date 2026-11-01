local ADDON, ns = ...
local BJ = ns.BJ
local L = BJ.L
-- Minimap button (Icon_Bobber) and addon compartment entry (logo) via LibDataBroker + LibDBIcon (embedded in Libs/).
-- LibDBIcon reads hide / minimapPos / showInCompartment from BobbersJournal_Settings.minimap.
local M = BJ:RegisterModule("Broker")

local C = ns.Colors
local ldbIcon

-- Two-colour hint lines: key bright, description normal
-- Indented so the blue info icon (first hint line) has room; it stays at the bottom of the tooltip.
local function hint(tip, key, text) tip:AddDoubleLine("     " .. "|cff42b1fe" .. key .. "|r", text, 1, 1, 1, 0.85, 0.85, 0.85) end

--- Tooltip with the logo outside on the left (like ATT). Used by the minimap button and the compartment.
function M.ShowTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:AddLine(C.Paint("aqua", L["ADDON_NAME"]))
  GameTooltip:AddLine(" ")
  local tooltip = BJ.modules.Tooltip
  if tooltip and tooltip.SummaryLines then
    BJ.Protected("broker summary", function()
      tooltip.Render(GameTooltip, tooltip.SummaryLines())
      GameTooltip:AddLine(" ")
    end)
  end
  hint(GameTooltip, L["Left click"], L["Open the journal"])
  hint(GameTooltip, L["Right click"], L["Open the options"])
  -- The cast hint (double right click etc.) comes last, with the blue info icon.
  local cast = BJ.modules.Cast
  if cast and cast.Enabled() then
    GameTooltip:AddLine("     |cff42b1fe" .. cast.ShortcutText() .. "|r")
    if tooltip and tooltip.InfoIcon then tooltip.InfoIcon(GameTooltip) end
  end
  GameTooltip:Show()
  if not M.logo then
    M.logo = CreateFrame("Frame", nil, GameTooltip)
    M.logo:SetSize(64, 64)
    M.logo.tex = M.logo:CreateTexture(nil, "ARTWORK")
    M.logo.tex:SetAllPoints()
    M.logo.tex:SetTexture(ns.Icons.logo(64))
  end
  M.logo:ClearAllPoints()
  M.logo:SetPoint("TOPRIGHT", GameTooltip, "TOPLEFT", -4, 0)
  M.logo:Show()
end

function M.HideTooltip()
  GameTooltip:Hide()
  if M.logo then M.logo:Hide() end
end

local function onClick(_, mouseButton)
  if mouseButton == "RightButton" then BJ:OpenOptions() else BJ.modules.Journal.Toggle() end
end

--- Show or hide the minimap button (option "minimap.hide")
function M.SetShown(show)
  BJ.settings.minimap.hide = not show
  if ldbIcon then
    if show then ldbIcon:Show(ADDON) else ldbIcon:Hide(ADDON) end
  end
end

function M:OnEnable()
  ldbIcon = LibStub and LibStub("LibDBIcon-1.0", true)
  local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
  if not (ldbIcon and ldb) then BJ:Debug("Broker: LibDBIcon/LibDataBroker missing, no minimap button") return end
  local obj = ldb:NewDataObject(ADDON, {type = "launcher", text = L["ADDON_NAME"], icon = ns.Icons.Path(ns.Icons.bobber, 64),
    OnClick = onClick, OnEnter = M.ShowTooltip, OnLeave = M.HideTooltip})
  -- The compartment entry comes from the TOC (coloured title and icon, like Binds); LibDBIcon must not add a second one.
  BJ.settings.minimap.showInCompartment = false
  ldbIcon:Register(ADDON, obj, BJ.settings.minimap)
end

-- Addon compartment (Retail; the TOC entries are ignored where it does not exist)
function BobbersJournal_OnAddonCompartmentClick(_, button) onClick(nil, button) end
function BobbersJournal_OnAddonCompartmentEnter(_, frame) M.ShowTooltip(frame) end
function BobbersJournal_OnAddonCompartmentLeave() M.HideTooltip() end
