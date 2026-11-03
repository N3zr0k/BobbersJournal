local _, ns = ...
-- Central colour scheme (documentation/assets/Farbschema.md). Define colours here only.
local Colors = {}
ns.Colors = Colors

local HEX = {ocean = "0E3A5A", aqua = "22B3A7", parchment = "D9B382", leather = "6B4A2E", sand = "F1E6D2", red = "E64545"}

for name, hex in pairs(HEX) do
  local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  Colors[name] = {r / 255, g / 255, b / 255}
  Colors[name .. "Hex"] = "|cff" .. hex:lower()
end

--- Colour escape of a colour given as r, g, b (0..1): "|cffrrggbb"
function Colors.Escape(r, g, b)
  return format("|cff%02x%02x%02x", math.floor(math.min(r * 255 + 0.5, 255)), math.floor(math.min(g * 255 + 0.5, 255)), math.floor(math.min(b * 255 + 0.5, 255)))
end

--- Text in a colour given as r, g, b (0..1): Colors.Wrap(r, g, b, "text"); without a colour the text is returned as it is.
function Colors.Wrap(r, g, b, text)
  if not r then return text end
  return Colors.Escape(r, g, b) .. text .. "|r"
end

--- Wraps text in a colour escape: Colors.Paint("aqua", "text")
function Colors.Paint(name, text)
  return (Colors[name .. "Hex"] or "|cffffffff") .. tostring(text) .. "|r"
end
