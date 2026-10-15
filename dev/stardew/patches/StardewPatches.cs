// Johnny on Flame's StardewPatches (BSD, LICENSE.Patch.txt; JohnnyonFlame/MonoGame v3.6_streamed_audio 4aea06d2),
// built by dev/stardew/build.sh against the player's own game. goodluckOS additions are at the end.

using System;
using System.Reflection;
using System.Collections.Generic;
using System.Diagnostics;
using HarmonyLib;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;
using Microsoft.Xna.Framework.Content;
using Microsoft.Xna.Framework.Audio;
using StardewValley;
using StardewValley.Menus;

[AttributeUsage(AttributeTargets.Class)]
public class ModEntryPointAttribute : Attribute
{
}

[ModEntryPoint]
public static class StardewPatches
{
	public static void Main()
	{
		Console.Out.WriteLine("Found StardewPatches, running...");
		Harmony harmony = new Harmony("com.github.johnnyonflame.StardewPatches");
		harmony.PatchAll(Assembly.GetExecutingAssembly());
		Probe.Harmony = harmony;
	}

	private static float getScreenRatio()
	{
		float hratio = (float)Game1.game1.Window.ClientBounds.Height / 768f;
		float wratio = (float)Game1.game1.Window.ClientBounds.Width / 1366f;
		return (hratio < wratio) ? hratio : wratio;
	}

	[HarmonyPatch(typeof(InputState))]
	[HarmonyPatch("SetMousePosition")]
	private class InputState__SetMousePosition
	{
		private static bool Prefix(int x, int y, ref InputState __instance)
		{
			// Mouse input is completely broken, we'll disable it here.
			if (!Game1.game1.IsMainInstance)
			{
				Traverse.Create(__instance).Field("_simulatedMousePosition").SetValue(new Point(x, y));
				return false;
			}
			Traverse traverse = Traverse.Create(__instance).Field("_currentMouseState");
			MouseState mouseState = (MouseState)traverse.GetValue();
			traverse.SetValue(new MouseState(x, y, mouseState.ScrollWheelValue, mouseState.LeftButton, mouseState.MiddleButton, mouseState.RightButton, mouseState.XButton1, mouseState.XButton2));
			return false;
		}
	}

	[HarmonyPatch(typeof(InputState))]
	[HarmonyPatch("UpdateStates")]
	private class InputState__UpdateStates
	{
		private static bool Prefix(ref InputState __instance)
		{
			// Mouse input is completely broken, we'll disable it here too
			Traverse traverse4 = Traverse.Create(__instance).Field("_currentKeyboardState");
			Traverse traverse2 = Traverse.Create(__instance).Field("_currentMouseState");
			Traverse traverse3 = Traverse.Create(__instance).Field("_currentGamepadState");
			traverse4.SetValue(Keyboard.GetState());
			if (Game1.playerOneIndex >= PlayerIndex.One)
			{
				traverse3.SetValue(PadState());
				return false;
			}
			if (traverse2.GetValue() == null)
			{
				traverse2.SetValue(default(MouseState));
			}
			traverse3.SetValue(default(GamePadState));
			return false;
		}
	}

	// Windows Compatibility-Mode build fix
	[HarmonyPatch(typeof(Options))]
	[HarmonyPatch("isCurrentlyWindowedBorderless")]
	private class Options__isCurrentlyWindowedBorderless
	{
		private static bool Prefix(ref bool __result, ref Options __instance)
		{
			__result = Game1.graphics.IsFullScreen && !Game1.graphics.HardwareModeSwitch;
			return false;
		}
	}

	// Windows Compatibility-Mode build fix
	[HarmonyPatch(typeof(Options))]
	[HarmonyPatch("isCurrentlyFullscreen")]
	private class Options__isCurrentlyFullscreen
	{
		private static bool Prefix(ref bool __result, ref Options __instance)
		{
			__result = Game1.graphics.IsFullScreen && Game1.graphics.HardwareModeSwitch;
			return false;
		}
	}

	// Windows Compatibility-Mode build fix
	[HarmonyPatch(typeof(Game1))]
	[HarmonyPatch("toggleFullscreen")]
	private class Game1__toggleFullscreen
	{
		private static bool Prefix()
		{
			if (Game1.options.windowedBorderlessFullscreen)
			{
				Game1.graphics.HardwareModeSwitch = false;
				Game1.graphics.IsFullScreen = true;
				Game1.graphics.ApplyChanges();
				Game1.graphics.PreferredBackBufferWidth = Program.gamePtr.Window.ClientBounds.Width;
				Game1.graphics.PreferredBackBufferHeight = Program.gamePtr.Window.ClientBounds.Height;
			}
			else
			{
				Game1.toggleNonBorderlessWindowedFullscreen();
			}
			GameRunner.instance.OnWindowSizeChange(null, null);
			return false;
		}
	}

	// Windows Compatibility-Mode build fix
	[HarmonyPatch(typeof(Game1))]
	[HarmonyPatch("toggleNonBorderlessWindowedFullscreen")]
	private class Game1__toggleNonBorderlessWindowedFullscreen
	{
		private static bool Prefix()
		{
			int preferredBackBufferWidth = Game1.options.preferredResolutionX;
			int preferredBackBufferHeight = Game1.options.preferredResolutionY;
			Game1.graphics.HardwareModeSwitch = (Game1.options.fullscreen && !Game1.options.windowedBorderlessFullscreen);
			if (!Game1.options.fullscreen && !Game1.options.windowedBorderlessFullscreen)
			{
				preferredBackBufferWidth = 1280;
				preferredBackBufferHeight = 720;
			}
			Game1.graphics.PreferredBackBufferWidth = preferredBackBufferWidth;
			Game1.graphics.PreferredBackBufferHeight = preferredBackBufferHeight;
			if (Game1.options.fullscreen != Game1.graphics.IsFullScreen)
			{
				Game1.graphics.ToggleFullScreen();
			}
			Game1.graphics.ApplyChanges();
			Game1.updateViewportForScreenSizeChange(true, Game1.graphics.PreferredBackBufferWidth, Game1.graphics.PreferredBackBufferHeight);
			GameRunner.instance.OnWindowSizeChange(null, null);
			return false;
		}
	}

	[HarmonyPatch(typeof(Game1))]
	[HarmonyPatch("SetWindowSize")]
	private class Game1__SetWindowSize
	{
		static int last_w = 0, last_h = 0;
		private static bool Prefix(int w, int h, Game1 __instance)
		{
			Microsoft.Xna.Framework.Rectangle oldBounds = new Microsoft.Xna.Framework.Rectangle(Game1.viewport.X, Game1.viewport.Y, Game1.viewport.Width, Game1.viewport.Height);
			Microsoft.Xna.Framework.Rectangle clientBounds = __instance.Window.ClientBounds;
			bool flag = false;
			if (!Game1.graphics.IsFullScreen && __instance.Window.AllowUserResizing)
			{
				Game1.graphics.PreferredBackBufferWidth = w;
				Game1.graphics.PreferredBackBufferHeight = h;
			}
			if (flag)
			{
				Microsoft.Xna.Framework.Rectangle clientBounds2 = __instance.Window.ClientBounds;
			}
			if (__instance.IsMainInstance && Game1.graphics.SynchronizeWithVerticalRetrace != Game1.options.vsyncEnabled)
			{
				Game1.graphics.SynchronizeWithVerticalRetrace = Game1.options.vsyncEnabled;
				Console.WriteLine("Vsync toggled: " + Game1.graphics.SynchronizeWithVerticalRetrace.ToString());
			}
			if (last_w != w || last_h != h)
			{
				Game1.graphics.ApplyChanges();
				last_w = w;
				last_h = h;
			}
			try
			{
				if (Game1.graphics.IsFullScreen)
				{
					__instance.localMultiplayerWindow = new Microsoft.Xna.Framework.Rectangle(0, 0, Game1.graphics.PreferredBackBufferWidth, Game1.graphics.PreferredBackBufferHeight);
				}
				else
				{
					__instance.localMultiplayerWindow = new Microsoft.Xna.Framework.Rectangle(0, 0, w, h);
				}
			}
			catch (Exception)
			{
			}
			Game1.defaultDeviceViewport = new Viewport(__instance.localMultiplayerWindow);
			List<Vector4> list = new List<Vector4>();
			if (GameRunner.instance.gameInstances.Count <= 1)
			{
				list.Add(new Vector4(0f, 0f, 1f, 1f));
			}
			else if (GameRunner.instance.gameInstances.Count == 2)
			{
				list.Add(new Vector4(0f, 0f, 0.5f, 1f));
				list.Add(new Vector4(0.5f, 0f, 0.5f, 1f));
			}
			else if (GameRunner.instance.gameInstances.Count == 3)
			{
				list.Add(new Vector4(0f, 0f, 1f, 0.5f));
				list.Add(new Vector4(0f, 0.5f, 0.5f, 0.5f));
				list.Add(new Vector4(0.5f, 0.5f, 0.5f, 0.5f));
			}
			else if (GameRunner.instance.gameInstances.Count == 4)
			{
				list.Add(new Vector4(0f, 0f, 0.5f, 0.5f));
				list.Add(new Vector4(0.5f, 0f, 0.5f, 0.5f));
				list.Add(new Vector4(0f, 0.5f, 0.5f, 0.5f));
				list.Add(new Vector4(0.5f, 0.5f, 0.5f, 0.5f));
			}
			// goodluckOS: the zoom and UI scale getters multiply by zoomModifier; scaling it here replaces JoF's
			// patches on those getters, which AOT code inlines past (and which ran on every call)
			if (GameRunner.instance.gameInstances.Count <= 1)
			{
				__instance.zoomModifier = getScreenRatio();
			}
			else
			{
				__instance.zoomModifier = 0.5f * getScreenRatio();
			}
			Vector4 vector = list[Game1.game1.instanceIndex];
			Vector2? vector2 = null;
			if (__instance.uiScreen != null)
			{
				vector2 = new Vector2?(new Vector2((float)__instance.uiScreen.Width, (float)__instance.uiScreen.Height));
			}
			__instance.localMultiplayerWindow.X = (int)((float)w * vector.X);
			__instance.localMultiplayerWindow.Y = (int)((float)h * vector.Y);
			__instance.localMultiplayerWindow.Width = (int)Math.Ceiling((double)((float)w * vector.Z));
			__instance.localMultiplayerWindow.Height = (int)Math.Ceiling((double)((float)h * vector.W));
			try
			{
				int width = (int)Math.Ceiling((double)((float)__instance.localMultiplayerWindow.Width * (1f / Game1.options.zoomLevel)));
				int height = (int)Math.Ceiling((double)((float)__instance.localMultiplayerWindow.Height * (1f / Game1.options.zoomLevel)));
				__instance.screen = new RenderTarget2D(Game1.graphics.GraphicsDevice, width, height, false, SurfaceFormat.Color, DepthFormat.None, 0, RenderTargetUsage.PreserveContents);
				__instance.screen.Name = "Screen";
				int width2 = (int)Math.Ceiling((double)((float)__instance.localMultiplayerWindow.Width / Game1.options.uiScale));
				int height2 = (int)Math.Ceiling((double)((float)__instance.localMultiplayerWindow.Height / Game1.options.uiScale));
				__instance.uiScreen = new RenderTarget2D(Game1.graphics.GraphicsDevice, width2, height2, false, SurfaceFormat.Color, DepthFormat.None, 0, RenderTargetUsage.PreserveContents);
				__instance.uiScreen.Name = "UI Screen";
			}
			catch (Exception)
			{
			}
			Game1.updateViewportForScreenSizeChange(false, __instance.localMultiplayerWindow.Width, __instance.localMultiplayerWindow.Height);
			if (vector2 == null || vector2.Value.X != (float)__instance.uiScreen.Width || vector2.Value.Y != (float)__instance.uiScreen.Height)
			{
				Game1.PushUIMode();
				if (Game1.textEntry != null)
				{
					Game1.textEntry.gameWindowSizeChanged(oldBounds, new Microsoft.Xna.Framework.Rectangle(Game1.viewport.X, Game1.viewport.Y, Game1.viewport.Width, Game1.viewport.Height));
				}
				foreach (IClickableMenu clickableMenu in Game1.onScreenMenus)
				{
					clickableMenu.gameWindowSizeChanged(oldBounds, new Microsoft.Xna.Framework.Rectangle(Game1.viewport.X, Game1.viewport.Y, Game1.viewport.Width, Game1.viewport.Height));
				}
				if (Game1.currentMinigame != null)
				{
					Game1.currentMinigame.changeScreenSize();
				}
				if (Game1.activeClickableMenu != null)
				{
					Game1.activeClickableMenu.gameWindowSizeChanged(oldBounds, new Microsoft.Xna.Framework.Rectangle(Game1.viewport.X, Game1.viewport.Y, Game1.viewport.Width, Game1.viewport.Height));
				}
				// As 1.6.15 does it: rebuild the game menu and hand the old page to the new one
				if (Game1.activeClickableMenu?.GetType() == typeof(GameMenu))
				{
					GameMenu oldMenu = Game1.activeClickableMenu as GameMenu;
					IClickableMenu oldPage = oldMenu.GetCurrentPage();
					GameMenu newMenu = new GameMenu(oldMenu.currentTab, -1, true);
					Game1.activeClickableMenu = newMenu;
					IClickableMenu page = newMenu.GetCurrentPage();
					if (page is CollectionsPage)
						(page as CollectionsPage).postWindowSizeChange(oldPage);
					else if (page is OptionsPage)
						(page as OptionsPage).postWindowSizeChange(oldPage);
					else if (page is SocialPage)
						(page as SocialPage).postWindowSizeChange(oldPage);
				}
				Game1.PopUIMode();
			}
			return false;
		}
	}

	[HarmonyPatch(typeof(Program))]
	[HarmonyPatch("handleException")]
	private class Program__handleException
	{
		private static bool Prefix(object sender, UnhandledExceptionEventArgs args)
		{
			Console.Out.WriteLine($"{((Exception)args.ExceptionObject).ToString()}");
			return false;
		}
	}

	[HarmonyPatch(typeof(LocalizedContentManager))]
	[HarmonyPatch("GetContentRoot")]
	private class LocalizedContentManager__GetContentRoot
	{
		private static bool Prefix(ref string __result)
		{
			ContentManager mgr = Game1.content;
			__result = mgr.RootDirectory;
			return false;
		}
	}

	// PlatformStop frees the streaming buffers of every instance; memory-resident sounds have none (null)
	// and crashed the audio thread. Deleting buffer name 0 is a no-op in OpenAL.
	[HarmonyPatch(typeof(SoundEffectInstance))]
	[HarmonyPatch("PlatformStop")]
	private class SoundEffectInstance__PlatformStop
	{
		private static void Prefix(SoundEffectInstance __instance)
		{
			Traverse buffers = Traverse.Create(__instance).Field("buffers");
			if (buffers.GetValue() == null)
				buffers.SetValue(new int[1]);
		}
	}

	// SDV_PAD_ANY=1 (bench): player one also takes the first other pad with input, e.g. padsim's uinput clone
	private static readonly bool padAny = Environment.GetEnvironmentVariable("SDV_PAD_ANY") == "1";

	private static GamePadState PadState()
	{
		GamePadState one = GamePad.GetState(Game1.playerOneIndex);
		if (!padAny || Active(one))
			return one;
		for (PlayerIndex i = PlayerIndex.One; i <= PlayerIndex.Four; i++) {
			GamePadState s = GamePad.GetState(i);
			if (i != Game1.playerOneIndex && Active(s))
				return s;
		}
		return one;
	}

	private static bool Active(GamePadState s)
	{
		return s.IsConnected && (s.Buttons != default(GamePadButtons) || s.DPad != default(GamePadDPad) ||
			s.ThumbSticks.Left != Vector2.Zero || s.ThumbSticks.Right != Vector2.Zero || s.Triggers.Left > 0 || s.Triggers.Right > 0);
	}

	// SDV_LIGHTING=<n>: pixels per lightmap texel times two; the game fixes 8 (finest), 16 or 32 are cheaper
	[HarmonyPatch(typeof(Options))]
	[HarmonyPatch("lightingQuality", MethodType.Getter)]
	private class Options__lightingQuality
	{
		private static readonly int quality = int.Parse(Environment.GetEnvironmentVariable("SDV_LIGHTING") ?? "0");

		private static bool Prefix(ref int __result)
		{
			if (quality <= 0)
				return true;
			__result = quality;
			return false;
		}
	}

	// SDV_STATS=<seconds>: frames, updates, their average ms, the rest of the time (mostly Present), nursery/major
	// collections and managed heap, to stdout, followed by the probes
	private static class Stats
	{
		public static readonly double Period;
		public static readonly bool On;
		public static bool Paused;
		static int frames, updates, gc0, gc1;
		static long drawTicks, updateTicks;
		static DateTime t0 = DateTime.Now;

		static Stats()
		{
			double.TryParse(Environment.GetEnvironmentVariable("SDV_STATS") ?? "0", out Period);
			On = Period > 0 || Bench.Slot != null;
			Reset();
		}

		public static void Frame(long ticks)
		{
			frames++;
			drawTicks += ticks;
			if (Period > 0 && !Paused && (DateTime.Now - t0).TotalSeconds >= Period) {
				Report("stats");
				Reset();
			}
		}

		public static void Update(long ticks)
		{
			updates++;
			updateTicks += ticks;
		}

		public static void Reset()
		{
			frames = updates = 0;
			drawTicks = updateTicks = 0;
			gc0 = GC.CollectionCount(0);
			gc1 = GC.CollectionCount(1);
			t0 = DateTime.Now;
			Probe.Reset();
		}

		public static void Report(string tag)
		{
			double dt = (DateTime.Now - t0).TotalSeconds;
			double ms = 1000.0 / Stopwatch.Frequency, draw = drawTicks * ms, update = updateTicks * ms;
			Console.WriteLine("{0} {1:HH:mm:ss} fps {2:F1} ups {3:F1} draw {4:F1} ms update {5:F1} ms rest {6:F0}% gc0 {7} gc1 {8} " +
				"heap {9} KB at {10}", tag, DateTime.Now, frames / dt, updates / dt, draw / Math.Max(frames, 1),
				update / Math.Max(updates, 1), 100 - (draw + update) / (dt * 10), GC.CollectionCount(0) - gc0,
				GC.CollectionCount(1) - gc1, GC.GetTotalMemory(false) / 1024,
				Game1.currentLocation == null ? "-" : Game1.currentLocation.NameOrUniqueName);
			Probe.Report(dt, frames, updates);
		}
	}

	[HarmonyPatch(typeof(GameRunner))]
	[HarmonyPatch("Draw")]
	private class GameRunner__Draw
	{
		private static void Prefix(out long __state)
		{
			Probe.Drawing = true;
			__state = Stopwatch.GetTimestamp();
		}

		private static void Postfix(long __state)
		{
			Probe.Drawing = false;
			if (Stats.On)
				Stats.Frame(Stopwatch.GetTimestamp() - __state);
		}
	}

	[HarmonyPatch(typeof(GameRunner))]
	[HarmonyPatch("Update")]
	private class GameRunner__Update
	{
		private static void Prefix(out long __state)
		{
			__state = Stopwatch.GetTimestamp();
		}

		private static void Postfix(long __state)
		{
			if (!Stats.On)
				return;
			Stats.Update(Stopwatch.GetTimestamp() - __state);
			Probe.Install();
			Bench.Tick();
		}
	}

	// SDV_PROBE=default|<Type.Method>,...: inclusive time in those methods (all overloads), as ms per second of
	// wall time and per update or frame (up to 40 entries); on by default with SDV_BENCH. Installed after the first
	// update: patching a class runs its static constructor, and Farm's needs the game's content
	private static class Probe
	{
		const string Default = "Game1.Update,InputState.UpdateStates,Game1.UpdateControlInput,Game1.UpdateGameClock," +
			"Game1.UpdateCharacters,Farmer.Update,Game1.UpdateLocations,Game1._UpdateLocation," +
			"GameLocation.UpdateWhenCurrentLocation,GameLocation.updateEvenIfFarmerIsntHere,NPC.update," +
			"Game1.UpdateViewPort,Game1.UpdateOther,Game1.updateWeather,Game1.updateMusic,Game1.updateRaindropPosition," +
			"Microsoft.Xna.Framework.Audio.AudioEngine.Update,GameStateQuery.Update," +
			"Game1._draw,Game1.DrawWorld,Game1.DrawLighting,GameLocation.draw,Layer.Draw,Game1.drawWeather," +
			"Game1.DrawLightmapOnScreen,Game1.drawHUD,Game1.DrawOverlays,Game1.renderScreenBuffer,SpriteBatch.End";
		public static Harmony Harmony;
		public static bool Drawing;
		static readonly List<string> names = new List<string>();
		static readonly long[] ticks = new long[40];
		static readonly int[] calls = new int[40];
		static readonly bool[] inDraw = new bool[40];

		public static void Install()
		{
			if (Harmony == null)
				return;
			Harmony harmony = Harmony;
			Harmony = null;
			string spec = Environment.GetEnvironmentVariable("SDV_PROBE") ?? (Bench.Slot != null ? "default" : "none");
			if (spec == "none")
				return;
			foreach (string item in (spec == "default" ? Default : spec).Split(',')) {
				int dot = item.LastIndexOf('.'), n = 0;
				Type type = dot > 0 ? FindType(item.Substring(0, dot)) : null;
				Type slot = typeof(Probe).GetNestedType("P" + names.Count, BindingFlags.NonPublic);
				if (type != null && slot != null)
					foreach (MethodInfo m in type.GetMethods(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public |
							BindingFlags.NonPublic | BindingFlags.DeclaredOnly))
						if (m.Name == item.Substring(dot + 1) && !m.IsAbstract && !m.ContainsGenericParameters) {
							try {
								harmony.Patch(m, new HarmonyMethod(slot.GetMethod("Before", BindingFlags.Static | BindingFlags.NonPublic)),
									new HarmonyMethod(slot.GetMethod("After", BindingFlags.Static | BindingFlags.NonPublic)));
								n++;
							} catch (Exception e) {
								Console.WriteLine("probe: {0} not patched: {1}", item, (e.InnerException ?? e).Message);
							}
						}
				if (n > 0)
					names.Add(item);
				else
					Console.WriteLine("probe: no method {0}", item);
			}
			Console.WriteLine("probe: {0} methods", names.Count);
		}

		static Type FindType(string name)
		{
			foreach (Assembly a in new[] { typeof(Game1).Assembly, typeof(Game).Assembly, typeof(xTile.Layers.Layer).Assembly })
				foreach (Type t in a.GetTypes())
					if (t.FullName == name || t.Name == name)
						return t;
			return null;
		}

		// One class per probe (Harmony shares __state within a class): a constant index costs far less than
		// __originalMethod, which resolves the method from its handle on every call
		class P0 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(0, __state); } }
		class P1 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(1, __state); } }
		class P2 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(2, __state); } }
		class P3 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(3, __state); } }
		class P4 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(4, __state); } }
		class P5 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(5, __state); } }
		class P6 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(6, __state); } }
		class P7 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(7, __state); } }
		class P8 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(8, __state); } }
		class P9 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(9, __state); } }
		class P10 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(10, __state); } }
		class P11 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(11, __state); } }
		class P12 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(12, __state); } }
		class P13 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(13, __state); } }
		class P14 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(14, __state); } }
		class P15 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(15, __state); } }
		class P16 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(16, __state); } }
		class P17 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(17, __state); } }
		class P18 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(18, __state); } }
		class P19 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(19, __state); } }
		class P20 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(20, __state); } }
		class P21 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(21, __state); } }
		class P22 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(22, __state); } }
		class P23 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(23, __state); } }
		class P24 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(24, __state); } }
		class P25 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(25, __state); } }
		class P26 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(26, __state); } }
		class P27 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(27, __state); } }
		class P28 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(28, __state); } }
		class P29 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(29, __state); } }
		class P30 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(30, __state); } }
		class P31 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(31, __state); } }
		class P32 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(32, __state); } }
		class P33 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(33, __state); } }
		class P34 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(34, __state); } }
		class P35 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(35, __state); } }
		class P36 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(36, __state); } }
		class P37 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(37, __state); } }
		class P38 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(38, __state); } }
		class P39 { static void Before(out long __state) { __state = Stopwatch.GetTimestamp(); } static void After(long __state) { Add(39, __state); } }

		static void Add(int i, long t0)
		{
			ticks[i] += Stopwatch.GetTimestamp() - t0;
			calls[i]++;
			inDraw[i] |= Drawing;
		}

		public static void Reset()
		{
			Array.Clear(ticks, 0, ticks.Length);
			Array.Clear(calls, 0, calls.Length);
		}

		public static void Report(double seconds, int frames, int updates)
		{
			double ms = 1000.0 / Stopwatch.Frequency;
			for (int i = 0; i < names.Count; i++) {
				int per = Math.Max(inDraw[i] ? frames : updates, 1);
				Console.WriteLine("probe {0} {1:F1} ms/s {2:F2} ms/{3} {4:F1} calls", names[i], ticks[i] * ms / seconds,
					ticks[i] * ms / per, inDraw[i] ? "frame" : "update", (double)calls[i] / per);
			}
		}
	}

	// SDV_BENCH=<save folder>[,<warm-up s>,<measured s>]: from the title, load that save, warp to the farmhouse
	// porch and stand still, then print one "bench" line (stats columns), the probes and the peak RSS, and quit
	// the way the game does.
	// SDV_ZOOM=<zoom> sets the in-game zoom after loading (1 = the menu's 100%)
	private static class Bench
	{
		public static readonly string Slot;
		static readonly double warmup = 20, measure = 60;
		static int step;
		static DateTime t = DateTime.Now, shown;

		static Bench()
		{
			string[] v = (Environment.GetEnvironmentVariable("SDV_BENCH") ?? "").Split(',');
			if (v[0] == "")
				return;
			Slot = v[0];
			if (v.Length == 3) {
				double.TryParse(v[1], out warmup);
				double.TryParse(v[2], out measure);
			}
		}

		static double Uptime()
		{
			return (DateTime.Now - Process.GetCurrentProcess().StartTime).TotalSeconds;
		}

		static void Log(string what)
		{
			Console.WriteLine("bench {0:HH:mm:ss} {1}", DateTime.Now, what);
		}

		public static void Tick()
		{
			if (Slot == null)
				return;
			double s = (DateTime.Now - t).TotalSeconds;
			bool settled = !Game1.globalFade && Game1.locationRequest == null;
			if ((step == 1 || step == 2) && (DateTime.Now - shown).TotalSeconds >= 10) {
				shown = DateTime.Now;
				Log(string.Format("waiting: step {0} mode {1} loader {2} at {3} fade {4} request {5} menu {6}", step,
					Game1.gameMode, Game1.currentLoader != null, Game1.currentLocation?.NameOrUniqueName, Game1.globalFade,
					Game1.locationRequest != null, Game1.activeClickableMenu?.GetType().Name));
			}
			switch (step) {
			case 0:
				if (Game1.gameMode != Game1.titleScreenGameMode || !(Game1.activeClickableMenu is TitleMenu))
					t = DateTime.Now;
				else if (s > 3) {
					Log(string.Format("title after {0:F0} s, loading {1}", Uptime(), Slot));
					Stats.Paused = true;
					SaveGame.Load(Slot);
					Game1.exitActiveMenu();
					step = 1;
				}
				break;
			case 1:
				if (Game1.gameMode == Game1.playingGameMode && Game1.currentLocation != null && settled) {
					Point door = Game1.getFarm().GetMainFarmHouseEntry();
					float zoom;
					if (float.TryParse(Environment.GetEnvironmentVariable("SDV_ZOOM"), System.Globalization.NumberStyles.Float,
							System.Globalization.CultureInfo.InvariantCulture, out zoom))
						Game1.options.desiredBaseZoomLevel = zoom;
					Log(string.Format("loaded after {0:F0} s, warp to Farm {1},{2}", Uptime(), door.X, door.Y));
					Game1.warpFarmer("Farm", door.X, door.Y, 2);
					step = 2;
				}
				break;
			case 2:
				if (Game1.currentLocation is Farm && settled) {
					t = DateTime.Now;
					step = 3;
				}
				break;
			case 3:
				if (s >= warmup) {
					Log(string.Format("measuring {0} s: zoom {1:F3}, viewport {2}x{3}, lightmap {4}x{5}", measure,
						Game1.options.zoomLevel, Game1.viewport.Width, Game1.viewport.Height, Game1.lightmap?.Width, Game1.lightmap?.Height));
					Stats.Reset();
					t = DateTime.Now;
					step = 4;
				}
				break;
			case 4:
				if (s >= measure) {
					Stats.Report("bench");
					foreach (string line in System.IO.File.ReadAllLines("/proc/self/status"))
						if (line.StartsWith("VmHWM") || line.StartsWith("VmRSS"))
							Console.WriteLine("bench {0}", line.Replace("\t", " "));
					Console.Out.Flush();
					Game1.game1.Exit();
					step = 5;
				}
				break;
			}
		}
	}
}
