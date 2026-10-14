// Johnny on Flame's StardewPatches (BSD, LICENSE.Patch.txt; JohnnyonFlame/MonoGame v3.6_streamed_audio 4aea06d2),
// built by dev/stardew/build.sh against the player's own game. goodluckOS additions are at the end.

using System;
using System.Reflection;
using System.Collections.Generic;
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
		new Harmony("com.github.johnnyonflame.StardewPatches").PatchAll(Assembly.GetExecutingAssembly());
	}

	private static float getScreenRatio()
	{
		float hratio = (float)Game1.game1.Window.ClientBounds.Height / 768f;
		float wratio = (float)Game1.game1.Window.ClientBounds.Width / 1366f;
		return (hratio < wratio) ? hratio : wratio;
	}

	[HarmonyPatch(typeof(Options))]
	[HarmonyPatch("uiScale", MethodType.Getter)]
	private class Options__get_desiredUIScale
	{
		// Fit UI to the screen.
		private static void Postfix(ref float __result)
		{

			__result *= getScreenRatio();
		}
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

	[HarmonyPatch(typeof(Options))]
	[HarmonyPatch("zoomLevel", MethodType.Getter)]
	private class Options__zoomLevel_getter
	{
		private static bool Prefix(ref float __result, ref Options __instance)
		{
			if (Game1.game1.takingMapScreenshot)
			{
				__result = __instance.baseZoomLevel * getScreenRatio();
				return false;
			}
			__result = __instance.baseZoomLevel * getScreenRatio() * Game1.game1.zoomModifier;
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
			if (GameRunner.instance.gameInstances.Count <= 1)
			{
				__instance.zoomModifier = 1f;
			}
			else
			{
				__instance.zoomModifier = 0.5f;
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

	// SDV_STATS=<seconds>: frames, updates, nursery/major collections and managed heap, to stdout
	private static class Stats
	{
		public static readonly double Period;
		static int frames, updates, gc0, gc1;
		static DateTime t0 = DateTime.Now;

		static Stats()
		{
			double.TryParse(Environment.GetEnvironmentVariable("SDV_STATS") ?? "0", out Period);
			gc0 = GC.CollectionCount(0);
			gc1 = GC.CollectionCount(1);
		}

		public static void Frame()
		{
			frames++;
			double dt = (DateTime.Now - t0).TotalSeconds;
			if (dt < Period)
				return;
			int c0 = GC.CollectionCount(0), c1 = GC.CollectionCount(1);
			Console.WriteLine("stats {0:HH:mm:ss} fps {1:F1} ups {2:F1} gc0 {3} gc1 {4} heap {5} KB at {6}", DateTime.Now,
				frames / dt, updates / dt, c0 - gc0, c1 - gc1, GC.GetTotalMemory(false) / 1024,
				Game1.currentLocation == null ? "-" : Game1.currentLocation.NameOrUniqueName);
			frames = updates = 0;
			gc0 = c0;
			gc1 = c1;
			t0 = DateTime.Now;
		}

		public static void Update()
		{
			updates++;
		}
	}

	[HarmonyPatch(typeof(GameRunner))]
	[HarmonyPatch("Draw")]
	private class GameRunner__Draw
	{
		private static void Postfix()
		{
			if (Stats.Period > 0)
				Stats.Frame();
		}
	}

	[HarmonyPatch(typeof(GameRunner))]
	[HarmonyPatch("Update")]
	private class GameRunner__Update
	{
		private static void Postfix()
		{
			if (Stats.Period > 0)
				Stats.Update();
		}
	}
}
