<#
.SYNOPSIS
  Launch a MindAttic Unreal game headless (no window, no sound, no dialogs) for scripted/automated testing (UNRE-T2).

.DESCRIPTION
  Runs either a built game exe (-Exe) or an editor "-game" run of a .uproject (-Project) with --headless plus the
  engine's own flags: -RenderOffScreen (or -nullrhi with -NullRhi), -unattended, -nosplash, -nosound. A game that
  enables the MindAtticShared plugin adds those flags itself from --headless; this script passes them anyway, so it
  also works for a game that has not adopted the plugin yet (it just never prints the ready line).

  The log goes to -LogPath (default: <project>/Saved/Logs/<Name>-Headless.log, or %TEMP%\MindAttic.Headless\ for an
  exe) via -abslog, and its path is printed. With -Wait the script waits until the log has the
  MINDATTIC_HEADLESS_READY line, failing on -TimeoutSeconds or if the game exits first. The game is left running
  either way: the returned object's Process is the caller's to drive and stop (-StopAfterReady stops it for you).

  Anything after the named parameters is passed to the game unchanged.

.EXAMPLE
  ..\Unreal.Shared\tools\Start-Headless.ps1 -Project .\Cpp\SpaceGod.uproject -Wait
.EXAMPLE
  $run = ..\Unreal.Shared\tools\Start-Headless.ps1 -Exe .\Build\Windows\MyGame.exe -Wait -TimeoutSeconds 120 -ExecCmds="stat fps"
  # ... drive / query the game ...
  Stop-Process -Id $run.Process.Id
.EXAMPLE
  .\tools\Start-Headless.ps1 -Project .\tests\HostProject\HostProject.uproject -NullRhi -Wait -StopAfterReady
#>
[CmdletBinding(DefaultParameterSetName = 'Project')]
param(
  # A .uproject: run through the engine's UnrealEditor.exe with -game (needs the editor target built).
  [Parameter(ParameterSetName = 'Project', Mandatory, Position = 0)] [string]$Project,
  # A built (packaged or staged) game executable.
  [Parameter(ParameterSetName = 'Exe', Mandatory)] [string]$Exe,
  # Engine root for -Project runs. Default: $env:MINDATTIC_UE_ROOT, else D:\Games\UE_5.8.
  [string]$EngineRoot = $(if ($env:MINDATTIC_UE_ROOT) { $env:MINDATTIC_UE_ROOT } else { 'D:\Games\UE_5.8' }),
  # Optional map to open (e.g. /Game/Maps/Main); default: the project's GameDefaultMap.
  [string]$Map,
  # -nullrhi instead of -RenderOffScreen: no GPU work at all (no frames to read back), cheapest.
  [switch]$NullRhi,
  # Where the log goes. Default described above.
  [string]$LogPath,
  # Wait for the MINDATTIC_HEADLESS_READY line.
  [switch]$Wait,
  [int]$TimeoutSeconds = 300,
  # With -Wait: stop the game once it is ready (a smoke test of start-up).
  [switch]$StopAfterReady,
  # Everything else goes to the game unchanged.
  [Parameter(ValueFromRemainingArguments)] [string[]]$PassThru
)

$ErrorActionPreference = 'Stop'
$ReadyPattern = '(^|\])MINDATTIC_HEADLESS_READY(\s|$)'

$engineFlags = @($(if ($NullRhi) { '-nullrhi' } else { '-RenderOffScreen' }), '-unattended', '-nosplash', '-nosound')

if ($PSCmdlet.ParameterSetName -eq 'Project') {
  $projectFile = (Resolve-Path -LiteralPath $Project).Path
  if ([IO.Path]::GetExtension($projectFile) -ne '.uproject') { throw "-Project wants a .uproject, got $projectFile" }
  $name = [IO.Path]::GetFileNameWithoutExtension($projectFile)
  $exePath = Join-Path $EngineRoot 'Engine\Binaries\Win64\UnrealEditor.exe'
  if (-not (Test-Path -LiteralPath $exePath)) { throw "No UnrealEditor.exe under -EngineRoot $EngineRoot" }
  if (-not $LogPath) { $LogPath = Join-Path (Split-Path $projectFile) "Saved\Logs\$name-Headless.log" }
  # -Multiprocess: the editor binaries skip their start-up "UBT -Mode=ValidatePlatforms", which otherwise waits
  # behind any UE build running on the machine (SpaceGod's tools/play.ps1 does the same).
  $gameArgs = @("`"$projectFile`"") + $(if ($Map) { @($Map) } else { @() }) + @('-game', '-Multiprocess')
} else {
  $exePath = (Resolve-Path -LiteralPath $Exe).Path
  $name = [IO.Path]::GetFileNameWithoutExtension($exePath)
  if (-not $LogPath) { $LogPath = Join-Path ([IO.Path]::GetTempPath()) "MindAttic.Headless\$name-Headless.log" }
  $gameArgs = $(if ($Map) { @($Map) } else { @() })
}

$LogPath = [IO.Path]::GetFullPath($LogPath)
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force } # never read a stale ready line

$gameArgs += @('--headless') + $engineFlags + @("-abslog=`"$LogPath`"")
foreach ($arg in $PassThru) {
  # Start-Process joins arguments with spaces, so quote a value that has one: -ExecCmds=stat fps -> -ExecCmds="stat fps".
  if ($arg -match '\s' -and $arg -notmatch '"') {
    $arg = if ($arg -match '^(-[^=\s]+=)(.*)$') { "$($Matches[1])`"$($Matches[2])`"" } else { "`"$arg`"" }
  }
  $gameArgs += $arg
}

Write-Host "Start-Headless: $exePath $($gameArgs -join ' ')"
Write-Host "Start-Headless: log $LogPath"
$process = Start-Process -FilePath $exePath -ArgumentList $gameArgs -PassThru

$ready = $null
if ($Wait) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while (-not $ready) {
    if (Test-Path -LiteralPath $LogPath) {
      # UE keeps the log open for writing; read it shared.
      $stream = [IO.File]::Open($LogPath, 'Open', 'Read', 'ReadWrite, Delete')
      try { $text = (New-Object IO.StreamReader($stream)).ReadToEnd() } finally { $stream.Dispose() }
      $ready = ($text -split "`r?`n") | Where-Object { $_ -match $ReadyPattern } | Select-Object -First 1
    }
    if ($ready) { break }
    if ($process.HasExited) { throw "Start-Headless: $name exited (code $($process.ExitCode)) before MINDATTIC_HEADLESS_READY; see $LogPath" }
    if ((Get-Date) -gt $deadline) { throw "Start-Headless: no MINDATTIC_HEADLESS_READY within $TimeoutSeconds s (game still running, pid $($process.Id)); see $LogPath" }
    Start-Sleep -Milliseconds 500
  }
  Write-Host "Start-Headless: ready: $ready"
  if ($StopAfterReady) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    $process.WaitForExit()
  }
}

[pscustomobject]@{ Process = $process; LogPath = $LogPath; ReadyLine = $ready }
