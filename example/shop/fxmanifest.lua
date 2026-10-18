fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'doorman_example_shop'
description 'The same shop event, written the usual way and written with doorman.'
version '1.0.0'

-- This is the line that matters. It loads doorman into *this* resource.
server_script '@doorman/import.lua'

server_script 'server.lua'

dependency 'doorman'
