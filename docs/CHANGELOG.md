# Changelog

## M5 — Monetize

**Added**
- `GamePassService`: checks ownership once per player on join (cached), re-checks on `PromptGamePassPurchaseFinished`, and fires a `Changed` signal so services refresh. Passes with id 0 are skipped with one warning each. Sets the `Vip` attribute and pushes `Passes` to the client.
- Pass effects:
  - **2x Growth:** a growth multiplier.
  - **2x Coins:** income ×2.
  - **VIP:** 90 s lock, gold `[VIP]` chat tag (TextChatService), gold snowball trail.
  - **+2 Carry Slots.**
  - **Auto-Collect:** pedestal income goes straight to coins every tick.
- `ShopService`: `MarketplaceService.ProcessReceipt` following CLAUDE.md rule 4:
  - only granted once the profile is loaded;
  - idempotent by `PurchaseId` (stored in the profile and capped at 200 entries);
  - `PurchaseGranted` is returned only after `OnAfterSave` confirms a save containing that id. Otherwise it returns `NotProcessedYet`, and the retry is safe.
- Products:
  - **Blizzard Luck:** a server-wide 3× non-Common spawn weight for 15 min, stacking, announced to everyone, with a HUD countdown.
  - **Coin Packs S/M/L/XL:** 10/40/150/600 minutes of current income.
  - **Starter Pack:** a Frost Hedgehog onto a pedestal plus 10 min of 2× growth, once.
- `Shared/Purchases.luau` (pure, Lune-tested): timer stacking, coin pack reward, receipt log.
- **Data v2:** `ProcessedReceipts` field, with a v1→v2 migration in `DataService` (`CURRENT_VERSION = 2`).
- Shop panel: Gamepasses and Boosts sections showing price, "Owned" or "Soon" (id 0). Buying opens Roblox's purchase prompt.
- Dev hooks: `GrantPass(player, key[, false])`, `SimulatePurchase(player, productKey[, purchaseId])`. `SimulatePurchase` runs the real receipt handler, so the same `purchaseId` twice tests idempotency.
- Lune tests: 50 passing.

**Before launch, on the Creator Dashboard:** create the 5 gamepasses and 6 developer products, then paste their ids into `Config/Monetization.luau`. Until then the Shop shows "Soon", and Studio prints one warning per item.

**Expects in the place file:** `StarterGui.Hud` may also have a `LuckLabel` (TextLabel); otherwise the placeholder HUD makes one. TextChatService must be the chat version for VIP tags; it's Roblox's default.

**Known issues / notes (please confirm)**
- **Coin Pack floor:** a brand-new player earns about 0 coins/s, so "minutes of current income" would pay 0. Packs use at least `coinPackMinIncomePerSecond = 10` (Coin Pack S pays at least 6,000). Change it in `Config/Monetization.luau`.
- **Starter Pack critter:** the spec says "a Rare critter", and I picked the Bunny Slope Rare (Frost Hedgehog, 15 coins/s). If pedestals are full, its sell value is paid instead, so a paid item is never lost.
- The Starter Pack is limited to once in the UI and by `StarterPackBought`. A receipt that arrives anyway (e.g. bought on another device) is still granted, since the player paid for it.
- Real purchases can only be tested in a published place with real ids. `SimulatePurchase` exercises the same grant, save and idempotency path.

## M4 — Heist

**Added**
- `Shared/HeistRules.luau` (pure, Lune-tested): steal checks covering owner, hold time, already carrying, on foot, lock, new-player protection for both sides, fresh Mythic, and full pedestals. Also lock timeline (Locked → Cooldown → Unlocked), bump protection and ball contact.
- `StealService`:
  - **Village:** inside `Workspace.Map.Village`, players are on foot (`OnFoot` attribute) and the snowball parks outside their gate.
  - **Steal:** a server-timed 1.5 s hold on a rival's pedestal. The critter is welded above the thief's head and their walk speed drops from 20 to 12. They bank it by reaching their own gate; the owner tags it back by touching the thief.
  - **Safety:** while it's being carried, the critter stays in the owner's save, hidden. A crash or a leaving or respawning thief returns it, and only a completed steal moves it.
  - **Feedback:** steal alert and stolen toasts, plus `Stats.TotalSteals` and `TimesStolenFrom`. A per-server steal log is kept (`StealService.getLog()`).
  - **Bumps:** a ball at least 1.5× bigger knocks one carried critter loose from a smaller one. Victims have a 5 s cooldown, and there's 10 s of protection after leaving the village. Knockback is applied by the victim's client through the `Bumped` remote.
- `BaseService`: plot `Bounds` and `Barrier`, `RequestLockBase` (only inside your own igloo; 60 s lock, then a 10 s cooldown). Non-owners standing in a locked igloo are pushed out. Steal prompts sit on pedestals (key F) alongside Sell. `InPlot` attribute. Helper API for StealService.
- `CritterService`: `spawnLoose` (grabbable by anyone regardless of size after 0.75 s, gone after 10 s). No absorbing while on foot.
- Client:
  - `HeistController`: the Lock button with countdown appears while inside your igloo. Your own barrier is passable through the local `OwnBarrier` collision group. Handles knockback.
  - `BaseController`: shows Steal prompts to everyone except the owner.
  - The snowball visual handles on-foot mode: character shown, ball parked, camera reset.
- **Streaming-safe:** Studio places have instance streaming on by default, and a streamed-in part loses client-side changes. `ZoneGateController` and the barrier now re-apply their local state every tick instead of caching parts.
- Placeholder map: `Village` box, and per-plot `Bounds` and `Barrier` (4 ice walls).
- Dev hooks: `SkipProtection`, `DropCarried` (simulates being bumped).
- Lune tests: 46 passing.

**Expects in the place file:**
- `Workspace.Map.Village` (BasePart covering the whole village, invisible, CanCollide off).
- Per plot: `Bounds` (BasePart covering the igloo's inside) and `Barrier` (BasePart or Model; the server shows it and makes it solid while locked).

**Known issues / notes**
- Stealing, tag-back, bumping and the locked-door push-out need **2 players** (Test → Clients and Servers). The rules are covered by Lune tests; the single-player Studio run covered on-foot mode, locking, the owner passing their own barrier, prompt visibility, popped-loose critters and their expiry.
- New-player protection (3 min) blocks steals in fresh test servers. Use `DevHooks.SkipProtection` on both players.
- Knockback is applied by the victim's client, so it's cosmetic and an exploiter could ignore it. Nothing gameplay-relevant depends on it.
- Walk speed is set by the server but enforced by the client (Roblox physics), so speed exploits are possible. A server-side speed check is a possible later hardening.

## M3 — Progress

**Added**
- `UpgradeService`: the `RequestBuyUpgrade(upgradeId)` remote (rate-limited, type-checked). It checks price and max level with `Formulas.upgradePurchase`, then tells Growth, Critter and Base services to refresh: growth rate, carry slots, and the pedestals drawn.
- `RebirthService`: `RequestMelt`. Checks `Formulas.canMelt` and applies `Formulas.applyMelt`, which resets size, coins and Packing Power and keeps critters, pedestals and carry slots. It unlocks the melt skin and auto-equips it, sends the player home before resetting size (so ZoneService doesn't yank them), and fires a `Melted` signal. `RequestEquipSkin` for owned skins. The `Skin` player attribute lets every client draw the skin.
- `LeaderboardService`: leaderstats `Size` and `Melts`. Global **Biggest Snowball** (`Stats.BiggestSize`) and **Most Melts** boards on village SurfaceGuis, backed by OrderedDataStores (`Economy.globalLeaderboardStores`). Writes are skipped when a value hasn't changed, everything refreshes every 60 s, and the final score is saved on leave via `ProfileReleasing`. In Studio with mock data, the boards rank this server's players instead and make no DataStore calls.
- `Config/Skins.luau`: Default plus 5 melt-unlock skins (my proposal; see notes). `Formulas.meltSkin`.
- Client: `Ui.luau` kit (left menu column, one panel at a time). **Shop** panel: upgrades with level, effect preview and cost, plus a skins list with equip. **Melt** panel: requirements in red/green, next multiplier, what resets, skin unlocked, confirm popup. **Index** panel: all 26 critters, "???" until discovered, F/G/A mutation badges, discovered count. The snowball redraws when the skin changes.
- `IndexDiscovered` and `Stats` added to the client state. New discoveries are pushed live.
- World signs (plots, gates, critters) are now sized in studs, so distant ones shrink instead of cluttering the screen. HUD coins and carry moved to the top-left, and the menu is centered on the left edge (clear of the mobile thumbstick and jump button).
- Dev hook: `game.ServerStorage.DevHooks.SetMelts:Invoke(game.Players.<Name>, 3)`.
- Lune tests: 38 passing.

**Expects in the place file** (placeholders in Studio):
- `Workspace.Map.Leaderboards.BiggestSnowball` and `.MostMelts` (BaseParts). The board is drawn on the **Front** face.
- Optional `ReplicatedStorage.Assets.Skins.<SkinId>` (BasePart). Without it, the snowball (or `Assets.Snowball`) is recolored with the skin's Config color and material.
- Shop, Melt and Index panels are built in code. There's no StarterGui authoring for them yet; the M6 mobile UI pass restyles them.

**Known issues / notes**
- **Skins are my proposal:** Frostbite, Sunset Slush, Mint Chip, Midnight Flurry and Aurora Glow unlock at melts 1–5. Melts 6+ give no skin. Rename or retune them in `Config/Skins.luau`.
- Uncollected pedestal coins survive a Melt (only `Coins` resets). It's a small bonus; say if you want pending cleared too.
- The global boards need a published place with API access. In Studio they show "(this server)".
- OrderedDataStore values are capped at 2^53, far above any realistic size.

## M2 — Collect

**Added**
- `CritterService`: each zone keeps `maxLiveCritters` alive, spawning one every `respawnSeconds`. The rarity roll skips rarities a zone doesn't have (`Formulas.pickCritter`), and a mutation is rolled at spawn. Absorbing is a server distance check every `Economy.absorbCheckSeconds` against the same sphere the client draws. It needs size ≥ the critter's `sizeRequired` and a free carry slot; "too small" and "slots full" toasts are throttled. Carried critters are session-only (lost on leave) and replicate through the `Carried` player attribute (`Shared/CarryCodec`). `IndexDiscovered` is recorded on absorb, for M3's Index.
- `BaseService`: gives each joining player a free plot and moves them there on spawn/respawn. Walking onto your **Gate** banks carried critters onto free pedestals. When pedestals are full, leftovers stay carried and a popup offers to sell them; that sale only works at your own gate. Income builds per pedestal every second. Walking onto the **Collect Pad** collects (with a toast), and standing on it keeps collecting. A hold prompt on your own pedestals sells that critter, including its uncollected income. Offline earnings (50%, capped at 2 h) arrive on join with a popup.
- `Shared/CritterLook`: builds critter models (asset or placeholder ball in the rarity color), applies the mutation tint/material, and adds the name/rarity/size sign.
- Client: carried critters stick to and roll with every snowball. `PopupController` (generic modal). `BaseController` hides other players' Sell prompts, offers "pedestals full → sell" and shows the offline-earnings popup. The HUD now shows coins (+income/s) and "Carrying n/m".
- Remotes: `PromptSellCarried` (server→client), `RequestSellCarried` (client→server, rate-limited, only at your own gate).
- Server utils: `MapLocator` (shared map lookup and placeholder build), `DevHooks` (Studio-only Command Bar helpers).
- Placeholder map: 6 plots in a ring around the origin (Gate, CollectPad, Spawn, 24 pedestals). Zones now start at z = 240.
- Formulas: `pickCritter`, `totalIncomePerSecond`. Lune tests: 34 passing.

**Studio dev hooks** (Command Bar set to **Server**, Play running):
- `game.ServerStorage.DevHooks.SetSize:Invoke(game.Players.<Name>, 300)`
- `game.ServerStorage.DevHooks.GiveCritter:Invoke(game.Players.<Name>, "PineFox", "Golden")`
- `game.ServerStorage.DevHooks.SetCoins:Invoke(game.Players.<Name>, 1e6)`
- `game.ServerStorage.DevHooks.SimulateOffline:Invoke(game.Players.<Name>, 3600)`

**Expects in the place file** (placeholders in Studio; each warns by path when missing):
- `Workspace.Map.Plots.Plot1..Plot6`, each with `Gate` (BasePart), `CollectPad` (BasePart), `Pedestals` (Folder of BaseParts `Pedestal1..Pedestal24`), and optional `Spawn` (BasePart).
- Optional `Workspace.Map.Zones.<Zone>.CritterSpawns` (Folder of BaseParts; critters spawn on their top faces). Without it, critters drop onto solid ground somewhere inside the zone's `Bounds`.
- `ReplicatedStorage.Assets.Critters.<CritterId>` (Model or BasePart, all 25 + `GroupPenguin`). Mutation looks are applied as a tint plus material (`Config/Visuals.mutationLooks`).
- `StarterGui.Hud` now also needs `CoinsLabel` and `CarryLabel` (TextLabels).
- `StarterGui.Popup` (ScreenGui, `ResetOnSpawn` off, `Enabled` off) with `TitleLabel`, `BodyLabel` (TextLabels), and `ConfirmButton`, `CancelButton` (TextButtons).

**Known issues / notes**
- Offline earnings can't be tested for real in Studio, because the mock store doesn't persist. Use `SimulateOffline`, or turn off `useMockDataInStudio` (needs API access).
- "Swap" on full pedestals means selling one from a pedestal, then stepping on the gate again. There's no one-click swap UI.
- Luck (M5 server luck, M6 events), the +2 Carry Slots pass and the 2x Coins pass are marked with comments where they plug in, but not wired yet.
- Critter models spawn server-side. With 48 live critters plus up to 144 pedestal models in a full server, keep critter meshes under ~2k tris (spec §14).
- Each missing critter asset prints one warning, so expect a burst of warnings until the art exists.

## M1 — Grow

**Added**
- `GrowthService`: +size every `Economy.tickSeconds` on the server using `Formulas.growthPerSecond`. Pushes `Size` + `GrowthPerSecond` to the owner and sets a `Size` player attribute so every client can draw everyone's snowball. `registerMultiplier(name, fn)` for later passes/events; the code/Starter Pack growth boost (`GrowthBoostEndsAt`) is already wired. `setSize(player, n)` is the one way to change size. Tracks `Stats.BiggestSize`.
- `ZoneService`: Ice Gates. Gates are solid on the server; the server checks each player against every zone's `Bounds` once per `Economy.zoneCheckSeconds` and sends anyone too small back to `VillageSpawn`. Sends `Notify` toasts on zone unlock / when sent back.
- `Util/PlaceholderMap`: in Studio only, if `Workspace.Map` is missing, builds a straight-line test map (zones along +Z, each behind a gate). Layout in `Config/Dev.placeholderMap`; toggle `buildPlaceholderMapInStudio`.
- `SnowballVisualController`: client-only snowball per player (anchored, no collision/query/touch), radius from `Formulas.visualRadius`, eased between ticks, rolls with movement, hides the character, scales camera zoom and focus with the ball.
- `ZoneGateController`: "Zone / Size N" sign on each gate; gates you've earned go invisible and non-solid for you only. `GateShattered` signal for M6 VFX.
- `HudController`: size counter, "+N" popup each tick, growth/s, next gate, toasts.
- `Config/Visuals.luau` (client look/camera/HUD timings), `Economy.zoneCheckSeconds`, `Net.Attributes`, `Format.rate`, `Formulas.nextZoneIndex`.
- Studio-only dev hook: `game.ServerStorage.DevHooks.SetSize:Invoke(game.Players.<Name>, 300)`.
- Removed the M0 client smoke-test print. Lune tests: 29 passing.

**Expects in the place file** (all optional in Studio thanks to placeholders, each warns by path when missing):
- `Workspace.Map.VillageSpawn` (BasePart): where players caught past a gate are sent.
- `Workspace.Map.Zones.<BunnySlope|PineForest|GlacierValley|AuroraPeak>.Bounds` (BasePart covering the whole zone, invisible, CanCollide off).
- `Workspace.Map.Zones.<PineForest|GlacierValley|AuroraPeak>.IceGate` (BasePart or Model, solid).
- `ReplicatedStorage.Assets.Snowball` (BasePart/MeshPart; falls back to a white ball).
- `StarterGui.Hud` (ScreenGui, `ResetOnSpawn` off) with TextLabels `SizeLabel`, `GrowthLabel`, `NextZoneLabel`, `ToastLabel` anywhere inside (falls back to a placeholder HUD).

**Known issues / notes**
- Size grows everywhere, including the village. The village on-foot mode (snowball parked at the gate) is M4.
- The snowball is visual only: at large sizes it clips through walls/trees while the character fits through small gaps. That's by design (CLAUDE.md rule 5).
- Placeholder map has no side walls, so you can walk around a gate; the server Bounds check still sends you back if you enter a locked zone.
- A Melt (M3) that drops size below a zone's requirement will send a player standing in that zone back to the village. Intended, but worth a toast in M3.
- Gate enforcement checks once per second, so a cheater could be inside a locked zone for up to 1 s.

## M0 — Setup (scaffold)

**Added**
- Rojo project (`default.project.json`), Rokit toolchain (`rokit.toml`), StyLua, Selene, VS Code extension list.
- `Shared/Config/` with every number from GAME_SPEC: Zones, Critters (25 + Group Penguin), Economy, Monetization (IDs set to 0 until created), Events, Dev.
- `Shared/Formulas.luau`: growth, upgrade costs, carry slots, pedestals, income, sell value, offline earnings, melt, bump, rarity and mutation rolls, highest zone.
- `Shared/Format.luau`: 1.23K / 4.5M / 1aa formatting, commas, durations, countdown clocks.
- `Shared/Net.luau` (single place for remotes), `Shared/Signal.luau`, `Shared/DataTemplate.luau` (save schema v1).
- `Server/Services/DataService.luau`: ProfileStore sessions, Reconcile, versioned migrations, kick instead of blank data on failure, LastOnline stamped on save, state pushed to the client.
- `Server/Util/RateLimiter.luau` for validating client requests in later milestones.
- `Client/Controllers/StateController.luau`: read-only mirror of the player's state.
- Vendored ProfileStore (Apache 2.0) in `Server/Vendor/`.
- Lune tests: 26 passing (`lune run tests/run`).

**Expects in the place file:** nothing yet.

**Known issues / notes**
- Studio playtests use ProfileStore's mock store (`Config/Dev.useMockDataInStudio = true`), so data won't persist between Studio sessions. Set it to false and enable *Studio Access to API Services* to test real saving.
- Selene's Roblox standard library must be generated once on your machine: `selene generate-roblox-std`.
