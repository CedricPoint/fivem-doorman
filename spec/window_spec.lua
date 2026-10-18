local t = require('test.harness')
local Window = require('lib.window')

local test, eq, near, ok, no = t.test, t.eq, t.near, t.ok, t.no

test('it lets the first N through and then stops', function()
  local w = Window.new(3, 10)

  ok(w:allow('bob', 0))
  ok(w:allow('bob', 1))
  ok(w:allow('bob', 2))
  no(w:allow('bob', 3), 'the fourth is over the limit')
  no(w:allow('bob', 9))
end)

test('and says how long until the next one would fit', function()
  local w = Window.new(2, 10)

  w:allow('bob', 100)
  w:allow('bob', 104)

  local allowed, retry = w:allow('bob', 105)
  no(allowed)
  near(retry, 5, 1e-9, 'the oldest hit was at 100, so it leaves the window at 110')
end)

test('the window slides rather than resetting', function()
  local w = Window.new(2, 10)

  ok(w:allow('bob', 0))
  ok(w:allow('bob', 5))
  no(w:allow('bob', 9), 'both are still inside the window')

  ok(w:allow('bob', 10.1), 'the one at 0 has aged out')
  no(w:allow('bob', 11), 'the ones at 5 and 10.1 have not')
  ok(w:allow('bob', 15.1), 'now the one at 5 has')
end)

test('a fixed-window limiter would let double through at the seam; this does not', function()
  -- The classic bug: reset a counter every 10 seconds and someone sends the
  -- whole allowance at 9.9s and again at 10.1s. Twice the limit, no refusal.
  local w = Window.new(5, 10)

  for i = 1, 5 do ok(w:allow('bob', 9.9 + i * 0.001)) end
  for _ = 1, 5 do no(w:allow('bob', 10.1), 'the first five are still in the window') end
end)

test('players do not share a budget', function()
  local w = Window.new(1, 10)

  ok(w:allow('bob', 0))
  no(w:allow('bob', 0))
  ok(w:allow('alice', 0), 'alice has her own')
end)

test('counting does not consume the budget', function()
  local w = Window.new(3, 10)

  eq(w:count('bob', 0), 0)
  w:allow('bob', 0)
  eq(w:count('bob', 0), 1)
  eq(w:count('bob', 0), 1, 'asking twice does not add one')
  eq(w:count('bob', 11), 0, 'and it ages out like everything else')
end)

test('bump records whether or not it is over, and saturates at the limit', function()
  local w = Window.new(3, 10)

  eq(w:bump('bob', 0), 1)
  eq(w:bump('bob', 0), 2)
  eq(w:bump('bob', 0), 3)
  eq(w:bump('bob', 0), 3, 'saturated')
  eq(w:bump('bob', 0), 3)
end)

test('and the saturated list stays the size of the limit, under any load', function()
  -- An offender is exactly the person who could make this grow. If it grows,
  -- the counter is the leak.
  local w = Window.new(4, 60)

  for i = 1, 10000 do w:bump('bob', i * 0.001) end

  eq(w:count('bob', 10), 4, 'four timestamps held, not ten thousand')
end)

test('a saturated window still slides', function()
  local w = Window.new(2, 10)

  w:bump('bob', 0)
  w:bump('bob', 1)
  w:bump('bob', 2)   -- saturated: drops the one at 0, keeps 1 and 2

  eq(w:count('bob', 11.5), 1, 'only the one at 2 is still inside')
end)

test('forgetting a key frees what was held for it', function()
  local w = Window.new(5, 10)

  w:allow('bob', 0)
  w:allow('alice', 0)
  eq(w:tracked(), 2)

  w:forget('bob')
  eq(w:tracked(), 1)
  eq(w:count('bob', 0), 0)
  ok(w:allow('bob', 0), 'and the budget starts over')
end)

test('a sweep collects whoever stopped talking', function()
  local w = Window.new(5, 10)

  w:allow('bob', 0)
  w:allow('alice', 100)

  eq(w:sweep(130, 60), 1, 'bob has been quiet for 130 seconds, alice for 30')
  eq(w:tracked(), 1)

  eq(w:sweep(200, 60), 1)
  eq(w:tracked(), 0)
end)

test('a window that has gone quiet holds nothing of consequence', function()
  local w = Window.new(3, 10)

  for player = 1, 100 do
    w:allow('player' .. player, 0)
  end
  eq(w:tracked(), 100)

  w:sweep(3600, 300)
  eq(w:tracked(), 0)
end)

test('nonsense limits are refused when the window is built', function()
  t.raises(function() Window.new(0, 10) end, 'at least 1')
  t.raises(function() Window.new(-1, 10) end, 'at least 1')
  t.raises(function() Window.new(5, 0) end, 'greater than 0')
  t.raises(function() Window.new('five', 10) end, 'at least 1')
end)
