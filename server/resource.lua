--[[
  The wiring between the decision and the game.

  Everything that decides anything is in lib/. What is left here is the part
  that can only exist on a server: registering events, reading the clock,
  dropping a player, printing to the console.

  It takes the game as an argument rather than reaching for globals, so the
  spec can hand it a fake one and watch what it does.
]]

local Doorman = require('lib.doorman')

local resource = {}

local RED = '^1'
local YELLOW = '^3'
local GREY = '^7'

--- @param game table  the natives this needs, named
---   now()                         -> seconds, monotonic
---   register(event, handler)      RegisterNetEvent + AddEventHandler
---   kick(source, reason)          DropPlayer
---   name(source)                  -> string, for the log
---   print(line)
---   every(seconds, fn)            a repeating timer, or nil for none
--- @param opts table|nil
---   policy   table|false  escalation, or false when something else owns it
---   report   function(entry)  called for every refusal, after printing
---   sweep    number|false  how often to collect players who vanished
---   idle     number        how quiet a player must be to be collected
function resource.new(game, opts)
  opts = opts or {}

  local self = {
    game = game,
    report = opts.report or function() end,
    kick_message = opts.kick_message
      or 'Kicked by doorman: too many refused events. If this is a mistake, tell the server owner.',
  }

  self.doorman = Doorman.new({
    clock = game.now,
    policy = opts.policy,
    log = function(entry) self:logged(entry) end,
  })

  -- A client that crashes never fires playerDropped, so forget() alone would
  -- leak one entry per crash for the rest of the uptime.
  if game.every and opts.sweep ~= false then
    local idle = opts.idle or 600
    game.every(opts.sweep or 300, function()
      self.doorman:sweep(idle)
    end)
  end

  return setmetatable(self, { __index = resource })
end

--- Guard an event and register it in one go.
---
--- The handler is called with (source, payload) and only ever for calls that
--- passed. `source` is captured before anything can yield, which is the bug
--- this exists to make impossible: FiveM's `source` is a global that the next
--- event handler overwrites, so a handler that yields and then reads it is
--- acting on behalf of whoever came next.
function resource:on(name, rule, handler)
  assert(type(handler) == 'function', ('handler for "%s" must be a function'):format(name))

  self.doorman:guard(name, rule)

  self.game.register(name, function(source, payload)
    local verdict = self.doorman:inspect(name, source, payload)
    if not verdict.allow then return end

    return handler(source, payload)
  end)

  return self
end

--- @private
function resource:logged(entry)
  local who = self.game.name and self.game.name(entry.source) or ('player %s'):format(entry.source)
  local colour = entry.action == 'refuse' and GREY or (entry.action == 'warn' and YELLOW or RED)

  self.game.print(('%s[doorman] %s refused on %s (%s: %s) — %d in the last minute%s')
    :format(colour, who, entry.event, entry.reason, entry.detail, entry.offences, GREY))

  if entry.action == 'kick' then
    self.game.kick(entry.source, self.kick_message)
  end

  -- Last, and after the print, so that a report that throws still leaves a
  -- line in the console saying what happened.
  self.report(entry)
end

--- A player left: let go of everything held for them.
function resource:dropped(source)
  self.doorman:forget(source)
end

--- The lines the console command prints.
function resource:lines()
  local report = self.doorman:report()
  local out = {
    ('doorman — %d allowed, %d refused, %d warned, %d kicked')
      :format(report.allowed, report.refused, report.warned, report.kicked),
  }

  if #report.events == 0 then
    out[#out + 1] = '  no events are guarded yet'
    return out
  end

  for _, event in ipairs(report.events) do
    local limits = {}
    if event.rate then limits[#limits + 1] = event.rate end
    if event.cooldown then limits[#limits + 1] = 'cooldown ' .. event.cooldown end
    if event.schema then limits[#limits + 1] = 'schema' end

    out[#out + 1] = ('  %-34s %6d ok %6d refused   %s')
      :format(event.name, event.allowed, event.refused, table.concat(limits, ', '))
  end

  out[#out + 1] = ('  holding state for %d player/event pairs'):format(report.tracked)
  return out
end

return resource
