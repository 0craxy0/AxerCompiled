# Axer V1

A VapeV4ForRoblox-style loadstring script framework for Roblox, built in Luau.
Thin bootstrap, executor-filesystem caching with commit-pinned updates, an
in-house GUI, a module registry with config persistence, and per-game modules
keyed by PlaceId.

> **Note:** This project is a framework and ships only client-side, benign
> starter modules. Using exploit-style tooling violates the Roblox Terms of
> Service and can get accounts banned. Game-specific module content is the
> responsibility of whoever authors it.

## Usage

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/0craxy0/AxerCompiled/main/Axer%20V1/NewMainScript.lua", true))()
```

- **RightShift** toggles the GUI.
- **LeftControl + RightShift** panics: disables every module and removes the GUI.
- First run downloads the framework into the executor's `axer/` folder; later
  runs load from cache and only refresh when the repo commit changes.

## Repository layout

```
NewMainScript.lua        # the only file users execute (bootstrap + cache manager)
axer/
  main.lua               # boot: shims -> util -> registry -> GUI -> save -> game modules
  libraries/
    shims.lua            # Axer.Features capability detection + unified wrappers
    util.lua             # theme, signals, safe parenting, notifications
    module.lua           # module registry + lifecycle (tracked connections)
    gui.lua              # window, tabs, module cards, option widgets
    save.lua             # JSON config profiles per PlaceId
  games/
    universal.lua        # modules that run in every game
    <PlaceId>.lua        # game-specific module files (optional)
  assets/
  profiles/              # commit.txt + per-game config.json
```

The GitHub distribution repo (`0craxy0/AxerCompiled`) mirrors the `axer/`
folder inside the `Axer V1/` subfolder (configure via `REPO`/`SUBFOLDER` in
`NewMainScript.lua`). Any `.lua` file pulled from the repo is stamped with a
cache watermark so updates can wipe managed files without touching user data.

## Authoring modules

Drop this in `axer/games/universal.lua` or `axer/games/<PlaceId>.lua`:

```lua
Axer.CreateModule({
    Name = 'My Module',
    Description = 'What it does',
    Tab = 'Utility',                     -- GUI tab (created on demand)
    Init = function(self)                -- once, at registration
        self:AddOption('Toggle', 'enabled', { Name = 'Enabled' })
    end,
    OnEnable = function(self)            -- every enable
        self:Track(workspace.ChildAdded:Connect(print))  -- auto-cleaned on disable
    end,
    OnDisable = function(self) end,
})
```

Module API:

| Member | Description |
| --- | --- |
| `Enabled` | Current state. |
| `:Toggle(state?)` | Flip or force state; runs `OnEnable`/`OnDisable`. |
| `:Track(connection)` | Disconnect automatically when the module disables. |
| `:AddOption(type, id, def)` | GUI widget: `'Toggle'`, `'Slider'`, `'List'`, `'Button'`, `'Keybind'`, `'TextBox'`. |
| `:GetOption(id)` / `:SetOption(id, value)` | Read/write option values (updates the widget, queues a save). |

Options persist automatically to `axer/profiles/<PlaceId>/config.json`
(debounced autosave; restored on boot).

## Executor compatibility

`Axer.Features` detects what the current utility supports and everything
degrades gracefully:

| Feature flag | Meaning |
| --- | --- |
| `fs` | Real filesystem present, otherwise files live in memory for the session. |
| `http` | Working HTTP (`game:HttpGet` or `request`-family). |
| `getcustomasset`, `drawables`, `debug`, `queue_on_teleport`, `mouse` | Optional executor extras for future modules. |

Without filesystem APIs Axer still boots fully (no caching, no profiles).

## Development workflow

Run in Roblox Studio's command bar with the repo folder as the workspace:

```lua
shared.AxerDeveloper = true
loadstring(readfile('NewMainScript.lua'))()
```

Dev mode skips GitHub entirely and loads `axer/` straight from disk, so
edits apply on the next execute without pushing commits.

## Offline tests

`test/run_boot_test.py` seeds the real axer sources into a mocked
Roblox/executor filesystem and boots the actual `axer/main.lua` through the
same loadstring pipeline used in-game (requires the standalone Luau CLI in
`.freebuff/tools/`):

```
python test/run_boot_test.py
```

It registers the universal modules, toggles them, serializes config, writes it
through the (mocked) filesystem, decodes it back, restores, and panics — 29
assertions total.
