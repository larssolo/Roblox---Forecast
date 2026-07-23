# FORECAST — v0.1 Rojo scaffold

Playable graybox skeleton of the round loop from `FORECAST-spec-v0.1.md`.
The point of this stage is to test the **loop**, not the look.

## Requirements

[Rokit](https://github.com/rojo-rbx/rokit) (toolchain manager). Then:

```sh
rokit install          # installs rojo, lune, stylua, selene (pinned in rokit.toml)
```

## Run it in Studio

```sh
rojo serve
```

Open an empty baseplate in Roblox Studio, connect with the
[Rojo plugin](https://rojo.space), then press Play.

**Solo play just works:** `MinPlayers = 1` and AI stylists (`Config.Bots`)
fill the round up to 6 entrants — they style for the brief, bet, vote and
react, so a single player gets the full loop: styling → bet → runway →
results → trend board movement. For real multi-client testing use Studio's
Test tab → *Clients and Servers*.

## Tests & tooling

```sh
lune run tests/trendmath.spec.luau   # 31 assertions on the pure trend math
lune run tests/fullround.spec.luau   # 113 assertions: two complete headless rounds
lune run tests/botround.spec.luau    # 26 assertions: solo + AI stylists, shop, reactions
lune run tests/compile.spec.luau     # syntax gate over every src/ module
selene generate-roblox-std           # once
selene src                           # lint
stylua src tests                     # format
```

`TrendMath.luau` deliberately has **zero requires** so the whole trend economy
math is unit-testable outside Studio and reusable unchanged when the engine
goes cross-server in v0.2.

`tests/fullround.spec.luau` goes much further: `tests/harness/roblox.luau`
stubs `game`/`Instance`/`Players`/remotes and loads the **real** server modules,
then plays two complete rounds with six fake players — lobby gating,
invalid-outfit rejection, rate limiting + kick, mid-round join/leave, vote
normalization with every rejection path (self/duplicate/late/non-integer),
bet resolution, exact Threads/XP payouts, and a forced trend crash. It catches
state-machine regressions in seconds, without opening Studio.

## What is implemented

- Full server-authoritative state machine: LOBBY → BRIEF → STYLING → FORECAST → RUNWAY → RESULTS
- **AI stylists** (`BotService`): fill rounds to `Config.Bots.FillTo`, dress for the brief with
  trend-aware taste, bet, vote and react — solo play and quiet servers feel alive
- **Theme-match bonus**: wearing the brief's tags multiplies your score (`Config.Round.ThemeMatch*`)
- Outfit validation (catalog, slots, ownership, palette), per-remote + global rate limiting, kick on abuse
- Anonymous runway with per-voter mean normalization, self-vote/dupe rejection, vote window per look
- **Emote reactions**: anonymous 💖🔥✨ bursts echoed to everyone during the runway
- Trend Engine (local map): lazy 36h-half-life decay, 24h momentum anchors, saturation curve, **crash events**, editorial cold-start seeds
- Free Trend Bets resolved against the round's real S(e) contributions, plus the **Oracle streak**
  (consecutive hits pay a growing Threads bonus)
- **Shop**: 9 purchasable catalog items (`BuyItem`), so Threads have a purpose; 42 items total
- Threads/XP/rank economy with placement rewards, non-voter penalty, bet payouts, rank titles
- Styled client UI for every phase — "editorial paper + electric signal" design system
  (`Theme.luau` + `UIFX.luau`), persistent HUD, full-screen **trend crash takeover**
- **Live 3D avatar** (`CharacterViewport.luau`): a real R15 character in a `ViewportFrame`,
  dressed via `HumanoidDescription`, rotating/swaying/walking. It stars in styling (dress her
  live), struts each runway look, and poses the top-3 on the results podium. Body colors track
  the item you recolor; hair/clothes/accessories render once catalog items get real asset ids.

## Curating free avatar assets (make items show their real 3D look)

Every catalog item has `assetId` (0 = unassigned) and `accessoryType` in `src/shared/ItemCatalog.luau`.
With `assetId = 0` the avatar still wears the item's **color**; give it a real **free** Roblox
catalog asset id and the actual mesh renders on the character. Two-minute harvest, per item:

1. In Studio, open **View → Toolbox → Marketplace** (or the Avatar Shop at `roblox.com/catalog`)
   and find a **free** (0 Robux) item that matches — e.g. a hair for `hair_bob`.
2. Get its id: on the web the URL is `roblox.com/catalog/<ID>/name` (the number is the asset id);
   in the Toolbox, right-click the item → **Copy Asset ID**.
3. Set that item's `assetId = <ID>` in `ItemCatalog.luau`. Keep `accessoryType` matching the item
   (`Hair` for hair, `Shirt`/`Pants` for layered clothing, `Hat`/`Face`/`Neck`/`Back` for accessories —
   already defaulted per slot).

Use free layered-clothing items for tops/bottoms and free accessories/hair — they load in the
ViewportFrame for everyone. (The avatar APIs are Studio-only, so this can't be scripted from CI.)

## Deliberate scaffold limitations (read before playtesting for real)

| Gap | Where | Plan |
| --- | --- | --- |
| Profiles are **in-memory only** | `DataService.luau` | Wire [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) behind the existing interface (spec §9.5) |
| Trend heat is **per-server** | `TrendEngineService.luau` | Swap storage for MemoryStore HashMap + UpdateAsync lazy decay (spec §9.6) — math stays identical |
| Catalog items ship with **`assetId = 0`** | `ItemCatalog.luau` | Paste real free catalog ids (recipe above) so items render their mesh, not just their color |
| Runway is a **ViewportFrame avatar**, not a 3D world stage | `CharacterViewport.luau` | A real in-world catwalk with camera/lighting is the bigger v0.3 upgrade |
| No weekly forecast / Oracle board | — | v0.2 (spec §12) |

Everything tunable lives in `src/shared/Config.luau`.
