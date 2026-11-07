using UnrealBuildTool;

/// Test-only game module: calls the MindAtticHeadless API the way a game would (UNRE-T2).
public class HostProject : ModuleRules
{
	public HostProject(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PrivateDependencyModuleNames.AddRange(new[] { "Core", "CoreUObject", "Engine", "MindAtticHeadless" });
	}
}
