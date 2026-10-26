// The save's XmlSerializers as a DLL, made from the player's own game. Without a C# compiler the console builds
// them at run time with Reflection.Emit: SaveGame's five took ~60 s to build and a save ~54 s to read (mostly JIT
// of the emitted code). This takes the mappings SaveGame's static constructor builds and has Mono write and
// compile C# serializers for them (needs mcs, so it runs on the PC). Also the serializers SaveSerializer builds one
// type at a time (key and value types of every SerializableDictionary, Options, StartupPreferences), listed in
// StardewValley.XmlSerializers.txt for StardewPatches.Early to put in SaveSerializer's cache. A generated assembly only
// takes the types of one assembly: those of others (Vector2, bool[]...) go in StardewValley.XmlSerializers.<assembly>.dll.
//   mono SdvXmlGen.exe <out dir>      from the game folder; writes <out dir>/StardewValley.XmlSerializers*.dll and .txt
using System;
using System.CodeDom.Compiler;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Xml.Serialization;

public static class SdvXmlGen
{
	const BindingFlags Any = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

	public static int Main(string[] args)
	{
		Assembly game = Assembly.Load("StardewValley");
		Type saveGame = game.GetType("StardewValley.SaveGame", true);
		RuntimeHelpers.RunClassConstructor(saveGame.TypeHandle);
		List<Type> types = new List<Type>();
		List<XmlMapping> mappings = new List<XmlMapping>();
		foreach (FieldInfo f in saveGame.GetFields(BindingFlags.Public | BindingFlags.Static)) {
			XmlSerializer s = f.GetValue(null) as XmlSerializer;
			if (s == null)
				continue;
			XmlMapping m = (XmlMapping)Get(s, "mapping");
			Type t = (Type)Get(Get(Get(Get(m, "Accessor"), "Mapping"), "TypeDesc"), "Type");
			Console.WriteLine("{0}: {1}", f.Name, t.FullName);
			types.Add(t);
			mappings.Add(m);
		}
		Dictionary<Assembly, List<string>> single = new Dictionary<Assembly, List<string>>();
		Dictionary<Assembly, List<Type>> others = new Dictionary<Assembly, List<Type>>();
		Dictionary<Assembly, List<XmlMapping>> otherMappings = new Dictionary<Assembly, List<XmlMapping>>();
		single[game] = new List<string>();
		foreach (Type t in SingleTypes(game, types)) {
			XmlMapping m;
			try {
				m = (XmlMapping)Get(new XmlSerializer(t), "mapping");
			} catch (Exception e) {
				Console.WriteLine("{0}: skipped, {1}", t.FullName, e.Message);
				continue;
			}
			Console.WriteLine("single: {0}", t.FullName);
			if (!single.ContainsKey(t.Assembly)) {
				single[t.Assembly] = new List<string>();
				others[t.Assembly] = new List<Type>();
				otherMappings[t.Assembly] = new List<XmlMapping>();
			}
			(t.Assembly == game ? types : others[t.Assembly]).Add(t);
			(t.Assembly == game ? mappings : otherMappings[t.Assembly]).Add(m);
			single[t.Assembly].Add(t.AssemblyQualifiedName);
		}
		int failed = Generate(args[0], "StardewValley.XmlSerializers", types, mappings, single[game]);
		foreach (Assembly a in others.Keys)
			failed += Generate(args[0], "StardewValley.XmlSerializers." + a.GetName().Name, others[a], otherMappings[a], single[a]);
		return failed;
	}

	static int Generate(string dir, string name, List<Type> types, List<XmlMapping> mappings, List<string> single)
	{
		File.WriteAllLines(Path.Combine(dir, name + ".txt"), single.ToArray());
		CompilerParameters p = new CompilerParameters();
		p.OutputAssembly = Path.GetFullPath(Path.Combine(dir, name + ".dll"));
		p.GenerateInMemory = false;
		Assembly a = XmlSerializer.GenerateSerializer(types.ToArray(), mappings.ToArray(), p);
		Console.WriteLine(a == null ? "nothing generated" : p.OutputAssembly);
		return a == null ? 1 : 0;
	}

	// The types SaveSerializer.GetSerializer makes plain XmlSerializers for: key and value types of SerializableDictionary
	// (found in every field and property type of the game), Options, StartupPreferences and Item (generic
	// SaveSerializer.Deserialize<T> calls). Besides the game's own types that is Vector2, Point and arrays of primitives
	// (Early puts them in SaveSerializer's cache, so their assembly does not matter); primitives and strings take a fast
	// path anyway.
	static IEnumerable<Type> SingleTypes(Assembly game, List<Type> roots)
	{
		Type dictionary = game.GetType("StardewValley.SerializableDictionary`2", true);
		HashSet<Type> seen = new HashSet<Type>(), found = new HashSet<Type>();
		found.Add(game.GetType("StardewValley.Options", true));
		found.Add(game.GetType("StardewValley.StartupPreferences", true));
		found.Add(game.GetType("StardewValley.Item", true));
		Type[] all;
		try {
			all = game.GetTypes();
		} catch (ReflectionTypeLoadException e) {
			all = Array.FindAll(e.Types, t => t != null);
		}
		foreach (Type t in all) {
			foreach (FieldInfo f in t.GetFields(Any | BindingFlags.Static | BindingFlags.DeclaredOnly))
				Visit(f.FieldType, dictionary, seen, found);
			foreach (PropertyInfo p in t.GetProperties(Any | BindingFlags.Static | BindingFlags.DeclaredOnly))
				Visit(p.PropertyType, dictionary, seen, found);
			Visit(t.BaseType, dictionary, seen, found);
		}
		List<Type> result = new List<Type>();
		foreach (Type t in found)
			if (Type.GetTypeCode(t) == TypeCode.Object && !t.ContainsGenericParameters && !roots.Contains(t) && !t.IsEnum)
				result.Add(t);
		result.Sort((a, b) => string.CompareOrdinal(a.FullName, b.FullName));
		return result;
	}

	static void Visit(Type t, Type dictionary, HashSet<Type> seen, HashSet<Type> found)
	{
		if (t == null || !seen.Add(t))
			return;
		if (t.IsArray || t.IsByRef || t.IsPointer)
			Visit(t.GetElementType(), dictionary, seen, found);
		if (t.IsGenericType) {
			Type[] a = t.GetGenericArguments();
			if (t.GetGenericTypeDefinition() == dictionary && !t.ContainsGenericParameters) {
				found.Add(a[0]);
				found.Add(a[1]);
			}
			foreach (Type x in a)
				Visit(x, dictionary, seen, found);
		}
		Visit(t.BaseType, dictionary, seen, found);
	}

	// Internal members of the referencesource serializer Mono ships (XmlMapping.Accessor.Mapping.TypeDesc.Type)
	static object Get(object o, string name)
	{
		PropertyInfo p = o.GetType().GetProperty(name, Any);
		if (p != null)
			return p.GetValue(o, null);
		for (Type t = o.GetType(); t != null; t = t.BaseType) {
			FieldInfo f = t.GetField(name, Any);
			if (f != null)
				return f.GetValue(o);
		}
		throw new MissingMemberException(o.GetType().FullName, name);
	}
}
