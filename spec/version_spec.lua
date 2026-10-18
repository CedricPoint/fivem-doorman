local t = require('test.harness')
local version = require('lib.version')

local test, eq, ok, no = t.test, t.eq, t.ok, t.no

--- eq compares by identity; a parsed version is a fresh table each time.
local function same(got, want, note)
  eq(t.show(got), t.show(want), note)
end

test('a version reads the way tags and manifests write it', function()
  same(version.parse('1.2.3'), { 1, 2, 3 })
  same(version.parse('v1.2.3'), { 1, 2, 3 }, 'a git tag carries a v')
  same(version.parse('V10.0.12'), { 10, 0, 12 })
  same(version.parse('  2.4.0  '), { 2, 4, 0 })
end)

test('missing parts are zero, so 1.2 and 1.2.0 are the same release', function()
  same(version.parse('1.2'), { 1, 2, 0 })
  same(version.parse('3'), { 3, 0, 0 })
  eq(version.compare(version.parse('1.2'), version.parse('1.2.0')), 0)
end)

test('a pre-release or build suffix is ignored rather than compared', function()
  same(version.parse('1.3.0-beta.2'), { 1, 3, 0 })
  same(version.parse('1.3.0+build.7'), { 1, 3, 0 })
end)

test('numbers compare as numbers, not as text', function()
  -- The bug a string comparison ships: '1.10.0' < '1.9.0' alphabetically.
  eq(version.compare(version.parse('1.10.0'), version.parse('1.9.0')), 1)
  eq(version.compare(version.parse('1.9.9'), version.parse('2.0.0')), -1)
  eq(version.compare(version.parse('0.0.2'), version.parse('0.0.10')), -1)
end)

test('the status tells the server owner what to do', function()
  eq(version.status('1.0.0', 'v1.1.0'), 'outdated')
  eq(version.status('1.1.0', 'v1.1.0'), 'current')
  eq(version.status('1.2.0', 'v1.1.0'), 'ahead', 'a local build newer than any release')
end)

test('anything unreadable is refused with a reason, never guessed at', function()
  local status, err = version.status('1.0.0', 'latest')
  no(status)
  ok(err:match('latest release'), err)

  status, err = version.status(nil, '1.0.0')
  no(status)
  ok(err:match('running version'), err)

  no(version.parse(''))
  no(version.parse('1..2'))
  no(version.parse('1.2.'))
  no(version.parse('1.2.3.4'), 'four numbers is not semver')
  no(version.parse({}))
end)

test('format writes three numbers back', function()
  eq(version.format({ 1, 2, 0 }), '1.2.0')
  eq(version.format(version.parse('v4')), '4.0.0')
end)
