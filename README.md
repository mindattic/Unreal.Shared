# Unreal.Shared
Shared Unreal plugin for every MindAttic Unreal game: the common features the games would otherwise copy, starting with an optional `--headless` launch mode for scripted and automated testing.

![C++](https://img.shields.io/badge/C%2B%2B-20-00599C) ![Unreal](https://img.shields.io/badge/Unreal-5.8-black) ![License](https://img.shields.io/badge/license-MIT-blue) ![Status](https://img.shields.io/badge/status-1.0-green)

```text
MyGame.exe --headless            (or MINDATTIC_HEADLESS=1)
  EarliestPossible   MindAtticHeadless adds -RenderOffScreen -unattended -nosplash -nosound, mutes
  splash, RHI, Slate no splash, no swap chain, no window
  engine up          OnReady() broadcast, then one log line:
                     [2026.11.06-21.11.44:000][  0]MINDATTIC_HEADLESS_READY MyGame
```

The Unity counterpart is [Unity.Shared](https://github.com/mindattic/Unity.Shared), which follows the same headless contract.

## Why

- One way to run any MindAttic Unreal game for a test or CI script: the real game, no window, driven and queried by a script.
- One switch, the same in every Unity and Unreal game: `--headless` or `MINDATTIC_HEADLESS=1`.
- Off by default. Without the switch the plugin does nothing at all: no flags, no log lines, no behaviour change.
- Scripts know when to start driving: they wait for one `MINDATTIC_HEADLESS_READY` log line.
- Games keep their own opt-ins (skip the main menu, take scripted input) in their own code, bound to one delegate.

## Features

- **Plugin `MindAtticShared`** at `Plugins/MindAtticShared/`, runtime module `MindAtticHeadless` (Core only, `LoadingPhase` `EarliestPossible`).
- **`FMindAtticHeadless::IsActive()`**: resolved once from the command line and environment; overridable for tests.
- **`FMindAtticHeadless::OnReady()`**: a multicast delegate broadcast once, when the game is up, in a headless run only.
- **The ready line**: exactly one log message `MINDATTIC_HEADLESS_READY <ProjectName>`, written right after `OnReady()`, once the engine loop has finished initialising (the first map is loaded).
- **No window from the switch alone**: the module adds the engine's own headless flags early enough for the splash and the RHI to obey them (see [The flags](#the-flags)).
- **`tools/Start-Headless.ps1`**: launches a built game exe or an editor `-game` run of a `.uproject` headless, prints the log path, and can wait for the ready line.

## Quick start

With this repo cloned next to the game's repo under `D:\Projects\MindAttic`, in the game's `.uproject`:

```json
"Plugins": [
  { "Name": "MindAtticShared", "Enabled": true }
],
"AdditionalPluginDirectories": [
  "../Unreal.Shared/Plugins"
]
```

Then run it headless:

```powershell
..\Unreal.Shared\tools\Start-Headless.ps1 -Project .\MyGame.uproject -Wait
```

## Adopting it in a game

Every MindAttic Unreal game adopts it the same way.

### 1. The .uproject

Add the plugin and the directory it lives in. Relative paths are from the folder that holds the `.uproject`, with the repos side by side under `D:\Projects\MindAttic`:

| Where the .uproject is | `AdditionalPluginDirectories` entry |
|---|---|
| repo root (`Unreal.Soulslike/UnrealSoulslike.uproject`) | `"../Unreal.Shared/Plugins"` |
| a subfolder (`SpaceGod/Cpp/SpaceGod.uproject`, `Unreal.Soulslike/CSharp/...`, `*/CSharp/...`) | `"../../Unreal.Shared/Plugins"` |

```json
{
  "Plugins": [
    { "Name": "MindAtticShared", "Enabled": true }
  ],
  "AdditionalPluginDirectories": [
    "../../Unreal.Shared/Plugins"
  ]
}
```

Append to the existing arrays; keep entries already there (SpaceGod already has `"../Shared/Plugins"`). That alone gives the game `--headless` with no window and the ready line. The plugin is built with the game's own targets, like any project plugin; nothing is copied into the game.

### 2. Build.cs (only if the game's code calls the API)

```csharp
PrivateDependencyModuleNames.Add("MindAtticHeadless");
```

### 3. The game's own opt-ins

```cpp
#include "MindAtticHeadless.h"

void FMyGameModule::StartupModule()
{
	if (FMindAtticHeadless::IsActive())
	{
		// e.g. skip the main menu, take scripted input instead of a real mouse and keyboard
	}
	FMindAtticHeadless::OnReady().AddLambda([] { /* the first map is loaded and the game is up */ });
}
```

- `IsActive()` can be called at any time, from any module, from `StartupModule` on.
- Bind `OnReady()` in `StartupModule` (or any time before the engine finishes initialising). It fires once, before the ready line, so anything it does is done when a script sees the line. Bound later, it never fires: check `HasSignalledReady()` instead.
- Keep game-specific behaviour in the game. The plugin never skips menus or changes input.

## API

All in `MindAtticHeadless.h`, class `FMindAtticHeadless`.

| Call | What it does |
|---|---|
| `IsActive()` | True in a headless run. Resolved once; `SetActiveOverride` wins. |
| `OnReady()` | `FOnMindAtticHeadlessReady&`, broadcast once when the game is up, headless only. |
| `HasSignalledReady()` | True once `OnReady` has fired and the ready line is written. |
| `GetSuppliedEngineFlags()` | The engine flags the module added this run (e.g. `-RenderOffScreen`). |
| `SetActiveOverride(bool)` / `ClearActiveOverride()` | Tests: force `IsActive()`. Engine flags are decided at start-up and do not change. |
| `IsRequested(CommandLine, EnvValue)` | The rule, without side effects. |
| `ReadyMarker` / `EnvironmentVariable` | `"MINDATTIC_HEADLESS_READY"` / `"MINDATTIC_HEADLESS"`. |

## The flags

On when the command line has `--headless` or `-headless` (any case, as a whole argument) or the environment has `MINDATTIC_HEADLESS=1`. Anything else, `MINDATTIC_HEADLESS=0` included, is off.

Is `--headless` enough on its own? Partly. The module loads at `EarliestPossible`, inside `FEngineLoop::AppInit`, and appends to `FCommandLine` whichever of these flags are missing. Measured on UE 5.8 with `tests/HostProject`:

| Engine flag | Added by the plugin | Takes effect from the plugin alone? |
|---|---|---|
| `-RenderOffScreen` (not added when `-nullrhi` is given) | yes | **Yes.** The splash (`FPlatformSplash::Show`), `RHIInit`, the swap chain and Slate's windows all read the command line later. No window ever opens. |
| `-nosplash` | yes | **Yes**, for the same reason. |
| `-unattended` | yes | **No.** `FApp::IsUnattended()` caches its answer before any plugin can load, so engine dialogs are not suppressed. |
| `-nosound` | yes | **No.** The audio device manager is created at `IniSystemReady`, just before. The module sets `FApp::SetVolumeMultiplier(0)` instead: silent, but an audio device still opens. |

No game module can do better: `EarliestPossible` is the earliest any plugin or project module loads. So the full headless contract is the switch **plus** `-unattended -nosound` on the real command line, which is what `tools/Start-Headless.ps1` passes (with `-RenderOffScreen -nosplash` too, so it also works for a game that has not adopted the plugin). This is the same contract as SpaceGod's `tools/play.ps1 -Offscreen`.

`-RenderOffScreen` still renders frames (screenshots and frame read-back work). For no GPU work at all, pass `-nullrhi` (or `Start-Headless.ps1 -NullRhi`); the plugin then does not add `-RenderOffScreen`.

## The launcher

`tools/Start-Headless.ps1`, called from a game's run scripts by relative path:

```powershell
# An editor -game run of a .uproject (needs the game's editor target built)
..\Unreal.Shared\tools\Start-Headless.ps1 -Project .\Cpp\SpaceGod.uproject -Wait

# A built game exe, with arguments passed through to the game
$run = ..\..\Unreal.Shared\tools\Start-Headless.ps1 -Exe .\Build\Windows\MyGame.exe -Wait -TimeoutSeconds 120 -ExecCmds="stat fps"
# ... drive and query the game, read $run.LogPath ...
Stop-Process -Id $run.Process.Id
```

| Parameter | What it does |
|---|---|
| `-Project <.uproject>` | Runs `<EngineRoot>\Engine\Binaries\Win64\UnrealEditor.exe "<project>" -game -Multiprocess`. |
| `-Exe <game.exe>` | Runs a built game executable. |
| `-EngineRoot <dir>` | For `-Project`. Default `$env:MINDATTIC_UE_ROOT`, else `D:\Games\UE_5.8`. |
| `-Map <map>` | A map to open instead of the default. |
| `-NullRhi` | `-nullrhi` instead of `-RenderOffScreen`. |
| `-LogPath <file>` | Where the log goes (`-abslog`). Default `<project>\Saved\Logs\<Name>-Headless.log`, or `%TEMP%\MindAttic.Headless\<Name>-Headless.log` for an exe. Deleted first, so a stale ready line is never read. |
| `-Wait` / `-TimeoutSeconds <n>` | Wait for the ready line (default 300 s). Fails if the game exits first or the time runs out; the game is not killed on timeout. |
| `-StopAfterReady` | With `-Wait`: stop the game once ready (a start-up smoke test). |
| anything else | Passed to the game unchanged; a `-Key=value with spaces` is quoted for you. |

It always adds `--headless -RenderOffScreen|-nullrhi -unattended -nosplash -nosound -abslog=<log>`, prints the command line and the log path, and returns `[pscustomobject]@{ Process; LogPath; ReadyLine }`. The game is left running: stopping it is the caller's job.

To wait for the ready line yourself, match each log line against `(^|\])MINDATTIC_HEADLESS_READY(\s|$)`: UE puts its `[time][frame]` prefix in front of every line, and the message after it starts with the marker.

## Project layout

```text
Plugins/MindAtticShared/
  MindAtticShared.uplugin
  Source/MindAtticHeadless/                 runtime module (EarliestPossible, Core only)
    Public/MindAtticHeadless.h              FMindAtticHeadless
    Private/MindAtticHeadless.cpp           the rule, the engine flags, the ready line
tools/Start-Headless.ps1                    the launcher
tests/HostProject/                          test-only host project: enables the plugin as a game does
tests/Run-HostProjectTests.ps1              builds the host and checks the contract with real launches
```

## Testing

```powershell
.\tests\Run-HostProjectTests.ps1            # -NoBuild to skip the build, -Runs off,flag to pick runs
```

Builds `HostProjectEditor` with UE 5.8's `Build.bat`, then launches the host four times through `UnrealEditor.exe -game`, each quitting itself a few seconds after start-up:

| Run | Launched with | Checks |
|---|---|---|
| `off` | nothing | `IsActive()` false, no ready line, the plugin logs nothing and adds no flags, the normal window opens |
| `flag` | only `--headless` | `IsActive()` true, `OnReady` fired, exactly one `MINDATTIC_HEADLESS_READY HostProject` line, no window ever (sampled every 200 ms from launch), muted |
| `env` | only `MINDATTIC_HEADLESS=1` | the same as `flag` |
| `launcher` | `tools/Start-Headless.ps1 -Wait` | the same, plus `FApp::IsUnattended()` true and no audio device |

Each run also checks the switch rule (`--headless`, `-HEADLESS`, `-headlessly` is not it, `MINDATTIC_HEADLESS=0` is off) and the test override. Logs are `tests/HostProject/Saved/Logs/HostProject-<run>.log`. Build output stays out of git (`.gitignore`).

## Documentation

- [docs/USER_STORIES.md](docs/USER_STORIES.md): the ticket log.
- [AGENTS.md](AGENTS.md): agent instructions.

## License

MIT, see [LICENSE](LICENSE).

Part of [MindAttic](https://mindattic.com) — see more projects at [github.com/mindattic](https://github.com/mindattic). Sibling: [Unity.Shared](https://github.com/mindattic/Unity.Shared).
