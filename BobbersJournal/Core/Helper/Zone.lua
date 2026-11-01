local _, ns = ...
local BJ = ns.BJ
-- Zone key = uiMapID, inside instances -instanceID (negative, never collides with map IDs).
-- Position is map-normalised (0..1). Everything is pcall'd: map APIs may be secret or missing.
local Zone = {}
ns.Zone = Zone

local function num(v) v = BJ.Clean(v) return type(v) == "number" and v or nil end

--- zoneKey, name or nil
function Zone.Key()
  local ok, instName, kind, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
  if ok and (kind == "party" or kind == "raid" or kind == "scenario") and num(instanceID) then
    return -instanceID, BJ.Clean(instName)
  end
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local fine, map = pcall(C_Map.GetBestMapForUnit, "player")
  map = fine and num(map)
  if not map or map <= 0 then return nil end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return map, info and info.name
end

--- map, x, y or nil (instance, no map, secret or invalid)
function Zone.Where()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
  map = ok and num(map)
  if not map or map <= 0 then return nil end
  local fine, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not (fine and pos and pos.GetXY) then return nil end
  local x, y = pos:GetXY()
  x, y = num(x), num(y)
  if not (x and y) or x <= 0 or x > 1 or y <= 0 or y > 1 then return nil end
  return map, x, y
end
