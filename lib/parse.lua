--[[
  Turning what a human writes into numbers.

  Rules are meant to be read at a glance in somebody else's resource, so the
  library takes '5/10s' and '250ms' rather than a pair of magic numbers. That
  convenience is also the easiest place in the whole project to introduce a
  silent factor-of-sixty bug, which is why it lives in its own file with its
  own tests.
]]

local parse = {}

local UNITS = {
  ms = 0.001,
  s = 1,
  sec = 1,
  secs = 1,
  m = 60,
  min = 60,
  mins = 60,
  h = 3600,
  hr = 3600,
  hour = 3600,
  hours = 3600,
}

--- A duration, in seconds.
--- Accepts a number (already seconds) or a string such as '250ms', '2s', '5m'.
--- @return number|nil seconds, string|nil error
function parse.duration(value)
  if type(value) == 'number' then
    if value ~= value or value == math.huge or value < 0 then
      return nil, 'duration must be a positive number of seconds'
    end
    return value
  end

  if type(value) ~= 'string' then
    return nil, ('duration must be a number or a string, got %s'):format(type(value))
  end

  local amount, unit = value:match('^%s*(%d+%.?%d*)%s*(%a*)%s*$')
  if not amount then
    return nil, ('"%s" is not a duration I understand (try "2s", "250ms", "5m")'):format(value)
  end

  if unit == '' then unit = 's' end

  local factor = UNITS[unit:lower()]
  if not factor then
    return nil, ('"%s" is not a unit I know (ms, s, m, h)'):format(unit)
  end

  return tonumber(amount) * factor
end

--- A rate, as a count and a window in seconds.
--- Accepts '5/10s', '30/min', '3/s' or a table {5, 10}.
--- @return number|nil count, number|string window_or_error
function parse.rate(value)
  if type(value) == 'table' then
    local count, window = value[1], value[2]
    if type(count) ~= 'number' or type(window) ~= 'number' then
      return nil, 'a rate given as a table must be {count, seconds}'
    end
    if count < 1 or window <= 0 then
      return nil, 'a rate must allow at least one call, over a window longer than zero'
    end
    return count, window
  end

  if type(value) ~= 'string' then
    return nil, ('rate must be a string or a table, got %s'):format(type(value))
  end

  local count, window = value:match('^%s*(%d+)%s*/%s*(.-)%s*$')
  if not count then
    return nil, ('"%s" is not a rate I understand (try "5/10s" or "30/min")'):format(value)
  end

  count = tonumber(count)
  if count < 1 then
    return nil, 'a rate must allow at least one call'
  end

  if window == '' then
    -- '5/' parses far enough to get here, and the complaint should be about
    -- the rate the author wrote, not about the empty duration it became.
    return nil, ('"%s" is not a rate I understand (try "5/10s" or "30/min")'):format(value)
  end

  -- '5/s' and '5/min' have no number in front of the unit; '5/10s' does.
  if window:match('^%a+$') then window = '1' .. window end

  local seconds, err = parse.duration(window)
  if not seconds then return nil, err end
  if seconds <= 0 then
    return nil, 'a rate window must be longer than zero'
  end

  return count, seconds
end

return parse
