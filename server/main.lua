--[[
  The doorman resource itself.

  Every resource that imports doorman keeps its own rates — that is the hot
  path and it belongs where the event is. What it does not keep is the
  judgement: "this player has been refused thirty times in a minute" is a
  statement about the player, and it has to be made once, by something that
  can see all of them at the same time.

  That is this file. It owns one tally for the whole server, and it is the
  only thing here that drops anybody.
]]

local RESOURCE = GetCurrentResourceName()

local loaded = {}

local function import(name)
  if loaded[name] then return loaded[name] end

  local path = name:gsub('%.', '/') .. '.lua'
  local text = LoadResourceFile(RESOURCE, path)
  assert(text, ('doorman is missing %s'):format(path))

  local env = setmetatable({ require = import }, { __index = _G })
  loaded[name] = assert(load(text, ('@@%s/%s'):format(RESOURCE, path), 't', env))()

  return loaded[name]
end

local Policy = import('lib.policy')
local Version = import('lib.version')

local config = {
  warn = GetConvarInt('doorman_warn', 3),
  kick = GetConvarInt('doorman_kick', 10),
  window = GetConvarInt('doorman_window', 60),
  message = GetConvar('doorman_kick_message',
    'Kicked by doorman: too many refused events. If this is a mistake, tell the server owner.'),
}

-- set doorman_kick 0  — watch and log, never drop anyone.
if config.kick <= 0 then config.kick = false end

local ledger = Policy.new({
  warn = config.warn,
  kick = config.kick,
  window = config.window,
})

local seen = { refusals = 0, warned = 0, kicked = 0, by_resource = {} }

local function now()
  return GetGameTimer() / 1000
end

--- Called by every resource that imports doorman, once per refusal.
---
--- The arguments are plain values on purpose: this is the one place where
--- something crosses a resource boundary, and the less it carries the less
--- there is to go wrong.
local function offence(from, source, event, reason, detail)
  if type(source) ~= 'number' or source <= 0 then return end

  seen.refusals = seen.refusals + 1
  seen.by_resource[from] = (seen.by_resource[from] or 0) + 1

  local action, count = ledger:record(source, now())

  if action == 'warn' then
    seen.warned = seen.warned + 1
    print(('^3[doorman] %s [%s] — %d refused events in the last %ds (latest: %s %s on %s)^7')
      :format(GetPlayerName(source) or '?', source, count, config.window, event, reason, from))
  elseif action == 'kick' then
    seen.kicked = seen.kicked + 1
    print(('^1[doorman] dropping %s [%s] — %d refused events in the last %ds (latest: %s %s on %s: %s)^7')
      :format(GetPlayerName(source) or '?', source, count, config.window, event, reason, from, detail))
    DropPlayer(source, config.message)
    ledger:forget(source)
  end

  return action
end

exports('offence', function(source, event, reason, detail)
  return offence(GetInvokingResource() or 'unknown', source, event, reason, detail)
end)

AddEventHandler('playerDropped', function()
  ledger:forget(source)
end)

-- A client that crashes never fires playerDropped.
CreateThread(function()
  while true do
    Wait(300 * 1000)
    ledger:sweep(now(), 600)
  end
end)

RegisterCommand('doorman', function(source)
  if source ~= 0 then return end   -- console only

  print(('^2[doorman]^7 %d refusals seen, %d warnings, %d kicks')
    :format(seen.refusals, seen.warned, seen.kicked))
  print(('           thresholds: warn at %d, kick at %s, over %ds')
    :format(config.warn, config.kick == false and 'never' or config.kick, config.window))

  local names = {}
  for name in pairs(seen.by_resource) do names[#names + 1] = name end
  table.sort(names)

  if #names == 0 then
    print('           no resource has reported a refusal yet')
    return
  end

  for _, name in ipairs(names) do
    print(('           %-28s %6d'):format(name, seen.by_resource[name]))
  end
end, true)

print(('^2[doorman]^7 watching — warn at %d, kick at %s, over %ds')
  :format(config.warn, config.kick == false and 'never' or config.kick, config.window))

--[[
  Is a newer release out? Asked once, at start, of GitHub's public API.

  It only ever prints: nothing is downloaded and nothing is changed. Any
  failure (no network, rate limit, GitHub down) is silent apart from one grey
  line, because a version check must never be the reason a server's console
  fills up. Turn it off with:  set doorman_version_check false
]]
local RELEASES = 'https://github.com/CedricPoint/fivem-doorman/releases/latest'
local LATEST_API = 'https://api.github.com/repos/CedricPoint/fivem-doorman/releases/latest'

local function version_check()
  local setting = GetConvar('doorman_version_check', 'true'):lower()
  if setting == 'false' or setting == '0' or setting == 'off' then return end

  local running = GetResourceMetadata(RESOURCE, 'version', 0) or '0.0.0'

  PerformHttpRequest(LATEST_API, function(status, body)
    if status ~= 200 or not body then
      print(('^9[doorman] could not check for updates (HTTP %s) — see %s^7'):format(status, RELEASES))
      return
    end

    local ok, release = pcall(json.decode, body)
    local tag = ok and type(release) == 'table' and release.tag_name

    local state, err = Version.status(running, tag)
    if not state then
      print(('^9[doorman] could not check for updates (%s)^7'):format(err))
    elseif state == 'outdated' then
      print(('^3[doorman] update available: %s (you are running %s) — %s^7')
        :format(Version.format(Version.parse(tag)), running, release.html_url or RELEASES))
    else
      print(('^2[doorman]^7 up to date (%s)'):format(running))
    end
  end, 'GET', '', { ['User-Agent'] = 'fivem-doorman', ['Accept'] = 'application/vnd.github+json' })
end

-- After the start-up burst, so the line is not lost among other resources'.
CreateThread(function()
  Wait(5000)
  version_check()
end)
