local ADDON, ns = ...
-- Central icon paths (own artwork: Media/*.tga, 32 bit with alpha, power-of-two sizes 64/128/256).
local base = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Icon_%s_Transparent_%d"
local Icons = {}
ns.Icons = Icons

--- Icons.Path("Fish", 64) -> texture path without extension
function Icons.Path(name, size) return format(base, name, size or 64) end

--- Stacked logo (logo above the name), only in 256 px; shown at 128 px in the options.
Icons.logoStacked = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Logo_Stacked_Transparent_256"

Icons.maskSoft = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Mask_Soft_128" -- soft-edged mask (technical, not artwork)

Icons.ringStamp = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Ring_Stamp_128" -- ring for stamp icons (technical, not artwork)

Icons.logo = function(size) return Icons.Path("Frameless", size or 64) end
Icons.fish, Icons.zones, Icons.book, Icons.bobber = "Fish", "Zones", "Book", "Bobber"
Icons.settings, Icons.stats, Icons.equipment = "Settings", "Statistik", "Equipment" -- stats/equipment: planned features
