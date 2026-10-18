--[[
  What a payload is allowed to look like.

  Everything a client sends is attacker-controlled: the types, the sizes, the
  shape and the numbers. A handler that does `inventory[data.slot] = data.item`
  trusts four separate things, and a client that sends
  {slot = 0/0, item = string.rep('a', 2^20)} breaks all four at once.

  So the limits here are not only about correctness:

    · NaN and infinity are refused outright. `0/0` compares false against
      every bound you could write, so `min`/`max` alone will not stop it, and
      it poisons any total it reaches.
    · Strings are measured in bytes, with a limit whether or not one was
      asked for.
    · Tables have a depth limit and an entry limit, because the cheapest
      denial of service against a Lua server is a deeply nested table.
    · Unknown keys are refused rather than ignored, so a payload cannot smuggle
      a field past a handler that iterates with pairs().
]]

local schema = {}

-- Applied whether or not the rule asks for them. A rule may lower them; the
-- point is that forgetting to write a limit is not the same as allowing
-- anything.
local MAX_DEPTH = 8
local MAX_STRING = 512
local MAX_ENTRIES = 64

local KINDS = {
  string = true,
  number = true,
  boolean = true,
  table = true,
  any = true,
}

local function fail(path, message)
  if path == '' then return false, message end
  return false, ('%s: %s'):format(path, message)
end

local function join(path, key)
  if path == '' then return tostring(key) end
  if type(key) == 'number' then return ('%s[%d]'):format(path, key) end
  return ('%s.%s'):format(path, key)
end

--- Accepts 'string', 'string?', or a table whose [1] is the kind.
--- @return table|nil rule, string|nil error
local function normalise(spec)
  if type(spec) == 'string' then
    local kind, optional = spec:match('^(%a+)(%??)$')
    if not kind or not KINDS[kind] then
      return nil, ('"%s" is not a type I know (string, number, boolean, table, any)'):format(spec)
    end
    return { kind = kind, optional = optional == '?' }
  end

  if type(spec) ~= 'table' then
    return nil, ('a rule must be a string or a table, got %s'):format(type(spec))
  end

  -- A plain map of field names is shorthand for a strict table of those fields.
  if spec[1] == nil then
    return { kind = 'table', fields = spec, strict = true, optional = false }
  end

  local kind = spec[1]
  if type(kind) ~= 'string' or not KINDS[kind] then
    return nil, ('"%s" is not a type I know (string, number, boolean, table, any)'):format(tostring(kind))
  end

  local rule = {
    kind = kind,
    optional = spec.optional == true,
    min = spec.min,
    max = spec.max,
    integer = spec.integer,
    pattern = spec.pattern,
    oneof = spec.oneof,
    fields = spec.fields,
    of = spec.of,
    strict = spec.strict ~= false,
  }

  if rule.fields and rule.of then
    return nil, 'a table rule takes either `fields` or `of`, not both'
  end

  return rule
end

local check  -- forward declaration, it recurses

--- A value nobody described, checked for shape alone: how deep it goes and
--- how much it holds.
---
--- `any` and a bare `table` are the two places a rule stops describing the
--- payload, and so the two places a nested bomb would otherwise walk
--- straight in. The work here is bounded by the size of the payload, because
--- it gives up at the first level that is too wide.
local function scan(value, path, depth)
  if type(value) ~= 'table' then return true end

  if depth > MAX_DEPTH then
    return fail(path, ('is nested deeper than the %d levels allowed'):format(MAX_DEPTH))
  end

  local entries = 0
  for key, item in pairs(value) do
    entries = entries + 1
    if entries > MAX_ENTRIES then
      return fail(path, ('has more than the %d entries allowed'):format(MAX_ENTRIES))
    end

    local ok, err = scan(item, join(path, key), depth + 1)
    if not ok then return false, err end
  end

  return true
end

local function check_number(value, rule, path)
  if type(value) ~= 'number' then
    return fail(path, ('expected a number, got %s'):format(type(value)))
  end

  -- NaN is not equal to itself, and no bound rejects it.
  if value ~= value then
    return fail(path, 'is not a number (NaN)')
  end
  if value == math.huge or value == -math.huge then
    return fail(path, 'is infinite')
  end

  if rule.integer and value % 1 ~= 0 then
    return fail(path, ('expected a whole number, got %s'):format(tostring(value)))
  end
  if rule.min and value < rule.min then
    return fail(path, ('must be at least %s, got %s'):format(rule.min, value))
  end
  if rule.max and value > rule.max then
    return fail(path, ('must be at most %s, got %s'):format(rule.max, value))
  end

  return true
end

local function check_string(value, rule, path)
  if type(value) ~= 'string' then
    return fail(path, ('expected a string, got %s'):format(type(value)))
  end

  local limit = rule.max or MAX_STRING
  if limit > MAX_STRING then limit = MAX_STRING end

  if #value > limit then
    return fail(path, ('is %d bytes, longer than the %d allowed'):format(#value, limit))
  end
  if rule.min and #value < rule.min then
    return fail(path, ('is %d bytes, shorter than the %d required'):format(#value, rule.min))
  end
  if rule.pattern and not value:match(rule.pattern) then
    return fail(path, ('does not match %s'):format(rule.pattern))
  end

  if rule.oneof then
    for _, allowed in ipairs(rule.oneof) do
      if value == allowed then return true end
    end
    return fail(path, ('is not one of %s'):format(table.concat(rule.oneof, ', ')))
  end

  return true
end

local function check_table(value, rule, path, depth)
  if type(value) ~= 'table' then
    return fail(path, ('expected a table, got %s'):format(type(value)))
  end
  if depth > MAX_DEPTH then
    return fail(path, ('is nested deeper than %d levels'):format(MAX_DEPTH))
  end

  local entries = 0
  for _ in pairs(value) do entries = entries + 1 end

  local limit = rule.max or MAX_ENTRIES
  if limit > MAX_ENTRIES then limit = MAX_ENTRIES end

  if entries > limit then
    return fail(path, ('has %d entries, more than the %d allowed'):format(entries, limit))
  end
  if rule.min and entries < rule.min then
    return fail(path, ('has %d entries, fewer than the %d required'):format(entries, rule.min))
  end

  -- A list: every value matches `of`, and the keys are 1..n with no holes.
  if rule.of then
    for index = 1, entries do
      if value[index] == nil then
        return fail(path, ('is meant to be a list, but there is nothing at %d'):format(index))
      end
      local ok, err = check(value[index], rule.of, join(path, index), depth + 1)
      if not ok then return false, err end
    end
    return true
  end

  if rule.fields then
    for key, sub in pairs(rule.fields) do
      local ok, err = check(value[key], sub, join(path, key), depth + 1)
      if not ok then return false, err end
    end

    if rule.strict then
      for key in pairs(value) do
        if rule.fields[key] == nil then
          return fail(join(path, key), 'is not a field this event accepts')
        end
      end
    end

    return true
  end

  -- A bare `table` rule describes nothing about what is inside it, so the
  -- only thing left to check is that what is inside it is not a bomb.
  return scan(value, path, depth)
end

--- @return boolean ok, string|nil error
function check(value, spec, path, depth)
  local rule, err = normalise(spec)
  if not rule then return fail(path, err) end

  if value == nil then
    if rule.optional then return true end
    return fail(path, 'is missing')
  end

  if rule.kind == 'any' then return scan(value, path, depth) end
  if rule.kind == 'number' then return check_number(value, rule, path) end
  if rule.kind == 'string' then return check_string(value, rule, path) end

  if rule.kind == 'boolean' then
    if type(value) ~= 'boolean' then
      return fail(path, ('expected true or false, got %s'):format(type(value)))
    end
    return true
  end

  return check_table(value, rule, path, depth)
end

--- Does this value match this rule?
--- @return boolean ok, string|nil why_not
function schema.check(value, spec)
  return check(value, spec, '', 1)
end

--- Is this rule itself well formed? Called once when an event is guarded, so
--- that a typo in a rule is a startup error rather than a surprise at 2am.
--- @return boolean ok, string|nil error
function schema.valid(spec, path)
  path = path or ''

  local rule, err = normalise(spec)
  if not rule then return fail(path, err) end

  if rule.kind ~= 'table' then
    if rule.fields or rule.of then
      return fail(path, ('`%s` only applies to a table'):format(rule.fields and 'fields' or 'of'))
    end
    return true
  end

  if rule.of then
    return schema.valid(rule.of, join(path, 'of'))
  end

  if rule.fields then
    if type(rule.fields) ~= 'table' then
      return fail(path, '`fields` must be a table of rules')
    end
    for key, sub in pairs(rule.fields) do
      local ok, sub_err = schema.valid(sub, join(path, key))
      if not ok then return false, sub_err end
    end
  end

  return true
end

schema.limits = { depth = MAX_DEPTH, string = MAX_STRING, entries = MAX_ENTRIES }

return schema
