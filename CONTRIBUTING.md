# Contributing

## A payload that got through

The most useful thing you can send. Open an issue with:

- the **rule** you wrote,
- the **payload** that got past it,
- what your handler then did with it.

If it reached your handler and should not have, that is a bug in doorman and
it will get a test named after it.

## Running the tests

You need a `lua` binary. Nothing else — no LuaRocks, no busted, no server.

```bash
lua test/run.lua            # all 93
lua test/run.lua schema     # only the specs whose name contains "schema"
```

On Debian or Ubuntu: `sudo apt install lua5.4`.

## The shape, and why it is that shape

```
lib/        decides things. Pure Lua, no natives, clock passed in.
server/     touches the game. Natives passed in as a table.
spec/       one file per lib file, plus one for the wiring.
test/       an eighty-line runner.
```

The split is not decoration. It is the reason the suite can run the real
files rather than a copy of them: `lib/` has nothing in it that needs a
server, and `server/resource.lua` takes `register`, `kick`, `now`, `print`
and `every` as arguments, so a spec hands it a fake and watches what it
does.

**If you add logic, it goes in `lib/`.** If a change cannot be tested, that
is usually a sign it is on the wrong side of the line.

## Writing a test

No framework, just three helpers:

```lua
local t = require('test.harness')
local test, eq, ok, no = t.test, t.eq, t.ok, t.no

test('what it should do, as a sentence', function()
  eq(thing(), 'expected')
  ok(other())
  no(third())
  t.raises(function() bad() end, 'part of the message')
end)
```

Name the test after the behaviour, not the function: `a fixed-window limiter
would let double through at the seam; this does not` is worth more than
`test_window_3`.

New spec files go in `SPECS` in `test/run.lua`. Lua has no portable way to
list a directory, and a spec that silently stops running is worse than one
you have to add to a list.

## Timing

Never sleep in a test. Every rate-limited thing takes `now` as an argument
and every spec passes a number it controls, which is why the suite runs in
well under a second and never flakes on a slow runner.

## Style

Two-space indent, single quotes, `snake_case` for locals and fields,
`PascalCase` for the few things that are classes. Comments explain why, not
what. If a comment is only restating the line under it, delete one of them.

Keep it standalone: no framework, no dependency, nothing from LuaRocks. That
is most of the reason anyone would pick this up.

## Before you open the PR

```bash
lua test/run.lua
luac -p $(find . -name '*.lua')     # everything still parses
```

CI runs the suite on Lua 5.3 and 5.4, checks every file parses, and runs
luacheck.
