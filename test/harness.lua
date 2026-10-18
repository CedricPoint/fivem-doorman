--[[
  A test runner in eighty lines.

  Busted is the usual answer, and it is a good one, but it means LuaRocks on
  every machine that wants to check a change to a FiveM resource. This asks
  for a `lua` binary and nothing else, which is the same promise the library
  itself makes.
]]

local harness = { tests = {}, failures = {}, file = '?' }

local colour = os.getenv('NO_COLOR') == nil and os.getenv('TERM') ~= 'dumb'
local function paint(code, text)
  if not colour then return text end
  return ('\27[%sm%s\27[0m'):format(code, text)
end

function harness.file_is(name)
  harness.file = name
end

function harness.test(name, fn)
  harness.tests[#harness.tests + 1] = { name = name, fn = fn, file = harness.file }
end

--- Render a value so a failure message is actually readable.
local function show(value, depth)
  depth = depth or 0

  if type(value) == 'string' then
    if #value > 60 then
      return ('%q… (%d bytes)'):format(value:sub(1, 60), #value)
    end
    return ('%q'):format(value)
  end

  if type(value) ~= 'table' then return tostring(value) end
  if depth > 2 then return '{…}' end

  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = tostring(key) end
  table.sort(keys)

  local parts = {}
  for _, key in ipairs(keys) do
    local raw = value[key] ~= nil and value[key] or value[tonumber(key)]
    parts[#parts + 1] = ('%s = %s'):format(key, show(raw, depth + 1))
  end

  return '{ ' .. table.concat(parts, ', ') .. ' }'
end

harness.show = show

local function blame(message)
  error({ doorman_assert = message }, 3)
end

function harness.eq(got, want, note)
  if got ~= want then
    blame(('expected %s, got %s%s'):format(show(want), show(got), note and ('  (%s)'):format(note) or ''))
  end
end

function harness.near(got, want, slack, note)
  if type(got) ~= 'number' or math.abs(got - want) > (slack or 1e-9) then
    blame(('expected about %s, got %s%s'):format(show(want), show(got), note and ('  (%s)'):format(note) or ''))
  end
end

function harness.ok(value, note)
  if not value then
    blame(('expected something truthy, got %s%s'):format(show(value), note and ('  (%s)'):format(note) or ''))
  end
end

function harness.no(value, note)
  if value then
    blame(('expected false or nil, got %s%s'):format(show(value), note and ('  (%s)'):format(note) or ''))
  end
end

--- The call must fail, and the message must mention `pattern`.
function harness.raises(fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    blame(('expected this to raise, and it did not'))
  end

  err = type(err) == 'table' and (err.doorman_assert or '?') or tostring(err)
  if pattern and not err:match(pattern) then
    blame(('raised %s, which does not mention %s'):format(show(err), show(pattern)))
  end
end

--- Shorthand for the pair every validator in here returns.
function harness.refused(ok, err, pattern)
  if ok then
    blame(('expected a refusal, got one through with %s'):format(show(err)))
  end
  if pattern and not tostring(err):match(pattern) then
    blame(('refused with %s, which does not mention %s'):format(show(err), show(pattern)))
  end
end

function harness.accepted(ok, err)
  if not ok then
    blame(('expected this through, it was refused: %s'):format(show(err)))
  end
end

function harness.run()
  local passed, current = 0, nil

  for _, test in ipairs(harness.tests) do
    if test.file ~= current then
      current = test.file
      print(paint('1', '\n  ' .. current))
    end

    local ok, err = pcall(test.fn)

    if ok then
      passed = passed + 1
      print(('    %s %s'):format(paint('32', '✓'), test.name))
    else
      local message = type(err) == 'table' and err.doorman_assert or tostring(err)
      harness.failures[#harness.failures + 1] = { name = test.name, file = test.file, message = message }
      print(('    %s %s'):format(paint('31', '✗'), test.name))
      print(('        %s'):format(paint('31', message)))
    end
  end

  print(('\n  %d passed, %d failed, %d total\n'):format(passed, #harness.failures, #harness.tests))

  return #harness.failures == 0
end

return harness
