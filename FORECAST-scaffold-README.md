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

**Solo smoke test:** set `Config.Round.MinPlayers = 2` in
`src/shared/Config.luau`, then use Studio's Test tab → *Clients and Servers* →
2 players. Each client votes on the other's look, so the full loop
(styling → bet → runway → results → trend board movement) is exercisable alone.

## Tests & tooling

```sh
lune run tests/trendmath.spec.luau   # 31 assertions on the pure trend math
selene generate-roblox-std           # once
selene src                           # lint
stylua src tests                     # format
```

`TrendMath.luau` deliberately has **zero requires** so the whole trend economy
math is unit-testable outside Studio and reusable unchanged when the engine
goes cross-server in v0.2.

## What is implemented (spec §12, v0.1 scope)

- Full server-authoritative state machine: LOBBY → BRIEF → STYLING → FORECAST → RUNWAY → RESULTS
- Outfit validation (catalog, slots, ownership, palette), per-remote + global rate limiting, kick on abuse
- Anonymous runway with per-voter mean normalization, self-vote/dupe rejection, vote window per look
- Trend Engine (local map): lazy 36h-half-life decay, 24h momentum anchors, saturation curve, **crash events**, editorial cold-start seeds
- Free Trend Bets resolved against the round's real S(e) contributions
- Threads/XP/rank economy with placement rewards, non-voter penalty, bet payouts
- Graybox client UI for every phase

## Deliberate scaffold limitations (read before playtesting for real)

| Gap | Where | Plan |
| --- | --- | --- |
| Profiles are **in-memory only** | `DataService.luau` | Wire [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) behind the existing interface (spec §9.5) |
| Trend heat is **per-server** | `TrendEngineService.luau` | Swap storage for MemoryStore HashMap + UpdateAsync lazy decay (spec §9.6) — math stays identical |
| Runway shows **text cards**, not avatars | `RunwayUI.luau` / `GameLoopService.outfitSummary` | HumanoidDescription stage rig (spec §9.8); catalog `assetId = 0` placeholders need real assets |
| No shop, weekly forecast, or emote broadcast | — | v0.2 (spec §12) |

Everything tunable lives in `src/shared/Config.luau`.
