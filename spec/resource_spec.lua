local t = require('test.harness')
local resource = require('server.resource')

local test, eq, ok, no = t.test, t.eq, t.ok, t.no

--- A server, as far as the resource can tell.
local function fake()
  local game = {
    clock = 0,
    events = {},
    kicked = {},
    printed = {},
    timers = {},
  }

  game.now = function() return game.clock end
  game.register = function(event, handler) game.events[event] = handler end
  game.kick = function(source, reason) game.kicked[#game.kicked + 1] = { source = source, reason = reason } end
  game.name = function(source) return ('Player%s'):format(source) end
  game.print = function(line) game.printed[#game.printed + 1] = line end
  game.every = function(seconds, fn) game.timers[#game.timers + 1] = { seconds = seconds, fn = fn } end

  --- Pretend a client fired an event.
  game.fire = function(event, source, payload)
    local handler = game.events[event]
    if not handler then error(('nothing is listening on "%s"'):format(event)) end
    return handler(source, payload)
  end

  game.pass = function(seconds) game.clock = game.clock + seconds end

  return game
end

test('a guarded event reaches the handler, once, with what was sent', function()
  local game = fake()
  local r = resource.new(game)
  local seen = {}

  r:on('shop:buy', { schema = { item = 'string' } }, function(source, payload)
    seen[#seen + 1] = { source = source, item = payload.item }
  end)

  game.fire('shop:buy', 7, { item = 'bread' })

  eq(#seen, 1)
  eq(seen[1].source, 7)
  eq(seen[1].item, 'bread')
end)

test('and a refused one does not reach it at all', function()
  local game = fake()
  local r = resource.new(game)
  local calls = 0

  r:on('shop:buy', { rate = '2/10s', schema = { item = 'string' } }, function()
    calls = calls + 1
  end)

  game.fire('shop:buy', 7, { item = 'bread' })
  game.fire('shop:buy', 7, { item = 'bread' })
  game.fire('shop:buy', 7, { item = 'bread' })   -- over the rate
  game.fire('shop:buy', 7, { item = 1234 })      -- wrong shape
  game.fire('shop:buy', 7, 'not even a table')

  eq(calls, 2, 'the handler ran for the two that were allowed, and no others')
end)

test('a handler that throws does not take the guard with it', function()
  local game = fake()
  local r = resource.new(game)

  r:on('shop:buy', { rate = '5/10s' }, function() error('resource bug') end)

  no(pcall(game.fire, 'shop:buy', 1, {}), 'the error surfaces, as it should')
  no(pcall(game.fire, 'shop:buy', 1, {}))
  ok(select(1, pcall(game.fire, 'shop:buy', 1, {})) == false)
end)

test('every refusal is printed, with who and why', function()
  local game = fake()
  local r = resource.new(game)

  r:on('shop:buy', { rate = '1/60s' }, function() end)

  game.fire('shop:buy', 7, {})
  game.fire('shop:buy', 7, {})

  eq(#game.printed, 1)
  ok(game.printed[1]:match('Player7'), 'the name, not just the id')
  ok(game.printed[1]:match('shop:buy'))
  ok(game.printed[1]:match('rate'))
end)

test('a persistent offender is dropped, once, with a reason they can read', function()
  local game = fake()
  local r = resource.new(game, { policy = { warn = 2, kick = 4, window = 60 } })

  r:on('shop:buy', { rate = '1/60s' }, function() end)

  for _ = 1, 5 do game.fire('shop:buy', 7, {}) end

  eq(#game.kicked, 1)
  eq(game.kicked[1].source, 7)
  ok(game.kicked[1].reason:match('doorman'), 'the player is told what dropped them')
  ok(game.kicked[1].reason:match('server owner'), 'and what to do if it is wrong')
end)

test('a server that only wants to watch can turn kicking off', function()
  local game = fake()
  local r = resource.new(game, { policy = { warn = 2, kick = false } })

  r:on('shop:buy', { rate = '1/60s' }, function() end)
  for _ = 1, 30 do game.fire('shop:buy', 7, {}) end

  eq(#game.kicked, 0)
  ok(#game.printed >= 29, 'it still says so, every time')
end)

test('refusals can be handed onward, for a tally kept somewhere else', function()
  local game = fake()
  local sent = {}
  local r = resource.new(game, {
    policy = false,
    report = function(entry) sent[#sent + 1] = entry end,
  })

  r:on('shop:buy', { rate = '1/60s' }, function() end)

  game.fire('shop:buy', 7, {})
  game.fire('shop:buy', 7, {})
  game.fire('shop:buy', 7, {})

  eq(#sent, 2)
  eq(sent[1].source, 7)
  eq(sent[1].event, 'shop:buy')
  eq(#game.kicked, 0, 'judging is not its job any more')
end)

test('and a reporter that throws still leaves a line in the console', function()
  local game = fake()
  local r = resource.new(game, {
    policy = false,
    report = function() error('the ledger is down') end,
  })

  r:on('shop:buy', { rate = '1/60s' }, function() end)

  game.fire('shop:buy', 7, {})
  no(pcall(game.fire, 'shop:buy', 7, {}))
  eq(#game.printed, 1, 'the refusal was printed before the reporter blew up')
end)

test('the source comes from the server, so two players do not share a budget', function()
  local game = fake()
  local r = resource.new(game)
  local served = {}

  r:on('shop:buy', { rate = '1/60s' }, function(source) served[#served + 1] = source end)

  game.fire('shop:buy', 1, {})
  game.fire('shop:buy', 2, {})
  game.fire('shop:buy', 1, {})

  eq(#served, 2)
  eq(served[1], 1)
  eq(served[2], 2)
end)

test('a player who leaves is forgotten, and comes back with a clean budget', function()
  local game = fake()
  local r = resource.new(game)
  local calls = 0

  r:on('shop:buy', { rate = '1/60s' }, function() calls = calls + 1 end)

  game.fire('shop:buy', 7, {})
  game.fire('shop:buy', 7, {})
  eq(calls, 1)

  r:dropped(7)

  game.fire('shop:buy', 7, {})
  eq(calls, 2, 'slot 7 is somebody else now, and they have done nothing wrong')
end)

test('a sweep is scheduled, and it does let go', function()
  local game = fake()
  local r = resource.new(game, { sweep = 300, idle = 600 })

  r:on('shop:buy', { rate = '2/60s' }, function() end)

  eq(#game.timers, 1)
  eq(game.timers[1].seconds, 300)

  for source = 1, 20 do game.fire('shop:buy', source, {}) end
  eq(r.doorman:report().tracked, 20)

  game.pass(3600)
  game.timers[1].fn()

  eq(r.doorman:report().tracked, 0, 'the crashed clients were let go of')
end)

test('a server with no timers still works, it just never sweeps', function()
  local game = fake()
  game.every = nil

  local r = resource.new(game)
  r:on('shop:buy', { rate = '2/60s' }, function() end)

  game.fire('shop:buy', 1, {})
  eq(r.doorman:report().allowed, 1)
end)

test('the console command says something useful before anything has happened', function()
  local game = fake()
  local r = resource.new(game)

  local lines = r:lines()
  eq(#lines, 2)
  ok(lines[2]:match('no events are guarded'))
end)

test('and afterwards it lays out every event and its limits', function()
  local game = fake()
  local r = resource.new(game)

  r:on('shop:buy', { rate = '5/10s', schema = { item = 'string' } }, function() end)
  r:on('door:knock', { cooldown = '2s' }, function() end)

  game.fire('shop:buy', 1, { item = 'bread' })
  game.fire('door:knock', 1, {})
  game.fire('door:knock', 1, {})

  local text = table.concat(r:lines(), '\n')

  ok(text:match('2 allowed'))
  ok(text:match('1 refused'))
  ok(text:match('shop:buy'))
  ok(text:match('5 per 10s'))
  ok(text:match('cooldown 2s'))
  ok(text:match('schema'))
end)

test('forgetting to pass a handler is caught at startup', function()
  local game = fake()
  local r = resource.new(game)

  t.raises(function() r:on('shop:buy', { rate = '1/s' }) end, 'must be a function')
  t.raises(function() r:on('shop:buy', { rate = 'whenever' }, function() end) end, 'rate for')
end)
