fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'doorman'
author 'CedricPoint'
description 'A doorman for your net events: checks who is calling, how often, and whether the payload makes sense.'
version '1.0.0'
repository 'https://github.com/CedricPoint/fivem-doorman'

-- Other resources reach this with
--   server_script '@doorman/import.lua'
-- in their own fxmanifest, which is why import.lua is listed as a file
-- rather than as a script: it is loaded by them, in their Lua state, not by
-- this resource in its own.
files {
  'import.lua',
  'lib/parse.lua',
  'lib/window.lua',
  'lib/schema.lua',
  'lib/policy.lua',
  'lib/doorman.lua',
  'server/resource.lua',
}

-- Only the entry point is a script. Everything else is read with
-- LoadResourceFile and given a `require` of its own, so the files that hold
-- the logic are byte for byte the ones the test suite runs under a plain
-- `lua` binary.
server_script 'server/main.lua'
