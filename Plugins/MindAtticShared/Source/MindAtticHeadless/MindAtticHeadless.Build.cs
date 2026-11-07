using UnrealBuildTool;

/// The --headless launch mode shared by every MindAttic Unreal game (UNRE-T2). Loads at EarliestPossible, before the
/// splash screen and the RHI, so --headless can add the engine's own no-window flags itself. Depends on Core only.
public class MindAtticHeadless : ModuleRules
{
	public MindAtticHeadless(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.Add("Core");
	}
}
