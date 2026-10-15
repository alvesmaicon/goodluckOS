// The launcher icon from the player's own game: the title logo of Content/Minigames/TitleButtons.xnb on a sky
// gradient, 240x160 like the other app icons. XNB textures are LZX-compressed; MonoGame's decoder reads them.
//   mono SdvIcon.exe <TitleButtons.xnb> <icon.png>        the icon
//   mono SdvIcon.exe <TitleButtons.xnb> <out.png> dump     the whole texture, to find the logo
using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;

public static class SdvIcon
{
    const int W = 240, H = 160;
    static readonly int[] Logo = { 0, 0, 400, 187 };

    public static int Main(string[] args)
    {
        int w, h;
        byte[] rgba = ReadTexture(args[0], out w, out h);
        if (args.Length > 2 && args[2] == "dump") {
            WritePng(args[1], rgba, w, h);
            Console.WriteLine("{0}x{1}", w, h);
            return 0;
        }
        WritePng(args[1], Icon(rgba, w), W, H);
        return 0;
    }

    static byte[] ReadTexture(string path, out int width, out int height)
    {
        var file = new BinaryReader(File.OpenRead(path));
        if (new string(file.ReadChars(3)) != "XNB")
            throw new InvalidDataException("not an XNB file");
        file.ReadByte();
        file.ReadByte();
        byte flags = file.ReadByte();
        int size = file.ReadInt32();
        Stream data = file.BaseStream;
        if ((flags & 0x80) != 0) {
            int decompressed = file.ReadInt32();
            Type lzx = typeof(Microsoft.Xna.Framework.Game).Assembly.GetType("Microsoft.Xna.Framework.Utilities.LzxDecoderStream");
            data = (Stream)Activator.CreateInstance(lzx, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
                null, new object[] { file.BaseStream, decompressed, size - 14 }, null);
        }
        var r = new BinaryReader(data);
        int readers = Read7BitInt(r);
        for (int i = 0; i < readers; i++) {
            r.ReadString();
            r.ReadInt32();
        }
        Read7BitInt(r);
        Read7BitInt(r);
        if (r.ReadInt32() != 0)
            throw new InvalidDataException("not an RGBA texture");
        width = r.ReadInt32();
        height = r.ReadInt32();
        r.ReadInt32();
        return r.ReadBytes(r.ReadInt32());
    }

    static int Read7BitInt(BinaryReader r)
    {
        int value = 0, shift = 0;
        byte b;
        do {
            b = r.ReadByte();
            value |= (b & 0x7f) << shift;
            shift += 7;
        } while ((b & 0x80) != 0);
        return value;
    }

    // The logo scaled to 88% of the width (box filter) over the title screen's sky; the texture is premultiplied
    static byte[] Icon(byte[] tex, int texWidth)
    {
        var icon = new byte[W * H * 4];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                double t = (double)y / (H - 1);
                int o = (y * W + x) * 4;
                icon[o] = (byte)(64 + t * (126 - 64));
                icon[o + 1] = (byte)(120 + t * (186 - 120));
                icon[o + 2] = (byte)(222 + t * (242 - 222));
                icon[o + 3] = 255;
            }
        double scale = W * 0.88 / Logo[2];
        int lw = (int)(Logo[2] * scale), lh = (int)(Logo[3] * scale);
        int ox = (W - lw) / 2, oy = (H - lh) / 2;
        for (int y = 0; y < lh; y++)
            for (int x = 0; x < lw; x++) {
                double r = 0, g = 0, b = 0, a = 0;
                int n = 0;
                for (int sy = (int)(y / scale); sy < (int)((y + 1) / scale); sy++)
                    for (int sx = (int)(x / scale); sx < (int)((x + 1) / scale); sx++) {
                        int s = ((Logo[1] + sy) * texWidth + Logo[0] + sx) * 4;
                        r += tex[s];
                        g += tex[s + 1];
                        b += tex[s + 2];
                        a += tex[s + 3];
                        n++;
                    }
                if (n == 0)
                    continue;
                int o = ((oy + y) * W + ox + x) * 4;
                double k = 1 - a / n / 255;
                icon[o] = (byte)Math.Min(255, r / n + icon[o] * k);
                icon[o + 1] = (byte)Math.Min(255, g / n + icon[o + 1] * k);
                icon[o + 2] = (byte)Math.Min(255, b / n + icon[o + 2] * k);
            }
        return icon;
    }

    static void WritePng(string path, byte[] rgba, int w, int h)
    {
        var raw = new MemoryStream();
        for (int y = 0; y < h; y++) {
            raw.WriteByte(0);
            raw.Write(rgba, y * w * 4, w * 4);
        }
        var z = new MemoryStream();
        z.WriteByte(0x78);
        z.WriteByte(0x01);
        using (var d = new DeflateStream(z, CompressionMode.Compress, true))
            raw.WriteTo(d);
        WriteBE(z, Adler32(raw.ToArray()));
        var png = new MemoryStream();
        png.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, 0, 8);
        var ihdr = new MemoryStream();
        WriteBE(ihdr, (uint)w);
        WriteBE(ihdr, (uint)h);
        ihdr.Write(new byte[] { 8, 6, 0, 0, 0 }, 0, 5);
        Chunk(png, "IHDR", ihdr.ToArray());
        Chunk(png, "IDAT", z.ToArray());
        Chunk(png, "IEND", new byte[0]);
        File.WriteAllBytes(path, png.ToArray());
    }

    static void Chunk(Stream s, string type, byte[] data)
    {
        WriteBE(s, (uint)data.Length);
        var td = new byte[4 + data.Length];
        for (int i = 0; i < 4; i++)
            td[i] = (byte)type[i];
        Array.Copy(data, 0, td, 4, data.Length);
        s.Write(td, 0, td.Length);
        WriteBE(s, Crc32(td));
    }

    static void WriteBE(Stream s, uint v)
    {
        s.Write(new[] { (byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8), (byte)v }, 0, 4);
    }

    static uint Crc32(byte[] data)
    {
        uint c = 0xffffffff;
        foreach (byte b in data) {
            c ^= b;
            for (int k = 0; k < 8; k++)
                c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
        }
        return ~c;
    }

    static uint Adler32(byte[] data)
    {
        uint a = 1, b = 0;
        foreach (byte d in data) {
            a = (a + d) % 65521;
            b = (b + a) % 65521;
        }
        return (b << 16) | a;
    }
}
