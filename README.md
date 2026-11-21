# Snowball Heist: +1 Size Every Second

Roblox game, written in Luau and synced into Studio with Rojo.
Design: `docs/GAME_SPEC.md` · Rules for Claude Code: `CLAUDE.md` · Progress: `docs/CHANGELOG.md`

## One-time setup (Windows)

1. **Install Rokit** (toolchain manager): download the Windows installer from
   https://github.com/rojo-rbx/rokit/releases, run it, then open a new terminal.
2. **Install the tools** from this folder:
   ```
   rokit install
   ```
   This installs Rojo, Selene, StyLua and Lune at the versions in `rokit.toml`.
3. **Install the Rojo plugin in Studio:**
   ```
   rojo plugin install
   ```
4. **Generate Selene's Roblox definitions** (once):
   ```
   selene generate-roblox-std
   ```
5. **VS Code (optional):** open the folder and accept the recommended extensions.
6. **Git:**
   ```
   git init
   git add .
   git commit -m "M0 scaffold"
   ```

## Every work session

1. Open your place in Roblox Studio (the map and art live in the place file, not here).
2. In this folder, run:
   ```
   rojo serve
   ```
3. In Studio: **Plugins → Rojo → Connect**. Code changes now sync live.
4. Press **Play** to test.

## Checks

```
lune run tests/run     # pure-logic tests
stylua src tests       # format
selene src             # lint
```

## M0 playtest checklist

1. `rojo serve`, connect in Studio, press Play.
2. Output shows `[Server] Snowball Heist started with 1 service(s)`.
3. Output shows `[DataService] Loaded <you> (session #1, version 1, size 0, coins 0)`.
4. Output shows `[Client] Started with 1 controller(s)` and `[Client] State: size 0, coins 0, melts 0`.
5. In Explorer, `ReplicatedStorage.Remotes` contains `PlayerStateChanged`, `Notify` and `GetPlayerState`.
6. No red errors in Output.

## Before publishing

- Game Settings → Places → Server Size: **6**.
- Game Settings → Security: enable **Studio Access to API Services** (only if you turn off mock data).
- Create gamepasses and products on the Creator Dashboard and paste their IDs into `Config/Monetization.luau`.
