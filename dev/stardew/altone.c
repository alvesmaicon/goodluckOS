// OpenAL Soft check without MonoGame: altone [Hz [amplitude]] plays 1 s of a tone (default 2000 Hz,
// loud: the speaker path high-passes at 500 Hz) and prints the device and any error.
#include <AL/al.h>
#include <AL/alc.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    double hz = argc > 1 ? atof(argv[1]) : 2000, amp = argc > 2 ? atof(argv[2]) : 24000;
    static short pcm[22050];
    ALCdevice *dev = alcOpenDevice(NULL);
    if (!dev) { puts("alcOpenDevice failed"); return 1; }
    ALCcontext *ctx = alcCreateContext(dev, NULL);
    alcMakeContextCurrent(ctx);
    printf("device: %s, renderer: %s\n", alcGetString(dev, ALC_ALL_DEVICES_SPECIFIER), alGetString(AL_RENDERER));
    for (int i = 0; i < 22050; i++) pcm[i] = (short)(sin(2 * M_PI * hz * i / 22050.0) * amp);
    ALuint buf, src;
    alGenBuffers(1, &buf);
    alBufferData(buf, AL_FORMAT_MONO16, pcm, sizeof pcm, 22050);
    alGenSources(1, &src);
    alSourcei(src, AL_BUFFER, buf);
    alSourcePlay(src);
    printf("play error: 0x%x\n", alGetError());
    ALint state;
    for (int t = 0; t < 12; t++) {
        alGetSourcei(src, AL_SOURCE_STATE, &state);
        printf("t=%d00ms state=0x%x\n", t, state);
        usleep(100000);
    }
    alDeleteSources(1, &src);
    alDeleteBuffers(1, &buf);
    alcMakeContextCurrent(NULL);
    alcDestroyContext(ctx);
    alcCloseDevice(dev);
    return 0;
}
