local t = require('test.harness')
local parse = require('lib.parse')

local test, eq, near, ok, no = t.test, t.eq, t.near, t.ok, t.no

--- The parsers answer `nil, why`. This checks both halves at once.
local function rejects(fn, input, pattern)
  local value, err = fn(input)
  no(value, ('%s should not have parsed'):format(t.show(input)))
  ok(tostring(err):match(pattern),
    ('the message was %s, which does not mention %s'):format(t.show(err), t.show(pattern)))
end

test('a duration can be written the way people say it', function()
  eq(parse.duration('2s'), 2)
  near(parse.duration('250ms'), 0.25)
  eq(parse.duration('5m'), 300)
  eq(parse.duration('1h'), 3600)
  eq(parse.duration('90'), 90, 'a bare number is seconds')
  eq(parse.duration(1.5), 1.5)
end)

test('and spelled out, and with space around it', function()
  eq(parse.duration('30 sec'), 30)
  eq(parse.duration('  2 mins  '), 120)
  eq(parse.duration('1 hour'), 3600)
  eq(parse.duration('2S'), 2, 'case does not matter')
end)

test('a minute is sixty seconds, not sixty of anything else', function()
  -- The whole reason this file exists. A factor of sixty in the wrong
  -- direction turns "5 per minute" into "5 per second", and nobody finds out
  -- until a server is on fire.
  eq(parse.duration('1m'), 60)
  near(parse.duration('1ms'), 0.001)
  eq(parse.duration('1m'), parse.duration('1min'))
  ok(parse.duration('1m') ~= parse.duration('1ms'))
end)

test('nonsense is refused, with a message that says what to write instead', function()
  rejects(parse.duration, 'soon', 'not a duration I understand')
  rejects(parse.duration, '', 'not a duration I understand')
  rejects(parse.duration, '5 fortnights', 'not a unit')
  rejects(parse.duration, -1, 'positive')
  rejects(parse.duration, 0 / 0, 'positive')
  rejects(parse.duration, math.huge, 'positive')
  rejects(parse.duration, nil, 'number or a string')
  rejects(parse.duration, {}, 'number or a string')
end)

test('a rate is a count over a window', function()
  local count, window = parse.rate('5/10s')
  eq(count, 5)
  eq(window, 10)

  count, window = parse.rate('30/min')
  eq(count, 30)
  eq(window, 60)

  count, window = parse.rate('3/s')
  eq(count, 3)
  eq(window, 1, 'no number in front of the unit means one of it')

  count, window = parse.rate('100/1h')
  eq(count, 100)
  eq(window, 3600)
end)

test('a rate can also be two numbers, for anyone who prefers that', function()
  local count, window = parse.rate({ 5, 10 })
  eq(count, 5)
  eq(window, 10)
end)

test('a rate of zero would be a silent ban, so it is an error', function()
  rejects(parse.rate, '0/10s', 'at least one')
  rejects(parse.rate, { 0, 10 }, 'at least one')
  rejects(parse.rate, { 5, 0 }, 'longer than zero')
  rejects(parse.rate, { 5 }, 'count, seconds')
end)

test('and a rate that is not one says so', function()
  rejects(parse.rate, '5 per 10s', 'not a rate I understand')
  rejects(parse.rate, 'fast', 'not a rate I understand')
  rejects(parse.rate, '5/', 'not a rate I understand')
  rejects(parse.rate, 10, 'string or a table')
end)

test('fractional windows survive the round trip', function()
  local count, window = parse.rate('2/500ms')
  eq(count, 2)
  near(window, 0.5)
end)
