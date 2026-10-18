--[[
  A sliding window, counted per key.

  Every net event a player can fire needs an answer to "how many times in the
  last N seconds", and the answer has to be cheap: this runs on the hot path,
  for every player, on every event.

  The clock is passed in rather than read. On a server that means
  GetGameTimer(), in a test it means a number the test controls — which is the
  only reason the rate-limiting tests can be exhaustive without sleeping.
]]

local Window = {}
Window.__index = Window

--- @param limit number  how many are allowed
--- @param seconds number  over how long
function Window.new(limit, seconds)
  assert(type(limit) == 'number' and limit >= 1, 'limit must be at least 1')
  assert(type(seconds) == 'number' and seconds > 0, 'seconds must be greater than 0')

  return setmetatable({
    limit = limit,
    seconds = seconds,
    hits = {},  -- key -> ordered list of timestamps
    last = {},  -- key -> when we last heard from it, for sweeping
  }, Window)
end

--- Drop the timestamps that have fallen out of the window.
--- They are in order, so the ones to drop are always a prefix.
local function prune(hits, cutoff)
  local first = 1
  while hits[first] and hits[first] <= cutoff do
    first = first + 1
  end

  if first == 1 then return end

  local kept = 0
  for i = first, #hits do
    kept = kept + 1
    hits[kept] = hits[i]
  end
  for i = #hits, kept + 1, -1 do
    hits[i] = nil
  end
end

local function bucket(self, key, now)
  local hits = self.hits[key]
  if not hits then
    hits = {}
    self.hits[key] = hits
  end

  prune(hits, now - self.seconds)
  self.last[key] = now

  return hits
end

--- Is this one allowed? Records it if so.
--- @return boolean allowed, number retry_after  seconds until the oldest hit expires
function Window:allow(key, now)
  local hits = bucket(self, key, now)

  if #hits >= self.limit then
    return false, (hits[1] + self.seconds) - now
  end

  hits[#hits + 1] = now
  return true, 0
end

--- Record one whether or not it is over the limit, and say how many are in
--- the window now. This is what counts offences: an offence still happened
--- even when the answer was "no".
---
--- The count saturates at the limit, and the list never grows past it. That
--- matters because the person who makes this list long is, by definition,
--- the person attacking the server — an uncapped list here would be a leak
--- with an attacker holding the other end. Saturating is safe for the only
--- question ever asked of the answer ("are there at least N?") as long as
--- the limit is at least N, which is what Policy sets it to.
--- @return number count
function Window:bump(key, now)
  local hits = bucket(self, key, now)

  if #hits >= self.limit then
    table.remove(hits, 1)   -- keep the window sliding, at a fixed size
    hits[#hits + 1] = now
    return self.limit
  end

  hits[#hits + 1] = now
  return #hits
end

--- How many are in the window, without recording anything.
function Window:count(key, now)
  local hits = self.hits[key]
  if not hits then return 0 end

  prune(hits, now - self.seconds)
  return #hits
end

--- Forget a key entirely. Called when a player drops: without it, a server
--- that has seen ten thousand players is holding ten thousand empty lists.
function Window:forget(key)
  self.hits[key] = nil
  self.last[key] = nil
end

--- Forget every key not heard from for `idle` seconds.
--- @return number how many were dropped
function Window:sweep(now, idle)
  local dropped = 0

  for key, last in pairs(self.last) do
    if now - last >= idle then
      self.hits[key] = nil
      self.last[key] = nil
      dropped = dropped + 1
    end
  end

  return dropped
end

--- How many keys are being tracked. For the stats command, and for the test
--- that proves dropping a player actually frees the memory.
function Window:tracked()
  local n = 0
  for _ in pairs(self.hits) do n = n + 1 end
  return n
end

return Window
