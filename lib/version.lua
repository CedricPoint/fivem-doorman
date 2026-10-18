--[[
  Is there a newer doorman than the one running?

  Pure on purpose, like the rest of lib/: the HTTP request and the console
  are in server/main.lua, and this only reads two version strings and says
  how they compare. That is the part worth testing, because it is the part
  that decides whether a server owner gets told to update.
]]

local version = {}

--- '1.2.3', 'v1.2.3', '1.2' -> { 1, 2, 3 } (missing parts are 0).
--- A suffix such as '-beta' or '+build' is ignored, not compared: a check that
--- nags people about pre-releases they never asked for gets turned off.
--- @return table|nil, string|nil
function version.parse(text)
  if type(text) ~= 'string' then
    return nil, ('a version is a string, not %s'):format(type(text))
  end

  local core = text:match('^%s*[vV]?(%d+[%.%d]*)')
  if not core or core:find('%.%.') or core:sub(-1) == '.' then
    return nil, ('"%s" is not a version I understand (expected something like 1.2.3)'):format(text)
  end

  local parts = {}
  for number in core:gmatch('%d+') do
    parts[#parts + 1] = tonumber(number)
  end

  if #parts > 3 then
    return nil, ('"%s" has more than three numbers'):format(text)
  end

  return { parts[1], parts[2] or 0, parts[3] or 0 }
end

--- -1 when a is older than b, 0 when they are the same, 1 when a is newer.
function version.compare(a, b)
  for i = 1, 3 do
    if a[i] ~= b[i] then
      return a[i] < b[i] and -1 or 1
    end
  end
  return 0
end

--- Compare what is running with the latest published release.
--- @return string|nil  'outdated', 'current' or 'ahead' (a local build newer
---   than anything published); nil and a reason when either side is unreadable
function version.status(running, latest)
  local have, err = version.parse(running)
  if not have then return nil, 'running version: ' .. err end

  local want
  want, err = version.parse(latest)
  if not want then return nil, 'latest release: ' .. err end

  local order = version.compare(have, want)
  if order < 0 then return 'outdated' end
  if order > 0 then return 'ahead' end
  return 'current'
end

--- '1.2.3' from { 1, 2, 3 }, for messages.
function version.format(parts)
  return ('%d.%d.%d'):format(parts[1], parts[2], parts[3])
end

return version
