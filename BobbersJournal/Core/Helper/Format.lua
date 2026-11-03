local _, ns = ...
-- Central display of numbers (documentation/assets/Farbschema.md): ALL value/percent texts of the addon come from here.
-- Counts are white, percentages Bobber beige, the order is always "value (percent)". Change the look here only.
local Format = {}
ns.Format = Format

local COUNT = "|cffffffff"   -- colour of counts
local PERCENT = "%d %%"      -- how a percentage is written

--- Rounded percent of a fraction (0..1).
function Format.Round(fraction) return math.floor((fraction or 0) * 100 + 0.5) end

--- "15 %" in Bobber beige; plain = no colours (pages on parchment, where beige cannot be read).
function Format.Percent(fraction, plain)
  local text = PERCENT:format(Format.Round(fraction))
  return plain and text or ns.Colors.parchmentHex .. text .. "|r"
end

--- A count in white.
function Format.Count(n, plain)
  return plain and tostring(n) or COUNT .. n .. "|r"
end

--- "24 (15 %)": count in white, percent in beige. fraction nil = count only. plain = no colours.
function Format.Value(n, fraction, plain)
  local out = Format.Count(n, plain)
  if fraction then
    local text = PERCENT:format(Format.Round(fraction))
    out = out .. " " .. (plain and "(" .. text .. ")" or ns.Colors.parchmentHex .. "(" .. text .. ")|r")
  end
  return out
end
