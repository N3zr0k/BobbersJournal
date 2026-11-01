local _, ns = ...
-- Which client family we run on. Detected by an API that only Retail has, not by version numbers.
-- Bit values are stored per DB entry so data from both clients can live in one file.
local Flavor = {FOREVER = 1, RETAIL = 2, BOTH = 3}
ns.Flavor = Flavor

-- WOW_PROJECT_ID is the client project (not a version number); fall back to C_ClassTalents (Retail talent system)
-- when the constants are missing. UNTESTED on both clients.
local isRetail
if WOW_PROJECT_ID and WOW_PROJECT_MAINLINE then isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
else isRetail = C_ClassTalents ~= nil end
Flavor.current = isRetail and Flavor.RETAIL or Flavor.FOREVER

--- Does entry flags `mask` apply on this client? Missing mask = both.
function Flavor.Matches(mask, wanted)
  return bit.band(mask or Flavor.BOTH, wanted or Flavor.current) ~= 0
end
