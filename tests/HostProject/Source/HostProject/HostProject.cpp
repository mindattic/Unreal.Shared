// Test-only host for the MindAtticShared plugin (UNRE-T2). It uses the API exactly as a game would and logs one
// "HOSTPROJECT ..." line per check, so tools/Test-HostProject.ps1 can read the result from the log.
//   -HostProjectQuitAfter=<seconds>   quit that long after the engine is up (the test script passes it).

#include "CoreMinimal.h"
#include "Containers/Ticker.h"
#include "HAL/PlatformMisc.h"
#include "Misc/App.h"
#include "Misc/CommandLine.h"
#include "Misc/CoreDelegates.h"
#include "Misc/Parse.h"
#include "Modules/ModuleManager.h"
#include "MindAtticHeadless.h"

DEFINE_LOG_CATEGORY_STATIC(LogHostProject, Log, All);

namespace HostProject
{
	static bool GReadyFired = false;

	static void Check(const TCHAR* Name, bool bPass)
	{
		UE_LOG(LogHostProject, Display, TEXT("HOSTPROJECT %s %s"), bPass ? TEXT("PASS") : TEXT("FAIL"), Name);
	}

	/** The pure rule, independent of how this run was launched. */
	static void CheckRule()
	{
		Check(TEXT("rule: empty is off"), !FMindAtticHeadless::IsRequested(TEXT(""), TEXT("")));
		Check(TEXT("rule: other flags are off"), !FMindAtticHeadless::IsRequested(TEXT("x.uproject -game -headlessly -nullrhi"), TEXT("0")));
		Check(TEXT("rule: --headless"), FMindAtticHeadless::IsRequested(TEXT("x.uproject -game --headless"), TEXT("")));
		Check(TEXT("rule: -HEADLESS any case"), FMindAtticHeadless::IsRequested(TEXT("-log -HEADLESS"), TEXT("")));
		Check(TEXT("rule: MINDATTIC_HEADLESS=1"), FMindAtticHeadless::IsRequested(TEXT("-game"), TEXT("1")));
		Check(TEXT("rule: MINDATTIC_HEADLESS=0 is off"), !FMindAtticHeadless::IsRequested(TEXT("-game"), TEXT("0")));
	}

	static void CheckOverride()
	{
		const bool bResolved = FMindAtticHeadless::IsActive();
		FMindAtticHeadless::SetActiveOverride(!bResolved);
		const bool bFlipped = FMindAtticHeadless::IsActive() == !bResolved;
		FMindAtticHeadless::ClearActiveOverride();
		Check(TEXT("override flips and clears"), bFlipped && FMindAtticHeadless::IsActive() == bResolved);
	}

	/** Runs one tick after the engine is up, so after every OnFEngineLoopInitComplete handler (UE broadcasts a
	 *  multicast delegate last-bound first, so this module's handler runs before the plugin's). */
	static void CheckEngineUp()
	{
		const bool bActive = FMindAtticHeadless::IsActive();
		const bool bOffScreen = FParse::Param(FCommandLine::Get(), TEXT("RenderOffScreen"));
		const bool bNullRhi = FParse::Param(FCommandLine::Get(), TEXT("nullrhi"));
		// unattended is FApp::IsUnattended() (one cached answer in Core); the engine's own view of -nosound is in the
		// log ("Audio Device Manager not initializing"), not FApp::CanEverRenderAudio(), whose static is per module.
		UE_LOG(LogHostProject, Display,
			TEXT("HOSTPROJECT STATE active=%d readyFired=%d signalled=%d renderOffScreen=%d nullrhi=%d unattended=%d volume=%.2f supplied=[%s]"),
			bActive, GReadyFired, FMindAtticHeadless::HasSignalledReady(), bOffScreen, bNullRhi,
			FApp::IsUnattended(), FApp::GetVolumeMultiplier(), *FString::Join(FMindAtticHeadless::GetSuppliedEngineFlags(), TEXT(" ")));
		Check(TEXT("OnReady fired iff active"), GReadyFired == bActive);
		Check(TEXT("ready signalled iff active"), FMindAtticHeadless::HasSignalledReady() == bActive);
		if (bActive)
		{
			Check(TEXT("headless: -RenderOffScreen or -nullrhi on the command line"), bOffScreen || bNullRhi);
			Check(TEXT("headless: muted (volume multiplier 0)"), FApp::GetVolumeMultiplier() == 0.f);
		}
		else
		{
			Check(TEXT("off: no engine flags added"), FMindAtticHeadless::GetSuppliedEngineFlags().Num() == 0);
		}
		CheckRule();
		CheckOverride();

		float QuitAfter = -1.f;
		if (FParse::Value(FCommandLine::Get(), TEXT("HostProjectQuitAfter="), QuitAfter) && QuitAfter >= 0.f)
		{
			FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([](float)
			{
				UE_LOG(LogHostProject, Display, TEXT("HOSTPROJECT QUIT"));
				FPlatformMisc::RequestExit(false, TEXT("HostProject"));
				return false;
			}), QuitAfter);
		}
	}
}

class FHostProjectModule : public FDefaultGameModuleImpl
{
public:
	virtual void StartupModule() override
	{
		// How a game opts in to its own headless behaviour: bind OnReady (or check IsActive) in StartupModule.
		FMindAtticHeadless::OnReady().AddLambda([] { HostProject::GReadyFired = true; });
		FCoreDelegates::OnFEngineLoopInitComplete.AddLambda([]
		{
			FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([](float)
			{
				HostProject::CheckEngineUp();
				return false;
			}));
		});
	}
};

IMPLEMENT_PRIMARY_GAME_MODULE(FHostProjectModule, HostProject, "HostProject");
