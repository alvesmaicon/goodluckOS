// F0 check of the runtime: Mono + MonoGame + SDL/KMSDRM + gl4es + OpenAL + gamepad, without the game.
// It beeps once after 1 s; D-pad/stick moves the square, A beeps, START or BACK quits; FPS and memory go to stdout every 5 s.
// The beep is its own instance: the port's MonoGame crashes when its pool stops a memory-resident sound.
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
    SoundEffectInstance beepInstance;
    SoundState lastBeepState;
    bool startBeep;
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
        var pcm = new byte[22050 * 2 / 2];
        for (int i = 0; i < pcm.Length / 2; i++) {
            var s = (short)(Math.Sin(2 * Math.PI * 440 * i / 22050.0) * 16000);
            pcm[2 * i] = (byte)s;
            pcm[2 * i + 1] = (byte)(s >> 8);
        }
        beep = new SoundEffect(pcm, 22050, AudioChannels.Mono);
        beepInstance = beep.CreateInstance();
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
        var beepNow = !startBeep && (DateTime.Now - start).TotalSeconds > 1 ||
                      p.Buttons.A == ButtonState.Pressed && prev.Buttons.A == ButtonState.Released;
        startBeep |= beepNow;
        if (beepNow && beepInstance.State != SoundState.Playing)
            beepInstance.Play();
        if (beepInstance.State != lastBeepState)
            Console.WriteLine("beep: {0}", lastBeepState = beepInstance.State);
        if (p.Buttons != prev.Buttons)
            Console.WriteLine("buttons: {0}", string.Join(" ", new[] {
                p.Buttons.A == ButtonState.Pressed ? "A" : "", p.Buttons.B == ButtonState.Pressed ? "B" : "",
                p.Buttons.X == ButtonState.Pressed ? "X" : "", p.Buttons.Y == ButtonState.Pressed ? "Y" : "",
                p.Buttons.LeftShoulder == ButtonState.Pressed ? "L1" : "", p.Buttons.RightShoulder == ButtonState.Pressed ? "R1" : "",
                p.Triggers.Left > 0.5f ? "L2" : "", p.Triggers.Right > 0.5f ? "R2" : "",
                p.Buttons.LeftStick == ButtonState.Pressed ? "L3" : "", p.Buttons.RightStick == ButtonState.Pressed ? "R3" : "",
                p.Buttons.Back == ButtonState.Pressed ? "SELECT" : ""}.Where(b => b != "")));
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
