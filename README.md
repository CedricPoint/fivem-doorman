# doorman

**English** · [Français](README.fr.md)

A net event on a FiveM server is a public API with no authentication, no
rate limit and no types. Any connected client can fire any registered event,
as often as it likes, with any arguments at all.

Most server code is written as though that were not true:

```lua
RegisterNetEvent('shop:buy')
AddEventHandler('shop:buy', function(data)
    local cost = prices[data.item] * data.count
    money[source] = money[source] - cost
end)
```

Four assumptions, none checked. `{item = 'bread', count = -1000}` and the
shop pays the player. `{count = 0/0}` and the balance becomes NaN, after
which every comparison against it is false — including the one meant to stop
them buying things.

**doorman** puts the rule in front of the handler:

```lua
doorman.on('shop:buy', {
    rate     = '5/10s',
    cooldown = '500ms',
    schema   = {
        item  = { 'string', oneof = { 'bread', 'milk', 'eggs' } },
        count = { 'number', min = 1, max = 10, integer = true },
    },
}, function(source, data)
    -- only ever runs for a call that passed
end)
```

Standalone. No framework, no dependency, no database. **93 tests.**

## Install

1. Get it, for free, either way:
   - **[Cfx.re asset, through the CedricPoint store](https://cedricpoint-developpement.tebex.io/)**
     — it lands in your [Cfx.re portal](https://portal.cfx.re/assets/granted-assets);
   - **[the latest GitHub release](https://github.com/CedricPoint/fivem-doorman/releases/latest)**
     — `doorman-vX.Y.Z.zip`.

   Unzip it into your resources folder and `ensure doorman` before anything
   that uses it.
2. In the resource you want to protect, add one line to `fxmanifest.lua`:

```lua
server_script '@doorman/import.lua'
```

That gives you the global `doorman` inside that resource. Use
`doorman.on(...)` instead of `RegisterNetEvent` + `AddEventHandler`.

### Updates

At start, doorman asks GitHub for the latest release and prints one line if a
newer one is out. It never downloads or changes anything. To turn it off:

```cfg
set doorman_version_check false
```

## What a rule can say

| | |
|---|---|
| `rate = '5/10s'` | at most 5 calls per 10 seconds, per player, for this event. Also `'30/min'`, `'3/s'`, `{5, 10}` |
| `cooldown = '2s'` | and at least 2 seconds between them. Also `'500ms'`, `'1m'` |
| `schema = {…}` | what the payload has to look like |
| `exempt = fn` | `function(source) → boolean`, checked first; an admin does not spend a budget they are not subject to |

Every field is optional. A rule with only a `schema` validates and never
rate limits; a rule with only a `rate` limits and accepts any payload.

### Schemas

```lua
schema = {
    item   = 'string',                                        -- required
    note   = 'string?',                                       -- optional
    count  = { 'number', min = 1, max = 99, integer = true },
    id     = { 'string', max = 32, pattern = '^[%w_]+$' },
    side   = { 'string', oneof = { 'left', 'right' } },
    coords = { 'table', of = 'number', max = 3 },
    player = { 'table', fields = { id = 'number', name = 'string' } },
}
```

Types are `string`, `number`, `boolean`, `table` and `any`; a `?` on the end
makes a field optional.

Four things are refused whether or not you asked for them, because they are
the ones that are easy to forget and expensive to miss:

- **NaN and infinity.** `0/0` is a number as far as `type()` is concerned,
  and it compares false against every bound you could write, so `min` and
  `max` will not catch it. Anything it touches becomes NaN too.
- **Strings over 512 bytes.** A client can send a megabyte as easily as a
  word.
- **Tables deeper than 8 levels or wider than 64 entries** — including
  inside `any` and inside a bare `table`, which are otherwise the two places
  a nested payload walks straight in.
- **Fields you did not declare.** A handler that walks the payload with
  `pairs()` will happily act on a key you never thought about. Pass
  `strict = false` if you do want extras.

A mistake in a rule — `'nubmer'`, `rate = 'quickly'` — stops the resource
from starting, rather than waiting for a player to trip over it at 2am.

### When somebody will not stop

Each resource keeps its own rates, because that is the hot path and it
belongs where the event is. What it does not keep is the verdict: *this
player has been refused thirty times in a minute* is a statement about the
player, and has to be made once, by something that can see every resource at
the same time. That is the `doorman` resource itself.

```cfg
set doorman_warn   3     # log loudly from the third refusal in the window
set doorman_kick  10     # drop them at the tenth; 0 to never drop anybody
set doorman_window 60    # the window, in seconds
set doorman_kick_message "..."
```

The tally is deliberately not per event: somebody being careful spreads
themselves over ten events and stays under every individual limit.

`doorman` in the server console prints what has been refused and by which
resource; `doorman.lines()` gives a resource its own numbers.

## It is tested, and that is the point of the shape

Anything that decides something lives in `lib/`, takes a clock as an
argument and knows nothing about the game. Everything that touches a native
lives in `server/` and takes the natives as an argument. So the test suite
runs the real files, under a plain `lua` binary, with no server and no
mocking framework:

```bash
lua test/run.lua
```

93 tests, no dependencies. They cover the things that are hard to notice and
embarrassing to ship:

- a fixed-window limiter lets double the limit through at the seam; this one
  is a sliding window, and there is a test that sends the whole allowance at
  9.9s and again at 10.1s
- an offence counter is a list an attacker can make longer, so it saturates,
  and a test hits it ten thousand times and checks four timestamps are held
- a player who leaves has to be forgotten, or a server that has seen ten
  thousand players is holding ten thousand lists — and a client that crashes
  never fires `playerDropped`, so there is a sweep, and a test for it
- `source` is a FiveM global that the next event overwrites; the one place
  it is read is before anything can yield

The suite found two real bugs while it was being written. One is pinned by
[a test named after it](spec/policy_spec.lua): `opts.kick or 10` reads
beautifully and turns `kick = false` — *never drop anybody* — into *drop
them at ten*.

## What it does not do

- **It is not an anticheat.** It makes an event behave the way the rule
  says. It knows nothing about what a player is doing in the world, and a
  cheat that stays inside the rules is invisible to it.
- **It does not authorise.** `exempt` is yours to write; doorman does not
  know who your admins are.
- **It cannot un-receive a payload.** FiveM has already deserialised it
  before any handler runs. The limits here stop it reaching your code, not
  the network.
- **Client events are not its business.** Everything here is server side,
  which is the only side worth checking.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). A bug report with the event, the
rule and the payload that got through is the most useful thing you can send.

MIT.
