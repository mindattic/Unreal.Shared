#include "MindAtticHeadless.h"

#include "HAL/PlatformMisc.h"
#include "Misc/App.h"
#include "Misc/CommandLine.h"
#include "Misc/CoreDelegates.h"
#include "Misc/Parse.h"
#include "Modules/ModuleManager.h"

DEFINE_LOG_CATEGORY_STATIC(LogMindAtticHeadless, Log, All);

namespace MindAtticHeadless
{
	static TOptional<bool> GResolved;
	static TOptional<bool> GOverride;
	static bool GSignalledReady = false;
	static TArray<FString> GSuppliedFlags;

	static FString ReadEnvironment()
	{
		return FPlatformMisc::GetEnvironmentVariable(FMindAtticHeadless::EnvironmentVariable);
	}

	/** Adds the engine's headless flags the command line lacks. Runs at EarliestPossible (in FEngineLoop::AppInit),
	 *  which is in time for some and too late for others (verified on UE 5.8 with tests/HostProject):
	 *    -RenderOffScreen / -nosplash  take full effect: the splash (FPlatformSplash::Show), the RHI's swap chain and
	 *                                  Slate's windows all read FCommandLine after this, so no window ever opens.
	 *    -unattended                   too late for FApp::IsUnattended(), which caches its answer before plugins load;
	 *                                  only code that parses FCommandLine itself later sees it.
	 *    -nosound                      too late: the audio device manager is created at IniSystemReady, just before.
	 *                                  So the module also sets FApp's volume multiplier to 0: silent, but a device opens.
	 *  The real command line (tools/Start-Headless.ps1) is what makes -unattended and -nosound take full effect. */
	static void SupplyEngineFlags()
	{
		const TCHAR* Wanted[] = {
			FParse::Param(FCommandLine::Get(), TEXT("nullrhi")) ? nullptr : TEXT("RenderOffScreen"),
			TEXT("unattended"),
			TEXT("nosplash"),
			TEXT("nosound"),
		};
		for (const TCHAR* Flag : Wanted)
		{
			if (Flag && !FParse::Param(FCommandLine::Get(), Flag))
			{
				FCommandLine::Append(*FString::Printf(TEXT(" -%s"), Flag));
				GSuppliedFlags.Add(FString::Printf(TEXT("-%s"), Flag));
			}
		}
		// Silent even though -nosound came too late. Only the window-focus handler resets this, and there is no
		// window. (Not SetUnfocusedVolumeMultiplier: that writes GEngineIni, which a run can save to Saved/Config.)
		FApp::SetVolumeMultiplier(0.f);
	}

	static void SignalReady()
	{
		if (GSignalledReady)
		{
			return;
		}
		GSignalledReady = true;
		FMindAtticHeadless::OnReady().Broadcast();
		// No category, so the message right after UE's [time][frame] prefix starts with the marker.
		GLog->Log(NAME_None, ELogVerbosity::Log,
			FString::Printf(TEXT("%s %s"), FMindAtticHeadless::ReadyMarker, FApp::GetProjectName()));
		GLog->Flush();
	}
}

bool FMindAtticHeadless::IsRequested(const TCHAR* CommandLine, const FString& EnvironmentValue)
{
	if (EnvironmentValue.TrimStartAndEnd() == TEXT("1"))
	{
		return true;
	}
	const TCHAR* Stream = CommandLine ? CommandLine : TEXT("");
	FString Token;
	while (FParse::Token(Stream, Token, false))
	{
		if (Token.Equals(TEXT("--headless"), ESearchCase::IgnoreCase) || Token.Equals(TEXT("-headless"), ESearchCase::IgnoreCase))
		{
			return true;
		}
	}
	return false;
}

bool FMindAtticHeadless::IsActive()
{
	using namespace MindAtticHeadless;
	if (GOverride.IsSet())
	{
		return GOverride.GetValue();
	}
	if (!GResolved.IsSet())
	{
		GResolved = IsRequested(FCommandLine::IsInitialized() ? FCommandLine::Get() : nullptr, ReadEnvironment());
	}
	return GResolved.GetValue();
}

FOnMindAtticHeadlessReady& FMindAtticHeadless::OnReady()
{
	static FOnMindAtticHeadlessReady Delegate;
	return Delegate;
}

bool FMindAtticHeadless::HasSignalledReady()
{
	return MindAtticHeadless::GSignalledReady;
}

const TArray<FString>& FMindAtticHeadless::GetSuppliedEngineFlags()
{
	return MindAtticHeadless::GSuppliedFlags;
}

void FMindAtticHeadless::SetActiveOverride(bool bActive)
{
	MindAtticHeadless::GOverride = bActive;
}

void FMindAtticHeadless::ClearActiveOverride()
{
	MindAtticHeadless::GOverride.Reset();
}

class FMindAtticHeadlessModule : public IModuleInterface
{
public:
	virtual void StartupModule() override
	{
		if (!FMindAtticHeadless::IsActive())
		{
			return; // Off by default: nothing changes, nothing is logged.
		}
		MindAtticHeadless::SupplyEngineFlags();
		const TArray<FString>& Supplied = FMindAtticHeadless::GetSuppliedEngineFlags();
		UE_LOG(LogMindAtticHeadless, Display, TEXT("Headless on (%s); engine flags added: %s"),
			MindAtticHeadless::ReadEnvironment().TrimStartAndEnd() == TEXT("1") ? TEXT("MINDATTIC_HEADLESS=1") : TEXT("--headless"),
			Supplied.Num() ? *FString::Join(Supplied, TEXT(" ")) : TEXT("none (all already given)"));
		InitCompleteHandle = FCoreDelegates::OnFEngineLoopInitComplete.AddStatic(&MindAtticHeadless::SignalReady);
	}

	virtual void ShutdownModule() override
	{
		if (InitCompleteHandle.IsValid())
		{
			FCoreDelegates::OnFEngineLoopInitComplete.Remove(InitCompleteHandle);
		}
	}

private:
	FDelegateHandle InitCompleteHandle;
};

IMPLEMENT_MODULE(FMindAtticHeadlessModule, MindAtticHeadless)
