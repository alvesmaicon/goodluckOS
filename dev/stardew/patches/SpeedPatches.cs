// goodluckOS: CPU cuts for the A33 found by the F2 bench (dev/out/stardew/results). Each one does the same work with
// the same results, only less of it. SDV_SLOW=<name>,... (or all) leaves some out for A/B runs:
//   objects    farm debris (weeds, stones, twigs) whose update would do nothing are skipped
//   polls      net events of every location are only polled when something arrived
//   locations  the per-location loop of a single-player game, without the farmer enumerators
//   trees      one player bounding box per tick for all trees, not one per tree
//   sort       sprites sorted by a float key array instead of IComparable calls
//   ids        a save's readers made for one name table copy the first one's names instead of adding them again
//   bushes     NPC schedule paths find bushes in a tile map built once per search, not by scanning every bush
//   lz4        LZ4 .xnb files decoded by the port's native LZ4 in one go (installed before the game starts)
// SDV_SORTCHECK=1 also sorts each batch the game's way and reports any batch that comes out in another order.
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Reflection.Emit;
using System.Xml;
using System.Xml.Serialization;
using HarmonyLib;
using Microsoft.Xna.Framework;
using Netcode;
using StardewValley;
using StardewValley.Buildings;
using StardewValley.Locations;
using StardewValley.Network;
using StardewValley.TerrainFeatures;
using SObject = StardewValley.Object;

public static class SpeedPatches
{
	public static Harmony Harmony;
	static readonly string[] Names = { "objects", "polls", "locations", "trees", "sort", "ids", "bushes" };

	// After the first update, like the probes: patching a class runs its static constructor
	public static void Install()
	{
		if (Harmony == null)
			return;
		Harmony harmony = Harmony;
		Harmony = null;
		System.Diagnostics.Stopwatch w = System.Diagnostics.Stopwatch.StartNew();
		string slow = "," + (Environment.GetEnvironmentVariable("SDV_SLOW") ?? "") + ",";
		List<string> on = new List<string>();
		foreach (string name in Names) {
			if (slow == ",all," || slow.Contains("," + name + ","))
				continue;
			try {
				switch (name) {
				case "objects": Objects.Install(harmony); break;
				case "polls": Polls.Install(harmony); break;
				case "locations": Locations.Install(harmony); break;
				case "trees": Trees.Install(harmony); break;
				case "sort": Sort.Install(harmony); break;
				case "ids": Ids.Install(harmony); break;
				case "bushes": Bushes.Install(harmony); break;
				}
				on.Add(name);
			} catch (Exception e) {
				Console.WriteLine("speed: {0} not patched: {1}", name, (e.InnerException ?? e).Message);
			}
		}
		Console.WriteLine("speed: {0} in {1} ms", on.Count == 0 ? "none" : string.Join(",", on.ToArray()), w.ElapsedMilliseconds);
	}

	// Before Program.Main (StardewPatches.Early): what must be in place before the game loads its first content
	public static void InstallEarly()
	{
		string slow = "," + (Environment.GetEnvironmentVariable("SDV_SLOW") ?? "") + ",";
		if (slow == ",all," || slow.Contains(",lz4,"))
			return;
		try {
			Xnb.Install(new Harmony("goodluckos.speed.early"));
		} catch (Exception e) {
			Console.WriteLine("speed: lz4 not patched: {0}", (e.InnerException ?? e).Message);
		}
	}

	// Transpiler body: calls to methods matching `match` become calls to `to(method)`, a static method taking the
	// instance first; throws (and Harmony keeps the method as it was) when there are fewer than `min`
	static IEnumerable<CodeInstruction> Redirect(IEnumerable<CodeInstruction> code, Func<MethodInfo, MethodInfo> to, int min,
		string what)
	{
		List<CodeInstruction> list = new List<CodeInstruction>(code);
		int n = 0;
		foreach (CodeInstruction c in list) {
			MethodInfo m = c.operand as MethodInfo;
			MethodInfo target = m != null && (c.opcode == OpCodes.Call || c.opcode == OpCodes.Callvirt) ? to(m) : null;
			if (target == null)
				continue;
			c.opcode = OpCodes.Call;
			c.operand = target;
			n++;
		}
		if (n < min)
			throw new Exception(what + ": " + n + " calls found");
		return list;
	}

	static MethodInfo Own(Type type, string name)
	{
		return type.GetMethod(name, BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.Public);
	}

	// Object.updateWhenCurrentLocation for a plain Object with no held object, light, machine animation, shake or
	// harvest flag, and none of its special ids (artifact and seed spots, BC 56, text signs), returns having changed
	// nothing; on the farm that is about a thousand debris objects a tick, each paying string compares to find out
	static class Objects
	{
		static Func<SObject, bool> busy;

		public static void Install(Harmony harmony)
		{
			DynamicMethod dm = new DynamicMethod("ObjectBusy", typeof(bool), new[] { typeof(SObject) }, typeof(SObject), true);
			ILGenerator il = dm.GetILGenerator();
			Label yes = il.DefineLabel();
			foreach (string name in new[] { "_hasHeldObject", "_hasLightSource", "_machineAnimation" }) {
				FieldInfo f = AccessTools.Field(typeof(SObject), name);
				if (f == null)
					throw new MissingFieldException("Object", name);
				il.Emit(OpCodes.Ldarg_0);
				il.Emit(OpCodes.Ldfld, f);
				il.Emit(OpCodes.Brtrue, yes);
			}
			il.Emit(OpCodes.Ldc_I4_0);
			il.Emit(OpCodes.Ret);
			il.MarkLabel(yes);
			il.Emit(OpCodes.Ldc_I4_1);
			il.Emit(OpCodes.Ret);
			busy = (Func<SObject, bool>)dm.CreateDelegate(typeof(Func<SObject, bool>));
			harmony.Patch(AccessTools.Method(typeof(GameLocation), "UpdateWhenCurrentLocation"),
				transpiler: new HarmonyMethod(typeof(Objects), "Transpiler"));
		}

		static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> code)
		{
			MethodInfo update = Own(typeof(Objects), "Update");
			return Redirect(code, m => m.Name == "updateWhenCurrentLocation" && m.DeclaringType == typeof(SObject) ? update : null,
				1, "Object.updateWhenCurrentLocation");
		}

		static void Update(SObject o, GameTime time)
		{
			if (o.GetType() == typeof(SObject) && o.shakeTimer <= 0 && !o.readyForHarvest.Value && !busy(o)) {
				string id = o.QualifiedItemId, item = o.ItemId;
				char last = string.IsNullOrEmpty(id) ? '0' : id[id.Length - 1];
				// The special ids end in 0 ("(O)590"), t ("(O)SeedSpot") and 6 ("(BC)56"); "TextSign" has 8 letters
				if (last != '0' && last != 't' && last != '6' && (item == null || item.Length != 8))
					return;
			}
			o.updateWhenCurrentLocation(time);
		}
	}

	// GameLocation.updateEvenIfFarmerIsntHere polls four net events in each of the ~90 locations every tick, and with
	// nothing received a poll only builds an enumerator over an empty list; an empty character list only asks
	// Game1.shouldTimePass
	static class Polls
	{
		public static void Install(Harmony harmony)
		{
			HarmonyMethod polls = new HarmonyMethod(typeof(Polls), "Transpiler");
			harmony.Patch(AccessTools.Method(typeof(GameLocation), "updateEvenIfFarmerIsntHere"), transpiler: polls);
			harmony.Patch(AccessTools.Method(typeof(NetAudio), "Update"), transpiler: polls);
			harmony.Patch(AccessTools.Method(typeof(GameLocation), "updateCharacters"),
				transpiler: new HarmonyMethod(typeof(Polls), "NoCharacters"));
		}

		// e.Poll() becomes: if (e.incomingEvents.Count != 0) e.Poll(); inline, since a generic helper reading the private
		// list of a shared generic instance trips a Mono assertion
		static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> code, ILGenerator il)
		{
			List<CodeInstruction> list = new List<CodeInstruction>(code), result = new List<CodeInstruction>();
			int n = 0;
			for (int i = 0; i < list.Count; i++) {
				CodeInstruction c = list[i];
				MethodInfo m = c.operand as MethodInfo;
				Type e = m != null && c.opcode == OpCodes.Callvirt && m.Name == "Poll" && m.GetParameters().Length == 0 ?
					Event(m.DeclaringType) : null;
				if (e == null || i + 1 == list.Count) {
					result.Add(c);
					continue;
				}
				FieldInfo incoming = e.GetField("incomingEvents", BindingFlags.Instance | BindingFlags.NonPublic);
				Label call = il.DefineLabel(), after = il.DefineLabel();
				list[i + 1].labels.Add(after);
				CodeInstruction poll = new CodeInstruction(OpCodes.Callvirt, m);
				poll.labels.Add(call);
				CodeInstruction dup = new CodeInstruction(OpCodes.Dup);
				dup.labels.AddRange(c.labels);
				dup.blocks.AddRange(c.blocks);
				result.Add(dup);
				result.Add(new CodeInstruction(OpCodes.Ldfld, incoming));
				result.Add(new CodeInstruction(OpCodes.Callvirt, incoming.FieldType.GetProperty("Count").GetGetMethod()));
				result.Add(new CodeInstruction(OpCodes.Brtrue, call));
				result.Add(new CodeInstruction(OpCodes.Pop));
				result.Add(new CodeInstruction(OpCodes.Br, after));
				result.Add(poll);
				n++;
			}
			if (n == 0)
				throw new Exception("Poll: no calls found");
			return result;
		}

		static Type Event(Type t)
		{
			for (; t != null; t = t.BaseType)
				if (t.IsGenericType && t.GetGenericTypeDefinition() == typeof(AbstractNetEvent1<>))
					return t;
			return null;
		}

		// if (characters.Count == 0) return; in front of GameLocation.updateCharacters
		static IEnumerable<CodeInstruction> NoCharacters(IEnumerable<CodeInstruction> code, ILGenerator il)
		{
			List<CodeInstruction> list = new List<CodeInstruction>(code);
			Label start = il.DefineLabel();
			list[0].labels.Add(start);
			list.InsertRange(0, new[] {
				new CodeInstruction(OpCodes.Ldarg_0),
				new CodeInstruction(OpCodes.Ldfld, AccessTools.Field(typeof(GameLocation), "characters")),
				new CodeInstruction(OpCodes.Callvirt, AccessTools.PropertyGetter(typeof(NetCollection<NPC>), "Count")),
				new CodeInstruction(OpCodes.Brtrue, start),
				new CodeInstruction(OpCodes.Ret),
			});
			return list;
		}
	}

	// Game1._UpdateLocation runs for every location every tick and asks location.farmers.Any(), an enumerator over
	// the player and otherFarmers with a name compare. With no other farmers that is just "is the player there".
	// Game1.UpdateLocations reaches it through Utility.ForEachLocation, which allocates a closure and a delegate per
	// location (two of the ~180 allocations a tick at the farm)
	static class Locations
	{
		public static void Install(Harmony harmony)
		{
			harmony.Patch(AccessTools.Method(typeof(Game1), "_UpdateLocation"), new HarmonyMethod(typeof(Locations), "Prefix"));
			harmony.Patch(AccessTools.Method(typeof(Game1), "UpdateLocations"), new HarmonyMethod(typeof(Locations), "All"));
		}

		static bool All(GameTime time)
		{
			if (Game1.IsClient || Game1.otherFarmers.Count != 0)
				return true;
			Game1.loopingLocationCues.Update(Game1.currentLocation);
			GameLocation current = Game1.currentLocation;
			string name = current?.NameOrUniqueName;
			foreach (GameLocation location in Game1.locations) {
				GameLocation l = location.NameOrUniqueName == name && current != null ? current : location;
				Prefix(l, time);
				foreach (Building building in l.buildings)
					if (building.GetIndoorsType() == IndoorsType.Instanced) {
						GameLocation indoors = building.GetIndoors();
						if (indoors != null)
							Prefix(indoors, time);
					}
			}
			if (Game1.currentLocation.IsTemporary)
				Prefix(Game1.currentLocation, time);
			MineShaft.UpdateMines(time);
			VolcanoDungeon.UpdateLevels(time);
			return false;
		}

		static bool Prefix(GameLocation location, GameTime time)
		{
			if (Game1.otherFarmers.Count != 0)
				return true;
			GameLocation at = Game1.player.currentLocation;
			bool here = at != null && (at == location || location.Equals(at));
			if (here)
				location.UpdateWhenCurrentLocation(time);
			location.updateEvenIfFarmerIsntHere(time);
			if (location.wasInhabited != here) {
				location.wasInhabited = here;
				if (Game1.IsMasterGame)
					location.cleanupForVacancy();
			}
			return false;
		}
	}

	// Tree.tickUpdate asks for the player's bounding box once per grown tree (139 on the bench farm) to fade the
	// trees the player walks behind; it only changes when the player moves, between ticks
	static class Trees
	{
		static int tick = -1;
		static Character who;
		static Rectangle box;

		public static void Install(Harmony harmony)
		{
			harmony.Patch(AccessTools.Method(typeof(Tree), "tickUpdate"), transpiler: new HarmonyMethod(typeof(Trees), "Transpiler"));
		}

		static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> code)
		{
			MethodInfo cached = Own(typeof(Trees), "Box");
			return Redirect(code, m => m.Name == "GetBoundingBox" && m.GetParameters().Length == 0 &&
				typeof(Character).IsAssignableFrom(m.DeclaringType) ? cached : null, 1, "GetBoundingBox");
		}

		static Rectangle Box(Character c)
		{
			if (tick != Game1.ticks || !ReferenceEquals(c, who)) {
				box = c.GetBoundingBox();
				tick = Game1.ticks;
				who = c;
			}
			return box;
		}
	}

	// SpriteBatcher.DrawBatch sorts its items with Array.Sort over IComparable<SpriteBatchItem>, two calls per compare
	// (comparer, then CompareTo). Sorting the float keys with the items as values runs the same introsort on floats
	static class Sort
	{
		static float[] keys = new float[0];
		static Action<object[], float[], int, int> fill;
		static MethodInfo gameSort;
		static bool check;
		static int batches, differ, tied;

		public static void Install(Harmony harmony)
		{
			Assembly mg = typeof(Microsoft.Xna.Framework.Graphics.SpriteBatch).Assembly;
			Type item = mg.GetType("Microsoft.Xna.Framework.Graphics.SpriteBatchItem", true);
			// for (; i < end; i++) keys[i] = ((SpriteBatchItem)items[i]).SortKey;
			DynamicMethod dm = new DynamicMethod("SortKeys", null, new[] { typeof(object[]), typeof(float[]), typeof(int), typeof(int) },
				item, true);
			ILGenerator il = dm.GetILGenerator();
			Label test = il.DefineLabel(), body = il.DefineLabel();
			il.Emit(OpCodes.Br, test);
			il.MarkLabel(body);
			il.Emit(OpCodes.Ldarg_1);
			il.Emit(OpCodes.Ldarg_2);
			il.Emit(OpCodes.Ldarg_0);
			il.Emit(OpCodes.Ldarg_2);
			il.Emit(OpCodes.Ldelem_Ref);
			il.Emit(OpCodes.Castclass, item);
			il.Emit(OpCodes.Ldfld, item.GetField("SortKey"));
			il.Emit(OpCodes.Stelem_R4);
			il.Emit(OpCodes.Ldarg_2);
			il.Emit(OpCodes.Ldc_I4_1);
			il.Emit(OpCodes.Add);
			il.Emit(OpCodes.Starg_S, (byte)2);
			il.MarkLabel(test);
			il.Emit(OpCodes.Ldarg_2);
			il.Emit(OpCodes.Ldarg_3);
			il.Emit(OpCodes.Blt, body);
			il.Emit(OpCodes.Ret);
			fill = (Action<object[], float[], int, int>)dm.CreateDelegate(typeof(Action<object[], float[], int, int>));
			check = Environment.GetEnvironmentVariable("SDV_SORTCHECK") == "1";
			foreach (MethodInfo m in typeof(Array).GetMethods())
				if (m.Name == "Sort" && m.IsGenericMethodDefinition && m.GetGenericArguments().Length == 1 &&
						m.GetParameters().Length == 3 && m.GetParameters()[1].ParameterType == typeof(int))
					gameSort = m.MakeGenericMethod(item);
			harmony.Patch(AccessTools.Method(mg.GetType("Microsoft.Xna.Framework.Graphics.SpriteBatcher", true), "DrawBatch"),
				transpiler: new HarmonyMethod(typeof(Sort), "Transpiler"));
		}

		static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> code)
		{
			MethodInfo run = Own(typeof(Sort), "Run");
			return Redirect(code, m => m.Name == "Sort" && m.DeclaringType == typeof(Array) && m.IsGenericMethod &&
				m.GetParameters().Length == 3 ? run : null, 1, "Array.Sort");
		}

		static void Run(object[] items, int index, int length)
		{
			object[] expected = null;
			if (check) {
				expected = (object[])items.Clone();
				gameSort.Invoke(null, new object[] { expected, index, length });
			}
			// The same length as the items: introsort's depth limit comes from the array length
			if (keys.Length != items.Length)
				keys = new float[items.Length];
			fill(items, keys, index, index + length);
			Array.Sort(keys, items, index, length);
			if (check) {
				batches++;
				for (int i = index; i < index + length; i++)
					if (!ReferenceEquals(items[i], expected[i])) {
						differ++;
						break;
					}
				for (int i = index + 1; i < index + length; i++)
					if (keys[i] == keys[i - 1]) {
						tied++;
						break;
					}
				if (batches % 1000 == 0)
					Console.WriteLine("sortcheck: {0} batches ({1} with equal keys), {2} in another order", batches, tied, differ);
			}
		}
	}

	// Each SerializableDictionary entry of a save (every object and terrain feature) is read by a new generated reader,
	// and its Init adds the 1,471 names of the save's types to the XmlReader's name table again. A reader made on this
	// thread after the first one is a copy of the first, whose names are already that table's atoms; its Init only sets
	// the XmlReader and the events, unless the table, the encoding or the assembly differ
	static class Ids
	{
		static Type reader1;
		static FieldInfo r, events;
		static Func<object, object> clone;
		[ThreadStatic] static object first, made;
		[ThreadStatic] static XmlNameTable table;

		public static void Install(Harmony harmony)
		{
			Assembly generated = null;
			foreach (Assembly a in AppDomain.CurrentDomain.GetAssemblies())
				if (a.GetName().Name == "StardewValley.XmlSerializers")
					generated = a;
			if (generated == null)
				throw new Exception("no pregenerated serializers");
			reader1 = generated.GetType("Microsoft.Xml.Serialization.GeneratedAssembly.XmlSerializationReader1", true);
			Type xr = typeof(XmlSerializationReader);
			if ((bool)AccessTools.Field(xr, "checkDeserializeAdvances").GetValue(null))
				throw new Exception("checkDeserializeAdvances is on");
			r = AccessTools.Field(xr, "r");
			events = AccessTools.Field(xr, "events");
			clone = (Func<object, object>)Delegate.CreateDelegate(typeof(Func<object, object>),
				typeof(object).GetMethod("MemberwiseClone", BindingFlags.Instance | BindingFlags.NonPublic));
			harmony.Patch(AccessTools.Method(generated.GetType("Microsoft.Xml.Serialization.GeneratedAssembly.XmlSerializer1", true),
				"CreateReader"), new HarmonyMethod(typeof(Ids), "Create"));
			harmony.Patch(AccessTools.Method(xr, "Init", new[] { typeof(XmlReader), typeof(XmlDeserializationEvents), typeof(string),
				xr.Assembly.GetType("System.Xml.Serialization.TempAssembly", true) }),
				new HarmonyMethod(typeof(Ids), "Before"), new HarmonyMethod(typeof(Ids), "After"));
		}

		static bool Create(ref XmlSerializationReader __result)
		{
			if (first == null)
				return true;
			__result = (XmlSerializationReader)clone(first);
			made = __result;
			return false;
		}

		static bool Before(XmlSerializationReader __instance, XmlReader r, XmlDeserializationEvents events, string encodingStyle,
			object tempAssembly, out bool __state)
		{
			__state = !ReferenceEquals(__instance, made) || r.NameTable != table || encodingStyle != null || tempAssembly != null;
			made = null;
			if (!__state) {
				Ids.r.SetValue(__instance, r);
				Ids.events.SetValue(__instance, events);
			}
			return __state;
		}

		static void After(XmlSerializationReader __instance, XmlReader r, bool __state)
		{
			if (!__state || __instance.GetType() != reader1)
				return;
			first = clone(__instance);
			Ids.r.SetValue(first, null);
			table = r.NameTable;
		}
	}

	// PathFindController.isPositionImpassableForNPCSchedule asks getLargeTerrainFeatureAt for every tile it visits, and
	// that scans all the location's bushes; a search changes nothing, so while one runs, a tile -> bush map of its
	// location (the first bush of the list on each tile, as the scan finds) answers instead
	static class Bushes
	{
		[ThreadStatic] static int depth;
		[ThreadStatic] static GameLocation where;
		[ThreadStatic] static Dictionary<long, LargeTerrainFeature> at;

		public static void Install(Harmony harmony)
		{
			harmony.Patch(AccessTools.Method(typeof(StardewValley.Pathfinding.PathFindController), "findPathForNPCSchedules",
				new[] { typeof(Point), typeof(Point), typeof(GameLocation), typeof(int), typeof(Character) }),
				new HarmonyMethod(typeof(Bushes), "Enter"), finalizer: new HarmonyMethod(typeof(Bushes), "Leave"));
			harmony.Patch(AccessTools.Method(typeof(GameLocation), "getLargeTerrainFeatureAt"), new HarmonyMethod(typeof(Bushes), "Find"));
		}

		static void Enter()
		{
			depth++;
		}

		static Exception Leave(Exception __exception)
		{
			if (--depth == 0) {
				where = null;
				at = null;
			}
			return __exception;
		}

		static bool Find(GameLocation __instance, int tileX, int tileY, ref LargeTerrainFeature __result)
		{
			if (depth == 0)
				return true;
			if (where != __instance) {
				where = __instance;
				at = new Dictionary<long, LargeTerrainFeature>();
				foreach (LargeTerrainFeature f in __instance.largeTerrainFeatures) {
					Rectangle b = f.getBoundingBox();
					for (int tx = (b.Left - 32) / 64 - 1; tx <= (b.Right - 32) / 64 + 1; tx++)
						for (int ty = (b.Top - 32) / 64 - 1; ty <= (b.Bottom - 32) / 64 + 1; ty++) {
							long k = ((long)tx << 32) | (uint)ty;
							if (b.Contains(tx * 64 + 32, ty * 64 + 32) && !at.ContainsKey(k))
								at[k] = f;
						}
				}
			}
			at.TryGetValue(((long)tileX << 32) | (uint)tileY, out __result);
			return false;
		}
	}

	// build.sh game stores the .xnb files as LZ4, and MonoGame's managed LZ4 decoder copies a byte at a time through
	// its window: as slow as the LZX it replaced. The port's native LZ4 (liblwjgl_lz4, for the game's own use) decodes
	// the whole asset into memory instead, as MonoGame does with LZX; any other stream gets MonoGame's decoder
	static class Xnb
	{
		static ConstructorInfo managed;

		[System.Runtime.InteropServices.DllImport("liblwjgl_lz4")]
		static extern int LZ4_decompress_safe(byte[] src, byte[] dst, int compressedSize, int dstCapacity);

		public static void Install(Harmony harmony)
		{
			managed = typeof(Game).Assembly.GetType("Microsoft.Xna.Framework.Utilities.Lz4DecoderStream", true)
				.GetConstructor(new[] { typeof(System.IO.Stream), typeof(long) });
			harmony.Patch(AccessTools.Method(typeof(Microsoft.Xna.Framework.Content.ContentManager), "GetContentReaderFromXnb"),
				transpiler: new HarmonyMethod(typeof(Xnb), "Transpiler"));
		}

		static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> code)
		{
			List<CodeInstruction> list = new List<CodeInstruction>(code);
			int n = 0;
			foreach (CodeInstruction c in list)
				if (c.opcode == OpCodes.Newobj && Equals(c.operand, managed)) {
					c.opcode = OpCodes.Call;
					c.operand = Own(typeof(Xnb), "Open");
					n++;
				}
			if (n != 1)
				throw new Exception("GetContentReaderFromXnb: " + n + " LZ4 decoders found");
			return list;
		}

		// The stream sits right after the header, whose last four bytes are the decoded size
		static System.IO.Stream Open(System.IO.Stream s, long length)
		{
			if (s.CanSeek && s.Position >= 14) {
				long at = s.Position;
				byte[] size = new byte[4], src = new byte[s.Length - at];
				s.Position = at - 4;
				if (Fill(s, size) && Fill(s, src)) {
					byte[] dst = new byte[Math.Max(BitConverter.ToInt32(size, 0), 0)];
					if (LZ4_decompress_safe(src, dst, src.Length, dst.Length) == dst.Length)
						return new System.IO.MemoryStream(dst, false);
				}
				s.Position = at;
			}
			return (System.IO.Stream)managed.Invoke(new object[] { s, length });
		}

		static bool Fill(System.IO.Stream s, byte[] b)
		{
			int at = 0, got;
			while (at < b.Length && (got = s.Read(b, at, b.Length - at)) > 0)
				at += got;
			return at == b.Length;
		}
	}
}
