local t = require('test.harness')
local schema = require('lib.schema')

local test, eq, ok, no = t.test, t.eq, t.ok, t.no
local accepted, refused = t.accepted, t.refused

local function check(value, spec)
  return schema.check(value, spec)
end

local function passes(value, spec)
  accepted(check(value, spec))
end

local function fails(value, spec, pattern)
  local allowed, err = check(value, spec)
  refused(allowed, err, pattern)
end

test('the shorthand covers the common case', function()
  passes({ item = 'bread', count = 2 }, { item = 'string', count = 'number' })
  fails({ item = 'bread' }, { item = 'string', count = 'number' }, 'count: is missing')
  fails({ item = 7, count = 2 }, { item = 'string', count = 'number' }, 'item: expected a string')
end)

test('a question mark means the field may be absent', function()
  passes({ item = 'bread' }, { item = 'string', note = 'string?' })
  passes({ item = 'bread', note = 'for later' }, { item = 'string', note = 'string?' })
  fails({ item = 'bread', note = 7 }, { item = 'string', note = 'string?' },
    'note: expected a string')
end)

test('NaN is not a number, whatever its type says', function()
  -- 0/0 is a number to type(), and it compares false against every bound you
  -- could write, so min and max will not catch it. Anything it is added to
  -- becomes NaN too.
  fails({ n = 0 / 0 }, { n = { 'number', min = 0, max = 10 } }, 'NaN')
  fails({ n = 0 / 0 }, { n = 'number' }, 'NaN')
end)

test('and neither is infinity', function()
  fails({ n = math.huge }, { n = 'number' }, 'infinite')
  fails({ n = -math.huge }, { n = 'number' }, 'infinite')
  fails({ n = math.huge }, { n = { 'number', max = 100 } }, 'infinite')
end)

test('bounds are inclusive and the message says which way it went', function()
  passes({ n = 1 }, { n = { 'number', min = 1, max = 10 } })
  passes({ n = 10 }, { n = { 'number', min = 1, max = 10 } })
  fails({ n = 0 }, { n = { 'number', min = 1, max = 10 } }, 'at least 1')
  fails({ n = 11 }, { n = { 'number', min = 1, max = 10 } }, 'at most 10')
end)

test('a count of 2.5 items is refused when it is asked to be whole', function()
  passes({ n = 3 }, { n = { 'number', integer = true } })
  passes({ n = -3 }, { n = { 'number', integer = true } })
  fails({ n = 2.5 }, { n = { 'number', integer = true } }, 'whole number')
end)

test('strings are measured in bytes, and there is a ceiling either way', function()
  passes({ s = string.rep('a', 10) }, { s = { 'string', max = 10 } })
  fails({ s = string.rep('a', 11) }, { s = { 'string', max = 10 } }, 'longer than the 10')

  -- No max asked for: the default still applies. A megabyte of 'a' is a
  -- perfectly ordinary thing for a client to send.
  fails({ s = string.rep('a', 1024 * 1024) }, { s = 'string' }, 'longer than the 512')

  -- And a rule cannot raise the ceiling past the built-in one.
  fails({ s = string.rep('a', 5000) }, { s = { 'string', max = 100000 } }, 'longer than the 512')
end)

test('patterns and fixed sets', function()
  passes({ id = 'weapon_pistol' }, { id = { 'string', pattern = '^[%l_]+$' } })
  fails({ id = 'weapon pistol' }, { id = { 'string', pattern = '^[%l_]+$' } }, 'does not match')

  passes({ side = 'left' }, { side = { 'string', oneof = { 'left', 'right' } } })
  fails({ side = 'up' }, { side = { 'string', oneof = { 'left', 'right' } } }, 'not one of left, right')
end)

test('a field nobody declared is refused, not ignored', function()
  -- A handler that walks the payload with pairs() will happily act on a key
  -- the author never thought about.
  fails({ item = 'bread', isAdmin = true }, { item = 'string' },
    'isAdmin: is not a field this event accepts')
end)

test('unless the rule says it does not mind', function()
  passes({ item = 'bread', extra = 1 }, { 'table', fields = { item = 'string' }, strict = false })
end)

test('a table bomb is refused on depth, wherever the rule stops describing it', function()
  -- Twelve levels of {}: a few bytes to send, and the classic way to take a
  -- Lua server down with one event. A strict rule already refuses it on the
  -- unknown key — the hole is the two rules that stop describing the payload.
  local deep = {}
  local node = deep
  for _ = 1, 12 do
    node.next = {}
    node = node.next
  end

  fails(deep, { 'table' }, 'nested deeper')
  fails({ payload = deep }, { payload = 'any' }, 'nested deeper')
  fails({ deep }, { 'table', of = 'any' }, 'nested deeper')

  passes({ a = { b = { c = 1 } } }, { 'table' })
end)

test('and on width, in the same two places', function()
  local wide = {}
  for i = 1, 200 do wide['k' .. i] = i end

  fails(wide, { 'table' }, 'more than the 64')
  fails({ payload = wide }, { payload = 'any' }, 'more than the 64')
end)

test('and on how many entries it holds', function()
  local wide = {}
  for i = 1, 100 do wide[i] = i end

  fails(wide, { 'table', of = 'number' }, 'more than the 64')
  fails(wide, { 'table', of = 'number', max = 10 }, 'more than the 10')
end)

test('a list must actually be a list', function()
  passes({ 1, 2, 3 }, { 'table', of = 'number', max = 3 })
  fails({ 1, 2, nil, 4 }, { 'table', of = 'number' }, 'nothing at')
  fails({ a = 1 }, { 'table', of = 'number' }, 'nothing at 1')
  fails({ 1, 'two' }, { 'table', of = 'number' }, '[2]: expected a number')
end)

test('nested rules report the path to what went wrong', function()
  local spec = {
    player = { 'table', fields = { id = 'number', name = { 'string', max = 24 } } },
    items = { 'table', of = { 'table', fields = { name = 'string', count = { 'number', min = 1 } } }, max = 3 },
  }

  passes({
    player = { id = 1, name = 'bob' },
    items = { { name = 'bread', count = 2 } },
  }, spec)

  fails({ player = { id = 1, name = 'bob' }, items = { { name = 'bread', count = 0 } } },
    spec, 'items%[1%].count: must be at least 1')

  fails({ player = { id = 'one', name = 'bob' }, items = {} },
    spec, 'player%.id: expected a number')
end)

test('booleans are booleans, not truthy things', function()
  passes({ b = false }, { b = 'boolean' })
  fails({ b = 'true' }, { b = 'boolean' }, 'expected true or false')
  fails({ b = 1 }, { b = 'boolean' }, 'expected true or false')
end)

test('`any` lets a value through but still has to be there', function()
  passes({ x = { 1, 2 } }, { x = 'any' })
  passes({ x = 'whatever' }, { x = 'any' })
  fails({}, { x = 'any' }, 'is missing')
  passes({}, { x = 'any?' })
end)

test('a payload that is not a table at all', function()
  fails('just a string', { item = 'string' }, 'expected a table')
  fails(nil, { item = 'string' }, 'is missing')
end)

test('a rule with a typo in it is caught before the server starts', function()
  ok(schema.valid({ item = 'string', count = { 'number', min = 1 } }))

  local valid, err = schema.valid({ item = 'strign' })
  no(valid)
  ok(err:match('strign'), 'the message names the typo')

  no(schema.valid({ 'number', fields = { a = 'string' } }), 'fields only applies to a table')
  no(schema.valid({ 'table', fields = { a = 'string' }, of = 'string' }), 'fields or of, not both')
  no(schema.valid({ 'table', of = 'nubmer' }), 'a typo inside a list rule is caught too')
  no(schema.valid({ 'table', fields = { a = { 'table', fields = { b = 'strnig' } } } }),
    'and one nested a few levels down')
end)

test('the built-in ceilings are published, so they can be relied on', function()
  eq(schema.limits.depth, 8)
  eq(schema.limits.string, 512)
  eq(schema.limits.entries, 64)
end)
