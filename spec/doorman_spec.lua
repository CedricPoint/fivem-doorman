local t = require('test.harness')
local Doorman = require('lib.doorman')

local test, eq, near, ok, no = t.test, t.eq, t.near, t.ok, t.no

--- A doorman whose clock the test holds.
local function at(start)
  local now = start or 0
  local logged = {}

  local d = Doorman.new({
    clock = function() return now end,
    log = function(entry) logged[#logged + 1] = entry end,
    policy = { warn = 3, kick = 5, window = 60 },
  })

  return d, function(seconds) now = now + seconds end, logged
end

test('a guarded event lets an honest call through', function()
  local d = at()
  d:guard('shop:buy', { schema = { item = 'string', count = { 'number', min = 1, integer = true } } })

  local verdict = d:inspect('shop:buy', 1, { item = 'bread', count = 2 })
  ok(verdict.allow)
end)

test('an event nobody guarded is refused, and nobody is blamed for it', function()
  local d = at()

  local verdict = d:inspect('shop:sell', 1, {})
  no(verdict.allow)
  eq(verdict.reason, 'unguarded')
  eq(verdict.offences, 0, 'this is the author forgetting a rule, not a player attacking')
end)

test('a payload of the wrong shape never reaches the handler', function()
  local d = at()
  d:guard('shop:buy', { schema = { item = 'string', count = { 'number', min = 1 } } })

  local verdict = d:inspect('shop:buy', 1, { item = 'bread', count = -5 })
  no(verdict.allow)
  eq(verdict.reason, 'schema')
  ok(verdict.detail:match('count'), 'the log says which field')
end)

test('the rate is per player and per event', function()
  local d, pass = at()
  d:guard('shop:buy', { rate = '3/10s' })

  for _ = 1, 3 do ok(d:inspect('shop:buy', 1, {}).allow) end
  no(d:inspect('shop:buy', 1, {}).allow, 'player 1 is out of budget')
  ok(d:inspect('shop:buy', 2, {}).allow, 'player 2 is not')

  d:guard('garage:take', { rate = '3/10s' })
  ok(d:inspect('garage:take', 1, {}).allow, 'and neither is the other event')

  pass(11)
  ok(d:inspect('shop:buy', 1, {}).allow, 'the window has moved on')
end)

test('a cooldown is the same thing said differently', function()
  local d, pass = at()
  d:guard('door:knock', { cooldown = '2s' })

  ok(d:inspect('door:knock', 1, {}).allow)

  local verdict = d:inspect('door:knock', 1, {})
  no(verdict.allow)
  eq(verdict.reason, 'cooldown')
  near(verdict.retry, 2, 1e-9)

  pass(1)
  no(d:inspect('door:knock', 1, {}).allow, 'still too soon')
  pass(1.01)
  ok(d:inspect('door:knock', 1, {}).allow)
end)

test('the shape is checked before the budget is spent', function()
  -- A client sending rubbish should not be able to use up an honest
  -- player's... well, their own allowance, but more to the point: a refused
  -- call should not count towards a limit it was never going to pass.
  local d = at()
  d:guard('shop:buy', { rate = '2/10s', schema = { item = 'string' } })

  for _ = 1, 10 do
    local verdict = d:inspect('shop:buy', 1, { item = 42 })
    eq(verdict.reason, 'schema', 'never "rate"')
  end

  ok(d:inspect('shop:buy', 1, { item = 'bread' }).allow, 'the budget is untouched')
  ok(d:inspect('shop:buy', 1, { item = 'bread' }).allow)
  no(d:inspect('shop:buy', 1, { item = 'bread' }).allow)
end)

test('refusals escalate to a warning and then to a kick', function()
  local d = at()
  d:guard('shop:buy', { rate = '1/60s' })

  eq(d:inspect('shop:buy', 1, {}).allow, true)
  eq(d:inspect('shop:buy', 1, {}).action, 'refuse')
  eq(d:inspect('shop:buy', 1, {}).action, 'refuse')
  eq(d:inspect('shop:buy', 1, {}).action, 'warn')
  eq(d:inspect('shop:buy', 1, {}).action, 'warn')
  eq(d:inspect('shop:buy', 1, {}).action, 'kick')
end)

test('every refusal is handed to the log, and nothing else is', function()
  local d, _, logged = at()
  d:guard('shop:buy', { rate = '1/60s', schema = { item = 'string' } })

  d:inspect('shop:buy', 7, { item = 'bread' })        -- through
  d:inspect('shop:buy', 7, { item = 'bread' })        -- over the rate
  d:inspect('shop:buy', 7, { item = 99 })             -- wrong shape

  eq(#logged, 2)
  eq(logged[1].event, 'shop:buy')
  eq(logged[1].source, 7)
  eq(logged[1].reason, 'rate')
  eq(logged[2].reason, 'schema')
  ok(logged[2].detail:match('item'))
end)

test('an exempt player skips the queue entirely', function()
  local d = at()
  d:guard('admin:teleport', {
    rate = '1/60s',
    exempt = function(source) return source == 99 end,
  })

  for _ = 1, 20 do ok(d:inspect('admin:teleport', 99, {}).allow) end
  ok(d:inspect('admin:teleport', 1, {}).allow)
  no(d:inspect('admin:teleport', 1, {}).allow)
end)

test('a player who leaves takes everything held about them with them', function()
  local d = at()
  d:guard('shop:buy', { rate = '2/60s' })
  d:guard('garage:take', { cooldown = '30s' })

  for source = 1, 50 do
    d:inspect('shop:buy', source, {})
    d:inspect('garage:take', source, {})
  end
  eq(d:report().tracked, 100)

  for source = 1, 50 do d:forget(source) end
  eq(d:report().tracked, 0, 'nothing is still being held for players who left')
end)

test('and a sweep catches whoever left without saying so', function()
  local d, pass = at()
  d:guard('shop:buy', { rate = '2/60s' })

  for source = 1, 10 do d:inspect('shop:buy', source, {}) end
  eq(d:report().tracked, 10)

  pass(1000)
  ok(d:sweep(300) >= 10)
  eq(d:report().tracked, 0)
end)

test('a rule with a mistake in it stops the resource, loudly', function()
  local d = at()

  t.raises(function() d:guard('a', { rate = 'quickly' }) end, 'rate for "a"')
  t.raises(function() d:guard('b', { cooldown = 'soonish' }) end, 'cooldown for "b"')
  t.raises(function() d:guard('c', { schema = { n = 'nubmer' } }) end, 'schema for "c"')
  t.raises(function() d:guard('d', { cooldown = 0 }) end, 'longer than zero')
  t.raises(function() d:guard('', {}) end, 'needs a name')
  t.raises(function() d:guard('e', 'nope') end, 'must be a table')

  d:guard('f', {})
  t.raises(function() d:guard('f', {}) end, 'already guarded')
end)

test('the report adds up', function()
  local d = at()
  d:guard('shop:buy', { rate = '2/10s', schema = { item = 'string' } })

  d:inspect('shop:buy', 1, { item = 'bread' })
  d:inspect('shop:buy', 1, { item = 'milk' })
  d:inspect('shop:buy', 1, { item = 'eggs' })      -- over the rate
  d:inspect('shop:buy', 2, { item = 404 })         -- wrong shape

  local report = d:report()
  eq(report.allowed, 2)
  eq(report.refused, 2)
  eq(#report.events, 1)
  eq(report.events[1].name, 'shop:buy')
  eq(report.events[1].allowed, 2)
  eq(report.events[1].refused, 2)
  eq(report.events[1].rate, '2 per 10s')
  eq(report.events[1].schema, true)
end)

test('the source is whatever the server says, never whatever the payload says', function()
  -- The one thing a client cannot forge is which player the event came from,
  -- so the key is built from it and the payload never gets a say.
  local d = at()
  d:guard('shop:buy', { rate = '1/60s', schema = { source = 'number' } })

  ok(d:inspect('shop:buy', 1, { source = 2 }).allow)
  no(d:inspect('shop:buy', 1, { source = 3 }).allow,
    'player 1 is out of budget however they label themselves')
  ok(d:inspect('shop:buy', 2, { source = 1 }).allow,
    'and player 2 still has theirs')
end)

test('escalation can be handed to somebody else entirely', function()
  -- On a server the tally belongs in one place, so each resource keeps its
  -- own rates and reports refusals outward rather than judging them.
  local reported = {}
  local d = Doorman.new({
    clock = function() return 0 end,
    policy = false,
    log = function(entry) reported[#reported + 1] = entry end,
  })
  d:guard('shop:buy', { rate = '1/60s' })

  d:inspect('shop:buy', 1, {})
  for _ = 1, 20 do
    local verdict = d:inspect('shop:buy', 1, {})
    eq(verdict.action, 'refuse', 'it never decides to kick on its own')
    eq(verdict.offences, 0)
  end

  eq(#reported, 20, 'but every one of them is reported')
  d:forget(1)
  d:sweep(1)
end)

test('a doorman with no clock given still works', function()
  local d = Doorman.new()
  d:guard('shop:buy', { rate = '2/60s' })

  ok(d:inspect('shop:buy', 1, {}).allow)
  ok(d:inspect('shop:buy', 1, {}).allow)
  no(d:inspect('shop:buy', 1, {}).allow)
end)
