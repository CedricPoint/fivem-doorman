--[[
  The decision, with nothing from the game in it.

  This file knows about rules, players, clocks and verdicts. It does not know
  about RegisterNetEvent, DropPlayer or print — those live in server/, behind
  the three things this takes: a clock, a log sink and a kick function.

  That split is the whole reason this project can be tested. Everything that
  decides anything is here and runs under a plain `lua` binary; what is left
  over is a hundred lines of wiring that can only be exercised on a server.
]]

local parse = require('lib.parse')
local schema = require('lib.schema')
local policy = require('lib.policy')
local Window = require('lib.window')

local Doorman = {}
Doorman.__index = Doorman

local function nothing() end

--- @param opts table|nil
---   clock   function  -> seconds, monotonic. Defaults to os.clock().
---   log     function(entry)  called for every refusal
---   policy  table     passed to Policy.new, or false to not escalate at all
---
--- `policy = false` is for the case where something else owns the tally. On
--- a server that is exactly what happens: each resource decides its own
--- rates, because that is the hot path and it should stay local, but
--- "this player has been refused thirty times" is a judgement about the
--- player and has to be made once, somewhere both resources report to.
function Doorman.new(opts)
  opts = opts or {}

  return setmetatable({
    clock = opts.clock or os.clock,
    log = opts.log or nothing,
    policy = opts.policy ~= false and policy.new(opts.policy) or nil,
    events = {},
    stats = { allowed = 0, refused = 0, warned = 0, kicked = 0 },
  }, Doorman)
end

--- Describe an event. Raises on a bad rule: a typo in a rule should stop the
--- resource from starting, not wait until a player trips over it.
--- @param name string
--- @param rule table  { rate = '5/10s', cooldown = '2s', schema = {...}, exempt = fn }
function Doorman:guard(name, rule)
  assert(type(name) == 'string' and name ~= '', 'an event needs a name')
  assert(type(rule) == 'table', ('rule for "%s" must be a table'):format(name))
  assert(self.events[name] == nil, ('"%s" is already guarded'):format(name))

  local guard = {
    name = name,
    schema = rule.schema,
    exempt = rule.exempt,
    allowed = 0,
    refused = 0,
  }

  if rule.rate then
    local count, window = parse.rate(rule.rate)
    assert(count, ('rate for "%s": %s'):format(name, window))
    guard.rate = Window.new(count, window)
    guard.rate_text = ('%d per %gs'):format(count, window)
  end

  if rule.cooldown then
    local seconds, err = parse.duration(rule.cooldown)
    assert(seconds, ('cooldown for "%s": %s'):format(name, err))
    assert(seconds > 0, ('cooldown for "%s" must be longer than zero'):format(name))
    -- A cooldown is just "one call per N seconds", so it is the same window.
    guard.cooldown = Window.new(1, seconds)
    guard.cooldown_text = ('%gs'):format(seconds)
  end

  if rule.schema then
    local ok, err = schema.valid(rule.schema)
    assert(ok, ('schema for "%s": %s'):format(name, err))
  end

  self.events[name] = guard
  return self
end

function Doorman:guarded(name)
  return self.events[name] ~= nil
end

--- Should this call go through?
---
--- @param name string    the event
--- @param source number  the player, as the server knows them — never from the payload
--- @param payload any    whatever the client sent
--- @return table verdict
---   { allow = true }
---   { allow = false, reason = 'rate'|'cooldown'|'schema'|'unguarded',
---     detail = string, action = 'refuse'|'warn'|'kick', offences = number,
---     retry = number|nil }
function Doorman:inspect(name, source, payload)
  local guard = self.events[name]
  local now = self.clock()

  if not guard then
    -- Refusing is the safe answer, but this is a mistake in the resource, not
    -- an attack, so it is never held against the player.
    return {
      allow = false,
      reason = 'unguarded',
      detail = ('"%s" has no rule'):format(name),
      action = 'refuse',
      offences = 0,
    }
  end

  if guard.exempt and guard.exempt(source) then
    guard.allowed = guard.allowed + 1
    self.stats.allowed = self.stats.allowed + 1
    return { allow = true, exempt = true }
  end

  local key = ('%s|%s'):format(source, name)

  -- Shape first: a payload that is the wrong shape is worth refusing even if
  -- the player is well within their rate, and checking it first means the
  -- limit is not spent on a call that was never going to be served.
  if guard.schema then
    local ok, err = schema.check(payload, guard.schema)
    if not ok then
      return self:refuse(guard, source, 'schema', err, now)
    end
  end

  if guard.cooldown then
    local ok, retry = guard.cooldown:allow(key, now)
    if not ok then
      return self:refuse(guard, source, 'cooldown',
        ('once every %s; %.1fs left'):format(guard.cooldown_text, retry), now, retry)
    end
  end

  if guard.rate then
    local ok, retry = guard.rate:allow(key, now)
    if not ok then
      return self:refuse(guard, source, 'rate',
        ('%s; %.1fs left'):format(guard.rate_text, retry), now, retry)
    end
  end

  guard.allowed = guard.allowed + 1
  self.stats.allowed = self.stats.allowed + 1
  return { allow = true }
end

--- @private
function Doorman:refuse(guard, source, reason, detail, now, retry)
  guard.refused = guard.refused + 1
  self.stats.refused = self.stats.refused + 1

  local action, offences = 'none', 0
  if self.policy then
    action, offences = self.policy:record(source, now)
  end

  if action == 'kick' then
    self.stats.kicked = self.stats.kicked + 1
  elseif action == 'warn' then
    self.stats.warned = self.stats.warned + 1
  end

  local verdict = {
    allow = false,
    event = guard.name,
    source = source,
    reason = reason,
    detail = detail,
    action = action == 'none' and 'refuse' or action,
    offences = offences,
    retry = retry,
    at = now,
  }

  self.log(verdict)
  return verdict
end

--- A player left. Everything held about them goes with them.
function Doorman:forget(source)
  for _, guard in pairs(self.events) do
    if guard.rate then guard.rate:forget(('%s|%s'):format(source, guard.name)) end
    if guard.cooldown then guard.cooldown:forget(('%s|%s'):format(source, guard.name)) end
  end
  if self.policy then self.policy:forget(source) end
end

--- Drop anything not touched for `idle` seconds. A safety net under forget():
--- a crashed client that never fires playerDropped should not cost memory for
--- the rest of the uptime.
function Doorman:sweep(idle)
  local now = self.clock()
  local dropped = self.policy and self.policy:sweep(now, idle) or 0

  for _, guard in pairs(self.events) do
    if guard.rate then dropped = dropped + guard.rate:sweep(now, idle) end
    if guard.cooldown then dropped = dropped + guard.cooldown:sweep(now, idle) end
  end

  return dropped
end

--- What is being held, for the console command and for the test that proves
--- forget() actually frees it.
function Doorman:report()
  local events, tracked = {}, 0

  for name, guard in pairs(self.events) do
    local held = (guard.rate and guard.rate:tracked() or 0)
      + (guard.cooldown and guard.cooldown:tracked() or 0)
    tracked = tracked + held

    events[#events + 1] = {
      name = name,
      allowed = guard.allowed,
      refused = guard.refused,
      rate = guard.rate_text,
      cooldown = guard.cooldown_text,
      schema = guard.schema ~= nil,
      tracked = held,
    }
  end

  table.sort(events, function(a, b) return a.name < b.name end)

  return {
    events = events,
    tracked = tracked,
    allowed = self.stats.allowed,
    refused = self.stats.refused,
    warned = self.stats.warned,
    kicked = self.stats.kicked,
  }
end

return Doorman
