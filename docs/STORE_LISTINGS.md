# Store listings

Create these on the Creator Dashboard (create.roblox.com → Creations → your game → Monetization),
then paste each ID into `src/ReplicatedStorage/Shared/Config/Monetization.luau` (the `id = 0` fields).
Icons: `art/icons/<Key>.png` (512×512, art kept inside the circle Roblox crops pass icons to).
Regenerate with `python tools/make_icons.py`.

## Gamepasses (Monetization → Passes)

| Key | Price | Name | Description | Icon |
|---|---|---|---|---|
| TwoXGrowth | R$249 | Double Growth | Your snowball grows twice as fast, forever! Stacks with Packing Power and Melts. | TwoXGrowth.png |
| TwoXCoins | R$299 | Double Coins | Every critter on your pedestals earns twice the Frost Coins, forever! | TwoXCoins.png |
| VIP | R$399 | VIP Snowball | Lock your igloo for 90 seconds instead of 60, plus a gold VIP chat tag and a golden snowball trail. | VIP.png |
| ExtraCarrySlots | R$199 | Bigger Pockets | Carry 2 extra critters on your snowball at once. | ExtraCarrySlots.png |
| AutoCollect | R$349 | Auto-Collect | Coins from your pedestals go straight to you. No need to walk to the Collect Pad! | AutoCollect.png |

## Developer products (Monetization → Developer Products)

| Key | Price | Name | Description | Icon |
|---|---|---|---|---|
| BlizzardLuck | R$149 | Blizzard Luck | 3× rare critter spawns for EVERYONE in the server for 15 minutes. Time stacks! | BlizzardLuck.png |
| CoinPackS | R$49 | Coin Pouch | Get 10 minutes of your current coin income instantly. | CoinPackS.png |
| CoinPackM | R$149 | Coin Sack | Get 40 minutes of your current coin income instantly. | CoinPackM.png |
| CoinPackL | R$499 | Coin Chest | Get 150 minutes of your current coin income instantly. | CoinPackL.png |
| CoinPackXL | R$1,499 | Coin Vault | Get 600 minutes of your current coin income instantly. | CoinPackXL.png |
| StarterPack | R$9 | Starter Pack | A Rare Frost Hedgehog for your igloo plus 10 minutes of 2× growth. One per player! | StarterPack.png |
