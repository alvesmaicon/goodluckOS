// The game's .xnb files are LZX-compressed, and MonoGame decodes LZX in managed code a bit at a time: on the A33 that
// was a good part of the title screen and of every save load. This rewrites each one as LZ4 (HC), which the port's
// MonoGame reads too and decodes several times faster, at about four times the size. Each file is decoded back with
// MonoGame's own LZ4 decoder and compared before it replaces the LZX one.
//   mono SdvXnb.exe <Content dir>      needs liblz4.so.1 and MonoGame.Framework.dll (MONO_PATH)
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

public static class SdvXnb
{
	[DllImport("liblz4.so.1")]
	static extern int LZ4_compress_HC(byte[] src, byte[] dst, int srcSize, int dstCapacity, int level);

	public static int Main(string[] args)
	{
		Assembly mg = typeof(Microsoft.Xna.Framework.Game).Assembly;
		Type lzx = mg.GetType("Microsoft.Xna.Framework.Utilities.LzxDecoderStream", true);
		Type lz4 = mg.GetType("Microsoft.Xna.Framework.Utilities.Lz4DecoderStream", true);
		long before = 0, after = 0;
		int n = 0;
		foreach (string path in Directory.GetFiles(args[0], "*.xnb", SearchOption.AllDirectories)) {
			byte[] xnb = File.ReadAllBytes(path);
			before += xnb.Length;
			if (xnb.Length < 14 || xnb[0] != 'X' || xnb[1] != 'N' || xnb[2] != 'B' || (xnb[5] & 0x80) == 0) {
				after += xnb.Length;
				continue;
			}
			int size = BitConverter.ToInt32(xnb, 10);
			byte[] raw = ReadAll((Stream)Activator.CreateInstance(lzx, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
				null, new object[] { new MemoryStream(xnb, 14, xnb.Length - 14), size, xnb.Length - 14 }, null), size);
			byte[] packed = new byte[size + size / 255 + 16];
			int length = LZ4_compress_HC(raw, packed, size, packed.Length, 9);
			if (length <= 0)
				throw new Exception(path + ": LZ4 failed");
			byte[] back = ReadAll((Stream)Activator.CreateInstance(lz4, new MemoryStream(packed, 0, length), long.MaxValue), size);
			for (int i = 0; i < size; i++)
				if (back[i] != raw[i])
					throw new Exception(path + ": LZ4 round trip differs at " + i);
			byte[] header = new byte[14];
			Array.Copy(xnb, header, 6);
			header[5] = (byte)(xnb[5] & ~0x80 | 0x40);
			BitConverter.GetBytes(14 + length).CopyTo(header, 6);
			BitConverter.GetBytes(size).CopyTo(header, 10);
			using (FileStream f = File.Create(path + ".tmp")) {
				f.Write(header, 0, 14);
				f.Write(packed, 0, length);
			}
			File.Delete(path);
			File.Move(path + ".tmp", path);
			after += 14 + length;
			n++;
		}
		Console.WriteLine("{0} .xnb files LZX -> LZ4, {1} MB -> {2} MB", n, before >> 20, after >> 20);
		return 0;
	}

	static byte[] ReadAll(Stream s, int size)
	{
		byte[] b = new byte[size];
		int at = 0, got;
		while (at < size && (got = s.Read(b, at, size - at)) > 0)
			at += got;
		if (at != size)
			throw new EndOfStreamException(at + " of " + size + " bytes");
		return b;
	}
}
