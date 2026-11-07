#pragma once

#include "CoreMinimal.h"
#include "Delegates/Delegate.h"

/** Fired once, when the game is up in a --headless run (never in a normal run). */
DECLARE_MULTICAST_DELEGATE(FOnMindAtticHeadlessReady);

/**
 * The --headless launch mode shared by every MindAttic Unreal game (UNRE-T2), for scripted and automated testing:
 * the real game, no window, driven and queried by a script.
 *
 * On when the command line has --headless or -headless (any case) or the environment has MINDATTIC_HEADLESS=1.
 * Off by default: with neither, this module does nothing at all.
 *
 * When on, the module (LoadingPhase EarliestPossible, before the splash screen and the RHI) adds the engine's own
 * flags the command line does not already have: -RenderOffScreen (skipped when -nullrhi is given), -unattended,
 * -nosplash and -nosound, and mutes FApp's volume multiplier. -RenderOffScreen and -nosplash take full effect (no
 * window ever opens); -unattended and -nosound come too late for the engine's own cached checks, so a launcher
 * (tools/Start-Headless.ps1) still passes all four on the real command line. Once the engine loop has finished initialising (the first map is loaded) it broadcasts
 * OnReady() and then writes exactly one log line whose message is "MINDATTIC_HEADLESS_READY <ProjectName>".
 *
 * Game-specific behaviour (skip the main menu, take scripted input) belongs in the game: check IsActive() or bind
 * OnReady() in the game module's StartupModule.
 */
class MINDATTICHEADLESS_API FMindAtticHeadless
{
public:
	/** The marker at the start of the one ready log message. Scripts wait for it. */
	static constexpr const TCHAR* ReadyMarker = TEXT("MINDATTIC_HEADLESS_READY");

	/** The environment variable that turns headless on when it is "1". */
	static constexpr const TCHAR* EnvironmentVariable = TEXT("MINDATTIC_HEADLESS");

	/** True in a --headless run. Resolved once from the command line and environment; SetActiveOverride wins. */
	static bool IsActive();

	/** Broadcast once, just before the ready log line, in a headless run. Bind in StartupModule. */
	static FOnMindAtticHeadlessReady& OnReady();

	/** True once OnReady has been broadcast and the ready line written. */
	static bool HasSignalledReady();

	/** The engine flags the module added to the command line this run (empty when off or all already given). */
	static const TArray<FString>& GetSuppliedEngineFlags();

	/** Tests: force IsActive() to a value. Does not add or remove engine flags; those are decided at startup. */
	static void SetActiveOverride(bool bActive);

	/** Tests: drop the override; IsActive() goes back to the resolved value. */
	static void ClearActiveOverride();

	/** The rule itself, without side effects: true if CommandLine has --headless/-headless or EnvironmentValue is "1". */
	static bool IsRequested(const TCHAR* CommandLine, const FString& EnvironmentValue);
};
