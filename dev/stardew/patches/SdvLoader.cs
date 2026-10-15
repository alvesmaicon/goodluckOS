// Starts the game in the root AppDomain (the only one where Mono uses AOT images) after StardewPatches.Early has put
// in place what must exist before Program.Main runs: the pregenerated save serializers. stardew.sh copies it into
// the game folder, so the AppDomain base is the game's, as with mono StardewValley.exe.
//   mono SdvLoader.exe [game args]      MONOGAME_PATCH names StardewPatches.dll
using System;
using System.Reflection;

public static class SdvLoader
{
	public static void Main(string[] args)
	{
		string patches = Environment.GetEnvironmentVariable("MONOGAME_PATCH");
		if (!string.IsNullOrEmpty(patches))
			Assembly.LoadFrom(patches).GetType("StardewPatches").GetMethod("Early").Invoke(null, null);
		Assembly.Load("StardewValley").EntryPoint.Invoke(null, new object[] { args });
	}
}
