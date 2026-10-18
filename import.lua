--[[
  What another resource gets when it writes

    server_script '@doorman/import.lua'

  in its own fxmanifest.

  This runs inside *that* resource's Lua state, not doorman's. That is on
  purpose: the handler you pass to doorman.on() stays a plain Lua function in
  your own resource, with your own upvalues, and never crosses an export
  boundary. Nothing is serialised on the hot path.

  What does cross the boundary is a refusal, which is rare, and which goes to
  the doorman resource so that one tally covers the whole server.
]]

local RESOURCE = 'doorman'

-- The library files `require` each other, and FiveM is not a place where
-- package.path means anything. Rather than rewrite them for the server, they
-- are loaded here with a `require` of our own put into their environment —
-- so the exact same files run under a plain `lua` binary in the tests and
-- under CfxLua on a server, with nothing conditional inside them.
local loaded = {}

local function import(name)
  if loaded[name] then return loaded[name] end

  local path = name:gsub('%.', '/') .. '.lua'
  local text = LoadResourceFile(RESOURCE, path)
  assert(text, ('doorman is missing %s — is the resource complete?'):format(path))

  local env = setmetatable({ require = import }, { __index = _G })
  local chunk = assert(load(text, ('@@%s/%s'):format(RESOURCE, path), 't', env))

  loaded[name] = chunk()
  return loaded[name]
end

local build = import('server.resource')

-- Not called `doorman`: that name is the global this file sets at the
-- bottom, and a local of the same name would quietly swallow it.
local watch = build.new({
  now = function() return GetGameTimer() / 1000 end,
  register = function(event, handler)
    RegisterNetEvent(event)
    AddEventHandler(event, function(payload)
      -- `source` is a global that the next event overwrites. Read once,
      -- here, before anything can yield: a handler that reads it after an
      -- await is acting for whoever came next.
      return handler(source, payload)
    end)
  end,
  kick = function(target, reason) DropPlayer(target, reason) end,
  name = function(target) return ('%s [%s]'):format(GetPlayerName(target) or '?', target) end,
  print = function(line) print(line) end,
  every = function(seconds, fn)
    CreateThread(function()
      while true do
        Wait(seconds * 1000)
        fn()
      end
    end)
  end,
}, {
  -- The judgement about a player belongs to the server, not to whichever
  -- resource happened to catch them, so every refusal goes to the one
  -- tally that can see all of them.
  policy = false,
  report = function(entry)
    exports[RESOURCE]:offence(entry.source, entry.event, entry.reason, entry.detail)
  end,
})

AddEventHandler('playerDropped', function()
  watch:dropped(source)
end)

local api = {
  --- Guard an event and handle it.
  ---
  ---   doorman.on('shop:buy', {
  ---     rate = '5/10s',
  ---     cooldown = '1s',
  ---     schema = {
  ---       item  = { 'string', max = 32, pattern = '^[%w_]+$' },
  ---       count = { 'number', min = 1, max = 100, integer = true },
  ---     },
  ---   }, function(source, data)
  ---     -- only ever called for calls that passed
  ---   end)
  on = function(name, rule, handler)
    watch:on(name, rule, handler)
    return true
  end,

  --- What this resource is holding and how it is going.
  report = function()
    return watch.doorman:report()
  end,

  --- The same, as lines of text.
  lines = function()
    return watch:lines()
  end,
}

-- A script pulled in with `server_script '@doorman/import.lua'` has its
-- return value thrown away, so the way in is a global — one name, in your
-- own resource's state, same as ox_lib's `lib`.
doorman = api

return api
