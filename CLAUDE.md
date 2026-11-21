# CLAUDE.md — Snowball Heist

Roblox game: *Snowball Heist: +1 Size Every Second*. The full design is in `docs/GAME_SPEC.md`; read it before building anything. This file holds the standing engineering rules.

## Stack
- **Language:** Luau (strict mode: `--!strict` at the top of every file).
- **Sync:** Rojo. Files on disk are the source of truth; nothing is authored by hand in Studio except art, maps and UI layout.
- **Tools:** pinned in `rokit.toml` (Rojo, Selene, StyLua, Lune). Install with `rokit install`.
- **Packages:** none via a package manager yet. ProfileStore (Apache 2.0, license in `docs/licenses/`) is vendored in `src/ServerScriptService/Server/Vendor/` — never edit it. Ask before adding any other dependency.
- **Pure logic:** `Shared/Formulas.luau` and `Shared/Format.luau` must not use Roblox globals or `require` anything; pass Config tables in as arguments. Config modules are plain tables with no requires. This keeps them runnable under Lune.
- **Lint/format:** Selene + StyLua. Run both before calling a task done.
- **Pure-logic tests:** Lune scripts in `tests/` for formulas (growth, income, rebirth, steal rules). Anything that doesn't touch Instances should be testable this way.

## You cannot run Roblox Studio
The human playtests. So, at the end of each task:
1. List exactly what to test in Studio, as numbered steps with expected results.
2. Name every Instance/asset the code expects to exist in the place file (e.g. `Workspace.Map.Zones.PineForest`, `ReplicatedStorage.Assets.Critters.Penguin`). Never assume they exist silently — fail loudly with a clear `warn`/`error` naming the missing path.

## Folder layout
```
src/
  ReplicatedStorage/Shared/
    Config/        -- ALL tunable numbers live here (Zones, Critters, Economy, Monetization, Events)
    Types.luau
    Net.luau       -- single place that defines RemoteEvents/RemoteFunctions
    Format.luau    -- big-number formatting (1.2K, 3.4M, 5.6B, 7.8T, then aa/ab...)
    Formulas.luau  -- pure game math (growth, costs, melt, income, radius)
    Signal.luau    -- tiny signal class
    DataTemplate.luau -- saved data shape + CURRENT_VERSION
  ServerScriptService/Server/
    Services/      -- one ModuleScript per system (GrowthService, CritterService, BaseService,
                   --   StealService, RebirthService, DataService, ShopService, EventService)
    Util/          -- server helpers (RateLimiter)
    Vendor/        -- third-party code (ProfileStore). Never edit.
    init.server.luau  -- creates remotes, then inits/starts services listed in SERVICE_ORDER
  StarterPlayer/StarterPlayerScripts/Client/
    Controllers/   -- StateController (state mirror), SnowballVisualController, HudController, etc.
    init.client.luau  -- inits/starts controllers listed in CONTROLLER_ORDER
tests/             -- Lune tests for pure logic
docs/GAME_SPEC.md
```
Simple Service/Controller pattern: each module returns a table with `init()` and `start()`. No large frameworks (no Knit).

## Non-negotiable rules
1. **Server-authoritative.** The server owns size, coins, critters, steals, locks and purchases. The client only sends *intents* ("I want to lock my base", "I pressed bank"). Validate every remote: type-check arguments, check distance and cooldowns, rate-limit per player.
2. **Numbers live in `Shared/Config`.** No magic numbers in services. A designer must be able to rebalance by editing Config only.
3. **Data safety.** ProfileStore with session locking. Save on leave and periodically. Version the data schema (`DataVersion` field) and write a migration whenever the shape changes. Never wipe data on a load error — kick with a message instead.
4. **Purchases.** Use `MarketplaceService.ProcessReceipt`, idempotent by `PurchaseId`, granted only after the profile is loaded, return `PurchaseGranted` only after the grant is saved. Gamepass checks are cached and re-checked on `PromptGamePassPurchaseFinished`.
5. **Performance (mobile first).** The giant snowball is a *visual* only: a client-side scaled mesh. Physics and hit detection use small server-side checks (`GetPartBoundsInRadius` / distance math), never a huge unanchored part. Target 60 FPS on a mid-range phone; avoid per-frame server loops — tick income and growth once per second.
6. **Platform policy (Kids/Select eligibility).** No media/video feeds, no autoplaying feeds, no rewards for watching anything. No player damage or death from other players — steals and bumps are knockback only. No real-money trading, no off-platform anything. Chat and text through Roblox's filtered systems only.
7. **Original IP only.** No copyrighted characters, brands or meme characters in names, models or text.

## Style
- `PascalCase` modules and Instances, `camelCase` locals and functions, `UPPER_SNAKE` for constants.
- Type every function signature. Prefer small functions. Comment *why*, not *what*.
- Remotes are named `Verb + Noun` (`RequestLockBase`, `CritterBanked`).

## Workflow
- Run `lune run tests/run`, `stylua src tests` and `selene src` before finishing a task.
- Data flow: services change data via `DataService.getData(player)`, then call `DataService.pushState(player, fields)`; the client reads it from `StateController`.
- Work one milestone (see GAME_SPEC §10) at a time. Don't start the next until the human confirms the playtest passed.
- Keep a `docs/CHANGELOG.md` entry per milestone: what was added, the Instances it expects, known issues.
- If the spec is ambiguous or a number seems wrong, ask instead of guessing, and propose a default.
