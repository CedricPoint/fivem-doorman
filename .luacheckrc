std = 'lua54'
max_line_length = 110

-- The natives, and the two globals FiveM gives a server script.
read_globals = {
  'AddEventHandler', 'CreateThread', 'DropPlayer', 'GetConvar', 'GetConvarInt',
  'GetCurrentResourceName', 'GetGameTimer', 'GetInvokingResource', 'GetPlayerName',
  'IsPlayerAceAllowed', 'LoadResourceFile', 'RegisterCommand', 'RegisterNetEvent',
  'TriggerClientEvent', 'Wait', 'exports', 'source',
  -- the manifest is Lua too
  'fx_version', 'game', 'lua54', 'name', 'author', 'description', 'version',
  'repository', 'files', 'server_script', 'server_scripts', 'dependency',
}

-- import.lua deliberately sets this one, for the resource that loads it.
globals = { 'doorman' }

files['spec/'] = { max_line_length = 120 }
files['example/'] = { globals = { 'doorman' } }
