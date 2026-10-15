// The save's XmlSerializers as a DLL, made from the player's own game. Without a C# compiler the console builds
// them at run time with Reflection.Emit: SaveGame's five took ~60 s to build and a save ~54 s to read (mostly JIT
// of the emitted code). This takes the mappings SaveGame's static constructor builds and has Mono write and
// compile C# serializers for them (needs mcs, so it runs on the PC).
//   mono SdvXmlGen.exe <out dir>      from the game folder; writes <out dir>/StardewValley.XmlSerializers.dll
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
		Type saveGame = Assembly.Load("StardewValley").GetType("StardewValley.SaveGame", true);
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
		CompilerParameters p = new CompilerParameters();
		p.OutputAssembly = Path.GetFullPath(Path.Combine(args[0], "StardewValley.XmlSerializers.dll"));
		p.GenerateInMemory = false;
		Assembly a = XmlSerializer.GenerateSerializer(types.ToArray(), mappings.ToArray(), p);
		Console.WriteLine(a == null ? "nothing generated" : p.OutputAssembly);
		return a == null ? 1 : 0;
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
