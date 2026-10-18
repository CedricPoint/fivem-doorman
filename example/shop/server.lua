--[[
  A shop, twice.

  Drop this next to doorman, `ensure doorman` then `ensure
  doorman_example_shop`, and fire the two events from a client to see the
  difference.
]]

local money = {}
local prices = { bread = 5, milk = 3, eggs = 7 }

local function balance(source)
  money[source] = money[source] or 100
  return money[source]
end

--[[ ─────────────────────────── the usual way ───────────────────────────

  Four assumptions, none of them checked, all of them wrong as soon as
  somebody opens a menu:

    · that `data` is a table
    · that `data.item` is one of the three things in `prices`
    · that `data.count` is a positive whole number
    · that this runs at human speed

  A client that sends {item = 'bread', count = -1000} is paid by the shop.
  One that sends {item = 'bread', count = 0/0} ends up with a balance of
  NaN, and every comparison against it is false from then on — including
  the one that is supposed to stop them buying things.
]]

RegisterNetEvent('shop:buy:unguarded')
AddEventHandler('shop:buy:unguarded', function(data)
  local src = source
  local cost = prices[data.item] * data.count

  if balance(src) < cost then return end

  money[src] = money[src] - cost
  print(('%s bought %d %s for %d, leaving %s')
    :format(GetPlayerName(src), data.count, data.item, cost, money[src]))
end)

--[[ ──────────────────────────── with doorman ────────────────────────────

  The rule says what a call is allowed to look like, and the handler runs
  only for calls that look like it. Everything the handler assumed above is
  now written down where somebody reviewing the resource can read it.
]]

doorman.on('shop:buy', {
  rate = '5/10s',
  cooldown = '500ms',
  schema = {
    item = { 'string', oneof = { 'bread', 'milk', 'eggs' } },
    count = { 'number', min = 1, max = 10, integer = true },
  },
}, function(src, data)
  local cost = prices[data.item] * data.count

  if balance(src) < cost then
    TriggerClientEvent('shop:refused', src, 'not enough money')
    return
  end

  money[src] = money[src] - cost
  print(('%s bought %d %s for %d, leaving %s')
    :format(GetPlayerName(src), data.count, data.item, cost, money[src]))
end)

--[[
  An event only a few people may fire at all. `exempt` is checked before
  anything else, so an admin does not spend a rate they are not subject to.
]]

doorman.on('shop:restock', {
  rate = '1/5s',
  schema = {
    item = { 'string', oneof = { 'bread', 'milk', 'eggs' } },
    price = { 'number', min = 1, max = 1000, integer = true },
  },
  exempt = function(src) return IsPlayerAceAllowed(src, 'shop.admin') end,
}, function(src, data)
  prices[data.item] = data.price
  print(('%s set %s to %d'):format(GetPlayerName(src), data.item, data.price))
end)

RegisterCommand('shopstats', function(src)
  if src ~= 0 then return end
  for _, line in ipairs(doorman.lines()) do print(line) end
end, true)
