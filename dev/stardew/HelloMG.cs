// F0 check of the runtime: Mono + MonoGame + SDL/KMSDRM + gl4es + OpenAL + gamepad, without the game.
// D-pad/stick moves the square, A beeps, START or BACK quits; FPS and memory go to stdout every 5 s.
using System;
using System.IO;
using System.Linq;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Audio;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

class HelloMG : Game
{
    readonly GraphicsDeviceManager gdm;
    SpriteBatch batch;
    Texture2D pixel;
    SoundEffect beep;
    Vector2 pos = new Vector2(300, 220);
    GamePadState prev;
    int frames;
    DateTime t0 = DateTime.Now, start = DateTime.Now;
    readonly double maxSeconds;

    HelloMG()
    {
        var mode = GraphicsAdapter.DefaultAdapter.CurrentDisplayMode;
        gdm = new GraphicsDeviceManager(this) {
            PreferredBackBufferWidth = mode.Width, PreferredBackBufferHeight = mode.Height, IsFullScreen = true
        };
        double.TryParse(Environment.GetEnvironmentVariable("HELLO_SECONDS") ?? "0", out maxSeconds);
    }

    protected override void LoadContent()
    {
        batch = new SpriteBatch(GraphicsDevice);
        pixel = new Texture2D(GraphicsDevice, 1, 1);
        pixel.SetData(new[] { Color.White });
        var pcm = new byte[22050 / 5 * 2];
        for (int i = 0; i < pcm.Length / 2; i++) {
            var s = (short)(Math.Sin(2 * Math.PI * 440 * i / 22050.0) * 8000);
            pcm[2 * i] = (byte)s;
            pcm[2 * i + 1] = (byte)(s >> 8);
        }
        beep = new SoundEffect(pcm, 22050, AudioChannels.Mono);
        var pp = GraphicsDevice.PresentationParameters;
        Console.WriteLine("backbuffer {0}x{1}, pad: {2}", pp.BackBufferWidth, pp.BackBufferHeight,
                          GamePad.GetCapabilities(PlayerIndex.One).IsConnected);
    }

    protected override void Update(GameTime gameTime)
    {
        var p = GamePad.GetState(PlayerIndex.One);
        if (p.Buttons.Start == ButtonState.Pressed || p.Buttons.Back == ButtonState.Pressed ||
            Keyboard.GetState().IsKeyDown(Keys.Escape) ||
            (maxSeconds > 0 && (DateTime.Now - start).TotalSeconds > maxSeconds))
            Exit();
        pos += p.ThumbSticks.Left * new Vector2(4, -4);
        if (p.DPad.Left == ButtonState.Pressed) pos.X -= 4;
        if (p.DPad.Right == ButtonState.Pressed) pos.X += 4;
        if (p.DPad.Up == ButtonState.Pressed) pos.Y -= 4;
        if (p.DPad.Down == ButtonState.Pressed) pos.Y += 4;
        if (p.Buttons.A == ButtonState.Pressed && prev.Buttons.A == ButtonState.Released)
            beep.Play();
        if (p.Buttons != prev.Buttons)
            Console.WriteLine("buttons: {0}", p.Buttons);
        prev = p;
        base.Update(gameTime);
    }

    protected override void Draw(GameTime gameTime)
    {
        GraphicsDevice.Clear(Color.CornflowerBlue);
        batch.Begin(SpriteSortMode.Deferred, BlendState.AlphaBlend, SamplerState.PointClamp);
        batch.Draw(pixel, new Rectangle((int)pos.X, (int)pos.Y, 40, 40), Color.Orange);
        batch.End();
        frames++;
        var dt = (DateTime.Now - t0).TotalSeconds;
        if (dt >= 5) {
            var status = File.ReadAllLines("/proc/self/status");
            Console.WriteLine("fps {0:F1}, managed {1} KB, {2}", frames / dt, GC.GetTotalMemory(false) / 1024,
                              string.Join(", ", status.Where(l => l.StartsWith("VmRSS") || l.StartsWith("VmSwap"))
                                                      .Select(l => l.Replace("\t", "").Replace("  ", ""))));
            frames = 0;
            t0 = DateTime.Now;
        }
        base.Draw(gameTime);
    }

    static void Main()
    {
        using (var game = new HelloMG())
            game.Run();
        // The port's MonoGame keeps a foreground audio thread (FrameworkDispatcher.UpdateWork) alive
        Environment.Exit(0);
    }
}
