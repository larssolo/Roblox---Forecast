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
- **Body customization** (the 💃 tab in styling): skin tone, height, body type, face and a
  runway pose. Each field is a server-clamped `Types.Appearance` that travels with the look,
  so everyone sees your body on the runway/podium. `face` is an **index into `Config.Faces`**
  (never a raw client-supplied decal id); add free classic-face ids there to fill the picker.
- **Primitive wardrobe** (`PrimitiveWardrobe.luau`): any item WITHOUT a real catalog asset id
  is still drawn in 3D from Roblox primitives (blocks/balls/wedges) hung on the avatar and
  palette-colored — so every one of the 42 items shows something on the figure. A real asset id
  on an item overrides its primitive with the proper mesh. Offsets are authored blind and need a
  Studio tuning pass (`BACK` flips front/back).

## Curating free avatar assets (make items show their real 3D look)

With `assetId = 0` the avatar still wears the item's **color**; give it a real Roblox catalog
asset id and the actual mesh renders on the character. The avatar **auto-detects each id's type**
at runtime (`MarketplaceService:GetProductInfo`) and routes it correctly — classic Shirt/Pants,
layered clothing, hair, hat, accessory — so **you only need the number**, nothing else. Per item:

1. Open the item's catalog page and copy the number from the url:
   `roblox.com/catalog/`**`1772336109`**`/Down-to-Earth-Hair`. (In Studio: right-click a Toolbox
   item → **Copy Asset ID**.) It must be a **catalog item** (`/catalog/…`) — a **bundle**
   (`/bundles/…`, e.g. classic shoe sets) is a package of parts, not a single asset, and won't wire in.
2. Add it to the `ASSET_IDS` map in `src/shared/ItemCatalog.luau`, keyed by item id:
   `top_crop_tee = 85096965320078,`

Already wired: `hair_bob` = Down-to-Earth Hair, `hair_long_waves`, `bot_cargo` = Cargo Pants Brown,
`bot_flare`, `top_crop_tee` = Fire Shirt B, `acc_shades` = glasses, `shoe_sneaker` = shoes.

**Bulk harvest:** to fill the rest fast, run `tools/harvest-free-assets.luau` in a Studio Play
session (paste it into the Command Bar) — it lists free catalog items with ids per slot, ready to
paste into the `ASSET_IDS` map. The avatar APIs are Studio-only, so this can't run from CI.

Custom items that aren't in the catalog (your own designs) mean real UGC work — 3D modeling plus a
Robux-paid upload and moderation — done in Studio or by an artist, not scriptable here.

## Deliberate scaffold limitations (read before playtesting for real)

| Gap | Where | Plan |
| --- | --- | --- |
| Profiles are **in-memory only** | `DataService.luau` | Wire [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) behind the existing interface (spec §9.5) |
| Trend heat is **per-server** | `TrendEngineService.luau` | Swap storage for MemoryStore HashMap + UpdateAsync lazy decay (spec §9.6) — math stays identical |
| Catalog items ship with **`assetId = 0`** | `ItemCatalog.luau` | Paste real free catalog ids (recipe above) so items render their mesh, not just their color |
| Runway is a **ViewportFrame avatar**, not a 3D world stage | `CharacterViewport.luau` | A real in-world catwalk with camera/lighting is the bigger v0.3 upgrade |
| No weekly forecast / Oracle board | — | v0.2 (spec §12) |

Everything tunable lives in `src/shared/Config.luau`.
