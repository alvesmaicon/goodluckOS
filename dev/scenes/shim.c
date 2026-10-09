/* LD_PRELOAD for dev/gl scenes: the console's ALSA mixer and a frozen wall clock, so screenshots
 * taken on any machine come out the same.
 * FAKE_VOLUME (0-100, default 60), FAKE_MUTED, FAKE_SPEAKER (1 speaker, 0 headphones): the mixer's
 * starting state; what the app sets is kept for the rest of the run.
 * FAKE_EPOCH: the wall clock, in seconds since 1970. CLOCK_MONOTONIC is untouched, so timers run. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>

typedef struct snd_mixer snd_mixer_t;
typedef struct snd_mixer_elem snd_mixer_elem_t;
typedef struct snd_mixer_selem_id snd_mixer_selem_id_t;
extern const char* snd_mixer_selem_id_get_name(const snd_mixer_selem_id_t* id);

struct elem { int ready; long volume; int on; int item; };
static struct elem headphone, speaker, filter, cutoff;

static int env_int(const char* name, int fallback) {
    const char* v = getenv(name);
    return v ? atoi(v) : fallback;
}

static struct elem* get(snd_mixer_elem_t* e) {
    struct elem* x = (struct elem*)e;
    if (!x->ready) {
        x->ready = 1;
        x->volume = env_int("FAKE_VOLUME", 60);
        x->on = x == &speaker ? env_int("FAKE_SPEAKER", 1) : x == &headphone ? !env_int("FAKE_MUTED", 0) : 1;
    }
    return x;
}

int snd_mixer_attach(snd_mixer_t* m, const char* name) { (void)m; (void)name; return 0; }
int snd_mixer_selem_register(snd_mixer_t* m, void* o, void* c) { (void)m; (void)o; (void)c; return 0; }
int snd_mixer_load(snd_mixer_t* m) { (void)m; return 0; }

snd_mixer_elem_t* snd_mixer_find_selem(snd_mixer_t* m, const snd_mixer_selem_id_t* id) {
    (void)m;
    const char* n = snd_mixer_selem_id_get_name(id);
    if (!n) return NULL;
    if (!strcmp(n, "Headphone")) return (snd_mixer_elem_t*)&headphone;
    if (!strcmp(n, "Speaker")) return (snd_mixer_elem_t*)&speaker;
    if (!strcmp(n, "DAC High-Pass Filter")) return (snd_mixer_elem_t*)&filter;
    if (!strcmp(n, "DAC High-Pass Filter Cutoff")) return (snd_mixer_elem_t*)&cutoff;
    return NULL;
}

int snd_mixer_selem_get_playback_volume_range(snd_mixer_elem_t* e, long* min, long* max) {
    (void)e; *min = 0; *max = 100; return 0;
}
int snd_mixer_selem_get_playback_volume(snd_mixer_elem_t* e, int ch, long* v) { (void)ch; *v = get(e)->volume; return 0; }
int snd_mixer_selem_set_playback_volume_all(snd_mixer_elem_t* e, long v) { get(e)->volume = v; return 0; }
int snd_mixer_selem_has_playback_switch(snd_mixer_elem_t* e) { (void)e; return 1; }
int snd_mixer_selem_get_playback_switch(snd_mixer_elem_t* e, int ch, int* v) { (void)ch; *v = get(e)->on; return 0; }
int snd_mixer_selem_set_playback_switch_all(snd_mixer_elem_t* e, int v) { get(e)->on = v; return 0; }
int snd_mixer_selem_is_enumerated(snd_mixer_elem_t* e) { return e == (snd_mixer_elem_t*)&cutoff; }
int snd_mixer_selem_set_enum_item(snd_mixer_elem_t* e, int ch, unsigned int item) { (void)ch; get(e)->item = (int)item; return 0; }

static time_t fake_epoch(void) {
    const char* v = getenv("FAKE_EPOCH");
    return v ? (time_t)atoll(v) : 0;
}

time_t time(time_t* t) {
    time_t now = fake_epoch();
    if (!now) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        now = ts.tv_sec;
    }
    if (t) *t = now;
    return now;
}

int clock_gettime(clockid_t id, struct timespec* ts) {
    static int (*real)(clockid_t, struct timespec*);
    if (!real) real = (int (*)(clockid_t, struct timespec*))dlsym(RTLD_NEXT, "clock_gettime");
    if ((id == CLOCK_REALTIME || id == CLOCK_REALTIME_COARSE) && fake_epoch()) {
        ts->tv_sec = fake_epoch();
        ts->tv_nsec = 0;
        return 0;
    }
    return real(id, ts);
}

int gettimeofday(struct timeval* tv, void* tz) {
    struct timespec ts;
    (void)tz;
    clock_gettime(CLOCK_REALTIME, &ts);
    tv->tv_sec = ts.tv_sec;
    tv->tv_usec = ts.tv_nsec / 1000;
    return 0;
}
