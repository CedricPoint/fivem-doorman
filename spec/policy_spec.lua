local t = require('test.harness')
local Policy = require('lib.policy')

local test, eq, ok = t.test, t.eq, t.ok

test('one refusal is not worth acting on', function()
  local p = Policy.new({ warn = 3, kick = 10, window = 60 })

  eq(p:record(1, 0), 'none')
  eq(p:record(1, 1), 'none')
end)

test('a few in a row is worth a word', function()
  local p = Policy.new({ warn = 3, kick = 10, window = 60 })

  p:record(1, 0)
  p:record(1, 1)

  local action, count = p:record(1, 2)
  eq(action, 'warn')
  eq(count, 3)
end)

test('and a lot of them is worth a boot', function()
  local p = Policy.new({ warn = 3, kick = 5, window = 60 })

  for i = 1, 4 do p:record(1, i) end
  eq(p:record(1, 5), 'kick')
end)

test('offences age out, so an honest player is not banked against', function()
  local p = Policy.new({ warn = 3, kick = 10, window = 60 })

  p:record(1, 0)
  p:record(1, 1)
  eq(p:count(1, 2), 2)

  -- Two hours later, after a reconnect and a laggy moment.
  eq(p:count(1, 7200), 0)
  eq(p:record(1, 7200), 'none')
end)

test('the tally is kept per player', function()
  local p = Policy.new({ warn = 2, kick = 10, window = 60 })

  p:record(1, 0)
  eq(p:record(2, 0), 'none', 'player 2 has one offence, not two')
  eq(p:record(1, 0), 'warn')
end)

test('the tally is NOT kept per event', function()
  -- Somebody being careful spreads themselves over ten events and stays
  -- under every individual limit. The point of counting centrally is that
  -- this does not work.
  local p = Policy.new({ warn = 3, kick = 10, window = 60 })

  p:record(1, 0)   -- refused on shop:buy
  p:record(1, 0)   -- refused on garage:take
  eq(p:record(1, 0), 'warn', 'three different events, one player, one tally')
end)

test('kicking can be switched off for a server that only wants to log', function()
  local p = Policy.new({ warn = 2, kick = false, window = 60 })

  p:record(1, 0)
  for i = 1, 50 do
    eq(p:record(1, i * 0.01), 'warn', 'it warns and goes on warning, but never kicks')
  end
end)

test('false is a value, not a missing argument', function()
  -- `opts.kick or 10` reads beautifully and is wrong: it turns "never kick"
  -- into "kick at 10". This is the test that caught it.
  local p = Policy.new({ warn = 1, kick = false })
  for i = 1, 100 do
    eq(p:record(1, i * 0.001), 'warn')
  end
end)

test('forgetting a player clears what stood against them', function()
  local p = Policy.new({ warn = 2, kick = 10, window = 60 })

  p:record(1, 0)
  p:record(1, 0)
  eq(p:count(1, 0), 2)

  p:forget(1)
  eq(p:count(1, 0), 0)
  eq(p:record(1, 0), 'none')
end)

test('a flood of offences does not become a flood of memory', function()
  local p = Policy.new({ warn = 3, kick = 10, window = 60 })

  for i = 1, 50000 do p:record(1, i * 0.0001) end

  eq(p:count(1, 5), 10, 'the count stops at the threshold it had to detect')
  eq(p:record(1, 5), 'kick', 'and it still says the right thing')
end)

test('a policy that could never kick is a mistake worth refusing', function()
  t.raises(function() Policy.new({ warn = 10, kick = 3 }) end, 'at least as large as warn')
  t.raises(function() Policy.new({ warn = 0 }) end, 'at least 1')
end)

test('the defaults are sane without being asked for', function()
  local p = Policy.new()

  for i = 1, 2 do eq(p:record(1, i), 'none') end
  eq(p:record(1, 3), 'warn')
  for i = 4, 9 do p:record(1, i) end
  eq(p:record(1, 10), 'kick')
end)

test('a sweep forgets whoever has gone', function()
  local p = Policy.new({ window = 60 })

  p:record(1, 0)
  p:record(2, 500)

  eq(p:sweep(600, 300), 1)
  ok(p:count(2, 600) >= 0)
end)
