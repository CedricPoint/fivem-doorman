--[[
  Run every spec. Usage, from the repository root:

    lua test/run.lua            every spec
    lua test/run.lua schema     only the specs whose name contains "schema"
]]

package.path = './?.lua;' .. package.path

local harness = require('test.harness')

-- Listed rather than globbed: Lua has no portable directory listing, and a
-- spec that silently stops being run is worse than one that has to be added
-- to a list.
local SPECS = {
  'spec.parse_spec',
  'spec.window_spec',
  'spec.schema_spec',
  'spec.policy_spec',
  'spec.doorman_spec',
  'spec.resource_spec',
}

local filter = ...

for _, spec in ipairs(SPECS) do
  if not filter or spec:find(filter, 1, true) then
    harness.file_is(spec:gsub('^spec%.', ''):gsub('_spec$', ''))
    require(spec)
  end
end

if #harness.tests == 0 then
  io.stderr:write('no specs matched\n')
  os.exit(2)
end

os.exit(harness.run() and 0 or 1)
