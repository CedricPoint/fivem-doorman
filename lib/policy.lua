--[[
  What to do about someone who keeps getting refused.

  One refused event means nothing — a laggy client double-clicks, a resource
  fires on a loop during a reconnect. Thirty refused events in a minute is
  somebody with a menu open.

  The counting is deliberately across every event rather than per event: a
  cheat that is being careful will spread itself thinly over ten different
  events, and stay under every individual limit while doing it.
]]

local Window = require('lib.window')

local Policy = {}
Policy.__index = Policy

--- @param opts table|nil  { window = 60, warn = 3, kick = 10 }
function Policy.new(opts)
  opts = opts or {}

  -- Written out rather than `opts.kick or 10`, because `false or 10` is 10:
  -- a server that asked never to kick anyone would have been kicking them.
  local warn = opts.warn
  if warn == nil then warn = 3 end

  local kick = opts.kick
  if kick == nil then kick = 10 end

  assert(type(warn) == 'number' and warn >= 1, 'warn must be at least 1')
  assert(kick == false or (type(kick) == 'number' and kick >= warn),
    'kick must be false, or a number at least as large as warn')

  -- The window is sized to the threshold it has to detect, and no larger:
  -- its count saturates there, which bounds what one offender can make the
  -- server hold.
  local cap = kick == false and warn or kick

  return setmetatable({
    warn = warn,
    kick = kick,
    offences = Window.new(cap, opts.window or 60),
  }, Policy)
end

--- Record one refusal.
--- @return string action  'none', 'warn' or 'kick'
--- @return number count   offences inside the window, this one included
function Policy:record(key, now)
  local count = self.offences:bump(key, now)

  if self.kick ~= false and count >= self.kick then
    return 'kick', count
  end
  if count >= self.warn then
    return 'warn', count
  end

  return 'none', count
end

--- How many offences stand against this key right now.
function Policy:count(key, now)
  return self.offences:count(key, now)
end

function Policy:forget(key)
  self.offences:forget(key)
end

function Policy:sweep(now, idle)
  return self.offences:sweep(now, idle)
end

return Policy
