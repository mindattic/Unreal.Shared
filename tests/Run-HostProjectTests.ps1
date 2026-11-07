<#
.SYNOPSIS
  Build tests/HostProject and prove the MindAtticShared plugin's --headless contract with real launches (UNRE-T2).

.DESCRIPTION
  1. Builds HostProjectEditor (Win64 Development) with the engine's Build.bat (skip with -NoBuild).
  2. Launches the host four times through UnrealEditor.exe -game, each quitting itself a few seconds after start-up:
     off      no flag, no environment: not active, no ready line, no MindAttic log lines, a window opens.
     flag     only --headless (no engine flags at all): active, one ready line, no window ever, unattended, no sound.
     env      only MINDATTIC_HEADLESS=1: the same as flag.
     launcher tools/Start-Headless.ps1 -Wait: waits for the ready line; the same checks.
  Each run's log is Saved/Logs/HostProject-<run>.log under tests/HostProject. Exit code 0 only if every check passes.
  Heavy: one build and four engine launches. Run it on its own.
#>
param(
  [string]$EngineRoot = $(if ($env:MINDATTIC_UE_ROOT) { $env:MINDATTIC_UE_ROOT } else { 'D:\Games\UE_5.8' }),
  [switch]$NoBuild,
  [int]$TimeoutSeconds = 300,
  [string[]]$Runs = @('off', 'flag', 'env', 'launcher')
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$uproject = Join-Path $here 'HostProject\HostProject.uproject'
$logDir = Join-Path $here 'HostProject\Saved\Logs'
$editor = Join-Path $EngineRoot 'Engine\Binaries\Win64\UnrealEditor.exe'
$launcher = Join-Path $here '..\tools\Start-Headless.ps1'
$failures = New-Object System.Collections.Generic.List[string]

function Fail([string]$why) { $failures.Add($why); Write-Host "  FAIL $why" -ForegroundColor Red }
function Pass([string]$what) { Write-Host "  PASS $what" -ForegroundColor Green }

function Read-Shared([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return '' }
  $s = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite, Delete')
  try { return (New-Object IO.StreamReader($s)).ReadToEnd() } finally { $s.Dispose() }
}

# Waits for the process to exit, sampling whether it ever shows a top-level window (splash or game).
function Watch-Process($process, [string]$log) {
  $sawWindow = $false
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while (-not $process.HasExited) {
    $process.Refresh()
    if ($process.MainWindowHandle -ne [IntPtr]::Zero) { $sawWindow = $true }
    if ((Get-Date) -gt $deadline) {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      Fail "timed out after $TimeoutSeconds s (killed); see $log"
      break
    }
    Start-Sleep -Milliseconds 200
  }
  $process.WaitForExit()
  return $sawWindow
}

function Test-Log([string]$run, [string]$log, [bool]$expectActive, [bool]$sawWindow) {
  $lines = (Read-Shared $log) -split "`r?`n"
  $ready = @($lines | Where-Object { $_ -match '(^|\])MINDATTIC_HEADLESS_READY(\s|$)' })
  $state = $lines | Where-Object { $_ -match 'HOSTPROJECT STATE' } | Select-Object -First 1
  if (-not $state) { Fail "${run}: host never reported (no HOSTPROJECT STATE); see $log"; return }
  Write-Host "  $($state -replace '^.*HOSTPROJECT ', '')"
  foreach ($l in $lines | Where-Object { $_ -match 'HOSTPROJECT (PASS|FAIL) ' }) {
    $check = $l -replace '^.*HOSTPROJECT (PASS|FAIL) ', ''
    if ($l -match 'HOSTPROJECT FAIL ') { Fail "${run}: $check" } else { Pass "${run}: $check" }
  }
  if ($expectActive) {
    if ($state -match 'active=1') { Pass "${run}: IsActive() is true" } else { Fail "${run}: IsActive() is false" }
    if ($ready.Count -eq 1) { Pass "${run}: exactly one ready line: $($ready[0] -replace '^.*\]', '')" } else { Fail "${run}: $($ready.Count) ready lines, want 1" }
    if ($ready.Count -ge 1 -and $ready[0] -match 'MINDATTIC_HEADLESS_READY HostProject$') { Pass "${run}: ready line names the project" } elseif ($ready.Count) { Fail "${run}: ready line '$($ready[0])'" }
    if (-not $sawWindow) { Pass "${run}: no window ever opened" } else { Fail "${run}: a window opened" }
    $noAudio = [bool]($lines -match 'Audio Device Manager not initializing')
    if ($run -eq 'launcher') {
      # The launcher puts -unattended and -nosound on the real command line, where the engine reads them in time.
      if ($state -match 'unattended=1') { Pass "${run}: FApp::IsUnattended() is true" } else { Fail "${run}: FApp::IsUnattended() is false" }
      if ($noAudio) { Pass "${run}: no audio device (-nosound)" } else { Fail "${run}: an audio device was created" }
    } else {
      # The plugin alone: -unattended and -nosound arrive after the engine has read them (see the README).
      Write-Host "  info ${run}: plugin alone: FApp::IsUnattended()=$(if ($state -match 'unattended=1') { 'true' } else { 'false' }), audio device $(if ($noAudio) { 'skipped' } else { 'created (muted)' })"
    }
  } else {
    if ($state -match 'active=0') { Pass "${run}: IsActive() is false" } else { Fail "${run}: IsActive() is true" }
    if ($ready.Count -eq 0) { Pass "${run}: no ready line" } else { Fail "${run}: ready line in a normal run" }
    if (-not ($lines -match 'LogMindAtticHeadless')) { Pass "${run}: the plugin logged nothing" } else { Fail "${run}: the plugin logged in a normal run" }
    if ($sawWindow) { Pass "${run}: the normal window opened" } else { Fail "${run}: no window in a normal run" }
  }
}

function Start-Host([string]$run, [string[]]$extra) {
  $log = Join-Path $logDir "HostProject-$run.log"
  if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
  $argList = @("`"$uproject`"", '-game', '-Multiprocess', '-HostProjectQuitAfter=5', "-abslog=`"$log`"") + $extra
  return @{ Process = (Start-Process -FilePath $editor -ArgumentList $argList -PassThru); Log = $log }
}

if (-not $NoBuild) {
  Write-Host "Building HostProjectEditor ..."
  & (Join-Path $EngineRoot 'Engine\Build\BatchFiles\Build.bat') HostProjectEditor Win64 Development "-Project=$uproject" -WaitMutex -NoHotReloadFromIDE
  if ($LASTEXITCODE -ne 0) { throw "Build failed ($LASTEXITCODE)" }
}
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$savedEnv = $env:MINDATTIC_HEADLESS
Remove-Item Env:MINDATTIC_HEADLESS -ErrorAction SilentlyContinue

foreach ($run in ($Runs -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { # -File passes "a,b" as one string
  Write-Host "Run '$run':"
  switch ($run) {
    'off'  { $h = Start-Host 'off' @(); Test-Log 'off' $h.Log $false (Watch-Process $h.Process $h.Log) }
    'flag' { $h = Start-Host 'flag' @('--headless'); Test-Log 'flag' $h.Log $true (Watch-Process $h.Process $h.Log) }
    'env'  {
      $env:MINDATTIC_HEADLESS = '1'
      try { $h = Start-Host 'env' @() } finally { Remove-Item Env:MINDATTIC_HEADLESS -ErrorAction SilentlyContinue }
      Test-Log 'env' $h.Log $true (Watch-Process $h.Process $h.Log)
    }
    'launcher' {
      $log = Join-Path $logDir 'HostProject-launcher.log'
      $r = & $launcher -Project $uproject -EngineRoot $EngineRoot -LogPath $log -Wait -TimeoutSeconds $TimeoutSeconds -HostProjectQuitAfter=5
      if ($r.ReadyLine) { Pass "launcher: -Wait returned on the ready line" } else { Fail 'launcher: -Wait returned without a ready line' }
      Test-Log 'launcher' $log $true (Watch-Process $r.Process $log)
    }
    default { throw "Unknown run '$run'" }
  }
}
if ($null -ne $savedEnv) { $env:MINDATTIC_HEADLESS = $savedEnv }

if ($failures.Count) { Write-Host "$($failures.Count) check(s) failed." -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed.' -ForegroundColor Green
