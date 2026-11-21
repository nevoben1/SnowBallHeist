# Snowball Heist: +1 Size Every Second — Game Spec (MVP v0.1)

All numbers below are starting values to be tuned. They go in `Shared/Config` and nowhere else.

---

## 1. Pitch
You're a snowball that grows **+1 size every second**. Roll up the mountain, absorb cute frozen critters, bring them home to your igloo where they earn Frost Coins every second, and steal critters from other players' igloos. Melt down to rebirth with a permanent multiplier and do it all again bigger.

**The title is the tutorial.** A new player should get it in 5 seconds with no text.

## 2. Server & session
- **Max players per server:** 6 (5–8 is the genre's sweet spot; stealing needs to feel personal).
- **Target session:** 8–12 minutes, with a reason to come back (income keeps building, scheduled events).
- **Platform target:** mobile first, then PC and console. Kids/Select eligible: Minimal/Mild content only.

## 3. Map layout
- **Igloo Village (center plaza):** 6 igloo plots in a ring, about 150 studs apart. Players walk **on foot** inside the village; the snowball parks at your igloo gate.
- **The Mountain:** four zones climbing outward and upward from the village. Each zone is behind an **Ice Gate** that only shatters for snowballs at or above its size requirement.

| # | Zone | Size to enter | Feel |
|---|---|---|---|
| 1 | Bunny Slope | 0 | Gentle, open, tutorial |
| 2 | Pine Forest | 300 | Trees, narrow paths |
| 3 | Glacier Valley | 3,000 | Ice, cliffs, slippery |
| 4 | Aurora Peak | 30,000 | Night sky, aurora, rare spawns |

With no upgrades, zone 2 takes about 5 minutes. Upgrades and rebirths should bring zone 4 within reach in roughly 45–60 minutes for a first-time player.

## 4. Core stats & formulas
**Size** (persistent, resets on Melt):
```
growthPerSecond = 1 × packingMult × meltMult × passMult × eventMult
packingMult     = 1 + 0.5 × packingLevel
passMult        = 2 if "2x Growth" gamepass else 1
```
Size ticks once per second on the server only.

**Visual radius** (client only; size goes into the billions, so use a log curve):
```
radiusStuds = min(2 + 3 × log10(size + 1), 60)
```

**Frost Coins:** earned from critters on your pedestals (§6). Spent on upgrades.

**Upgrades (coin shop):**

| Upgrade | Effect per level | Cost formula | Max |
|---|---|---|---|
| Packing Power | +0.5× growth | `50 × 1.6^level` | 50 |
| Carry Slots | +1 carried critter (base 3) | `500 × 4^level` | 3 (→ 6) |
| Pedestals | +2 pedestals (base 8) | `1,000 × 2.5^level` | 8 (→ 24) |

## 5. Critters
Critters spawn as world entities in their zone. Touch one while your size ≥ its **Size Req** to absorb it; it sticks to your snowball (visual) and fills a **carry slot**.

**Rarity spawn weights:** Common 60 · Uncommon 25 · Rare 10 · Epic 4 · Legendary 0.9 · Mythic 0.1
Each zone keeps up to 12 live critters per server and respawns one every 4 seconds.

| Zone | Critter | Rarity | Size Req | Coins/sec |
|---|---|---|---|---|
| Bunny Slope | Snow Bunny | Common | 1 | 1 |
| Bunny Slope | Chickadee Puff | Common | 5 | 2 |
| Bunny Slope | Mitten Mouse | Uncommon | 15 | 4 |
| Bunny Slope | Snowflake Moth | Uncommon | 30 | 6 |
| Bunny Slope | Frost Hedgehog | Rare | 80 | 15 |
| Bunny Slope | Pebble Seal | Epic | 200 | 40 |
| Pine Forest | Pine Fox | Common | 300 | 25 |
| Pine Forest | Acorn Owl | Common | 450 | 35 |
| Pine Forest | Icicle Squirrel | Uncommon | 700 | 60 |
| Pine Forest | Sleepy Badger | Rare | 1,200 | 120 |
| Pine Forest | Glowcap Elk | Epic | 2,000 | 300 |
| Pine Forest | Timber Moose | Legendary | 2,800 | 900 |
| Glacier Valley | Penguin Chef | Common | 3,000 | 250 |
| Glacier Valley | Walrus Drummer | Uncommon | 5,000 | 500 |
| Glacier Valley | Crystal Crab | Rare | 8,000 | 1,100 |
| Glacier Valley | Sled Husky | Epic | 14,000 | 2,800 |
| Glacier Valley | Frostback Turtle | Legendary | 22,000 | 8,000 |
| Glacier Valley | Glacier Narwhal | Mythic | 28,000 | 30,000 |
| Aurora Peak | Aurora Fox | Rare | 30,000 | 12,000 |
| Aurora Peak | Gentle Yeti | Epic | 50,000 | 30,000 |
| Aurora Peak | Comet Owl | Legendary | 80,000 | 90,000 |
| Aurora Peak | Ice Dragon Hatchling | Legendary | 120,000 | 150,000 |
| Aurora Peak | Polar Phoenix | Mythic | 200,000 | 600,000 |
| Event only | Blizzard Yeti King | Mythic | 50,000 | 1,000,000 |
| Event only | Starlight Ice Dragon | Mythic | 150,000 | 3,000,000 |

**Mutations** (rolled when a critter spawns; they multiply its income):

| Mutation | Chance | Income × | Look |
|---|---|---|---|
| Frosted | 8% | 1.5 | Icy sparkle |
| Golden | 1.5% | 3 | Gold sheen |
| Aurora | Event only | 6 | Shifting aurora colors |

**Selling:** a critter sells for `coinsPerSec × 60`, used when your pedestals are full.

## 6. Base (Igloo)
- On join, the player is assigned a free igloo plot. Their critters are placed on its **pedestals**.
- **Banking:** roll up to your igloo gate. All carried critters move onto free pedestals (or a "pedestals full" prompt offers to sell or swap).
- **Income:** each pedestal builds up coins (`coinsPerSec × meltIncomeMult × coinPassMult`). The player **walks over a Collect Pad** to collect. This keeps players returning to their base, which makes defense matter. The *Auto-Collect* gamepass removes the need.
- **Offline earnings:** 50% of the rate, capped at 2 hours, given on rejoin with a popup.

## 7. Stealing & defense
**Steal (on foot, inside the village):**
1. Walk into a rival's igloo while it's unlocked.
2. Hold the interact key/button on a pedestal for 1.5 seconds to pick up the critter.
3. While carrying: walk speed 12 (normal 20), no snowball, critter visible above your head.
4. Reach your own igloo to bank it. The critter now belongs to you.
5. If the owner touches you first, the critter snaps back to their pedestal.

**Lock:** a button inside your igloo locks the door for 60 seconds (VIP: 90), then it unlocks and has a 10-second cooldown. Locked igloos block entry with an ice barrier.

**Protections:**
- Players can't steal during their first 3 minutes in the server, and can't be stolen from during that time either.
- Mythic critters can't be stolen during their first 10 minutes after banking.
- Steals are logged per server, and an owner sees a toast saying "X stole your Y!".

**Bumping (on the mountain):** if snowball A is at least 1.5× the size of snowball B and they collide, B loses 1 random *carried* (not banked) critter. It pops loose and anyone can grab it for 10 seconds; then it despawns. B gets cartoon knockback only, with no damage. Each victim has a 5-second bump cooldown. Players get 10 seconds of spawn protection after leaving the village.

**Post-MVP defense:** Ice Walls (extra hold time for thieves) and a Guard Snowman (slows thieves inside your igloo).

## 8. Melt (rebirth)
Requirements and rewards for Melt `r` (the next melt):
```
sizeRequired  = 10,000 × 3^r
coinsRequired = 25,000 × 4^r
meltMult      = 1.5^(r+1)        -- applies to growth AND income
```
**Resets:** size, coins, Packing Power level. **Keeps:** critters, pedestals, carry slots, gamepasses, cosmetics.
Each Melt also unlocks one snowball skin. Show the next multiplier clearly so players see what they're working toward.

## 9. Monetization
**Gamepasses (one-time):**

| Pass | Price | Effect |
|---|---|---|
| 2x Growth | R$249 | Doubles growthPerSecond |
| 2x Coins | R$299 | Doubles income |
| VIP | R$399 | 90-second lock, chat tag, VIP snowball trail |
| +2 Carry Slots | R$199 | Carry 2 more critters |
| Auto-Collect | R$349 | Income collects automatically |

**Developer products (repeatable):**

| Product | Price | Effect |
|---|---|---|
| Blizzard Luck (server-wide) | R$149 | 15 minutes of 3× non-Common spawn weight for **everyone in the server**; time stacks; announced with the buyer's name |
| Coin Pack S / M / L / XL | R$49 / 149 / 499 / 1,499 | 10 / 40 / 150 / 600 minutes of the buyer's current income |
| Starter Pack (one per player) | R$9 | A Rare critter plus 10 minutes of 2× growth |

**Cosmetics:** snowball skins (R$75–199), trails. No pay-to-steal-without-counterplay.

## 10. Events & live ops
- **Blizzard Admin:** Tuesdays and Saturdays at 18:00 UTC for 15 minutes. Snowstorm VFX, 10× rare weights, event critters spawn in Aurora Peak. A countdown timer shows in the HUD.
- **Aurora Night:** every 2 hours, 5 minutes long. Spawns can roll the Aurora mutation (5%).
- **Admin commands:** a whitelist of UserIds in Config can trigger any event, give currency for testing, and spawn a specific critter.
- **Codes:** list in Config (`code`, reward, expiry). Launch with `SNOWBALL` (coins) and `HEIST` (2× growth for 10 minutes).
- **Group reward:** joining the creator's group gives a free "Group Penguin" (Rare, 50 coins/sec) once.
- **Weekly update** plan: new critters, skins, a new event twist. Not in the MVP code.

## 11. UI
- **HUD:** big size counter with +growth/s popping off, coins, carry slots, event countdown, lock button (when in base).
- **Shop:** upgrades, gamepasses, products.
- **Melt panel:** requirements, the next multiplier, confirm.
- **Index (collection book):** every critter, with silhouettes for undiscovered ones and mutation badges. Completion rewards are post-MVP.
- **Leaderboards:** in-server (size, melts), plus global boards in the village for Biggest Snowball and Most Melts (OrderedDataStore, refreshed every 60 seconds).
- **Toasts:** steal alerts, rare spawn announcements ("A Legendary Comet Owl appeared in Aurora Peak!"), and server luck purchases.

## 12. Data schema (ProfileStore)
```lua
{
  DataVersion = 1,
  Size = 0,
  Coins = 0,
  Melts = 0,
  Upgrades = { PackingPower = 0, CarrySlots = 0, Pedestals = 0 },
  Critters = { -- banked
    { Id = "uuid", CritterId = "PineFox", Mutation = "None" | "Frosted" | "Golden" | "Aurora",
      BankedAt = 0, Pending = 0 },
  },
  IndexDiscovered = { [CritterId] = { None = true, Golden = true, ... } },
  RedeemedCodes = { [code] = true },
  StarterPackBought = false,
  GroupRewardClaimed = false,
  Skins = { Owned = {}, Equipped = "Default" },
  LastOnline = 0,
  Stats = { TotalSteals = 0, TimesStolenFrom = 0, BiggestSize = 0 },
}
```
Carried critters are session-only. If a player leaves while carrying, the critters are lost (a toast warns players about this).

## 13. Build milestones (one Claude Code session each)
Each milestone ends with a Studio playtest list from Claude Code and a confirmed pass from you.

- **M0 — Setup:** Rojo project, Wally + ProfileStore, Selene/StyLua, folder layout, `Net`, `Format`, Config skeleton, DataService, Lune test harness.
- **M1 — Grow:** +1/sec growth on the server, client snowball visual with the log radius, size HUD, zone Ice Gates.
- **M2 — Collect:** critter spawners, rarity and mutations, absorbing, carry slots, banking, pedestals, Collect Pad income, offline earnings, selling.
- **M3 — Progress:** upgrade shop, Melt, leaderboards, Index.
- **M4 — Heist:** on-foot stealing, carrying, lock, owner tag-back, bumping, protections, steal toasts.
- **M5 — Monetize:** gamepasses, products, server luck, Starter Pack, receipt handling.
- **M6 — Live ops & polish:** Blizzard Admin and Aurora Night, admin commands, codes, group reward, sounds/VFX hooks, mobile UI pass.

**Target:** M0–M5 in about 3 weeks to soft-launch mid-December; M6 before Christmas.

## 14. Assets you need to make or source (not code)
- Mountain map with 4 zones, Ice Gates, Igloo Village with 6 plots.
- Igloo model with pedestals, Collect Pad, lock barrier.
- 25 critter models (low-poly, under ~2k triangles each) plus a frozen and gold material variant.
- Snowball mesh plus 5+ skins, trails.
- VFX: snowstorm, aurora sky, gate shatter, absorb pop, steal alert.
- Sounds: absorb, bank, coins, gate shatter, lock, steal alarm, music.
- Icons for gamepasses and products, game icon and thumbnails.

Put models in `ReplicatedStorage.Assets` with names matching each `CritterId` exactly.

## 15. Before launch
- Complete the maturity & compliance questionnaire, aiming for **Minimal/Mild**; complete the creator verification Roblox requires for Kids/Select discovery.
- Check that no feature rewards watching media or autoplaying feeds.
- Test on a low-end phone: 6 players, max-size snowballs, Blizzard event active.
- Create a test place for updates; never push untested changes to the live place.

---

## Next prompt to paste into Claude Code
M0 (setup) is already done — see `docs/CHANGELOG.md`.
> Read `CLAUDE.md`, `docs/GAME_SPEC.md` and `docs/CHANGELOG.md`. Do milestone **M1** only: GrowthService (+1/sec size on the server using `Formulas.growthPerSecond`), ZoneService (Ice Gates that only open for snowballs at or above each zone's size), SnowballVisualController (client-side scaled snowball using `Formulas.visualRadius`) and a simple HudController showing size and growth per second. Use placeholder parts if the map isn't built yet and tell me exactly which Instances to create. End with a numbered Studio playtest checklist.
