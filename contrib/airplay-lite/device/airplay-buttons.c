#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <alsa/asoundlib.h>
#include <math.h>

static volatile sig_atomic_t running = 1;
static long led_until = 0;
static int saved_led[9];
static const char *colors[] = {"red", "green", "blue"};
static void stop(int sig) { (void)sig; running = 0; }
static long now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000L + t.tv_nsec / 1000000L;
}
static int led_value(int index, int value) {
    char path[160];
    snprintf(path, sizeof(path), "/sys/class/leds/micro:%s:ring%d/brightness", colors[index / 3], index % 3 + 1);
    FILE *f = fopen(path, value < 0 ? "r" : "w");
    if (!f) return -1;
    int result = -1;
    if (value < 0) {
        if (fscanf(f, "%d", &result) != 1) result = -1;
    } else {
        fprintf(f, "%d\n", value);
        result = value;
    }
    fclose(f);
    return result;
}
static void restore_led(void) {
    if (!led_until) return;
    for (int i = 0; i < 9; i++)
        if (saved_led[i] >= 0 && led_value(i, -1) == 32) led_value(i, saved_led[i]);
    led_until = 0;
}
static void feedback(int input_fd) {
    for (int i = 0; i < 9; i++) {
        if (!led_until) saved_led[i] = led_value(i, -1);
        led_value(i, 32);
    }
    led_until = now_ms() + 140;
    pid_t child = fork();
    if (child != 0) return;
    close(input_fd);
    signal(SIGTERM, SIG_DFL);
    if (access("/tmp/shairport/restore-quasar", F_OK) != 0 && access("/tmp/shairport/playing", F_OK) != 0) {
        /* Native 32-bit ALSA shares Alice's mixer while AirPlay is paused. */
        unsetenv("ALSA_CONFIG_PATH");
        execl("/usr/bin/aplay", "aplay", "-q", "/data/shairport/button.wav", (char *)NULL);
        _exit(1);
    }
    /* Both this process and Shairport use the same private 64-bit dmix. */
    snd_pcm_t *pcm = NULL;
    int result = snd_pcm_open(&pcm, "default", SND_PCM_STREAM_PLAYBACK, SND_PCM_NONBLOCK);
    if (result < 0) { fprintf(stderr, "button sound: %s\n", snd_strerror(result)); _exit(1); }
    result = snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED, 2, 48000, 0, 80000);
    if (result < 0) { fprintf(stderr, "button sound parameters: %s\n", snd_strerror(result)); snd_pcm_close(pcm); _exit(1); }
    snd_pcm_nonblock(pcm, 0);
    enum { frames = 3360 };
    short samples[frames * 2];
    for (int i = 0; i < frames; i++) {
        double envelope = sin(3.141592653589793 * i / frames);
        short sample = (short)(1000.0 * envelope * envelope * sin(2.0 * 3.141592653589793 * 1100.0 * i / 48000.0));
        samples[i * 2] = samples[i * 2 + 1] = sample;
    }
    int offset = 0;
    while (offset < frames) {
        snd_pcm_sframes_t count = snd_pcm_writei(pcm, samples + offset * 2, frames - offset);
        if (count < 0) {
            if (snd_pcm_recover(pcm, (int)count, 1) < 0) break;
        } else offset += (int)count;
    }
    snd_pcm_drain(pcm);
    snd_pcm_close(pcm);
    _exit(0);
}
static int session_connected(void) {
    const char *tables[] = {"/proc/net/tcp", "/proc/net/tcp6"};
    for (unsigned i = 0; i < 2; i++) {
        FILE *f = fopen(tables[i], "r");
        if (!f) continue;
        char line[512], local[80], remote[80];
        unsigned state;
        while (fgets(line, sizeof(line), f)) {
            if (sscanf(line, "%*u: %79s %79s %x", local, remote, &state) == 3) {
                char *port = strrchr(local, ':');
                if (port && strtoul(port + 1, NULL, 16) == 7000 && state == 1) {
                    fclose(f);
                    return 1;
                }
            }
        }
        fclose(f);
    }
    return 0;
}
static void command(char *const argv[]) {
    pid_t child = fork();
    if (child == 0) {
        execv(argv[0], argv);
        _exit(127);
    }
    if (child < 0) { perror("fork"); return; }
    int status;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
}
int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    signal(SIGTERM, stop);
    signal(SIGINT, stop);
    setenv("DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/tmp/shairport/bus", 1);
    if (argc == 2 && strcmp(argv[1], "--feedback") == 0) {
        feedback(-1);
        while (now_ms() < led_until) usleep(10000);
        restore_led();
        int status = 0;
        if (wait(&status) < 0) return 1;
        return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    }
    /* The Lite's capacitive buttons are event1; event0 is the microphone switch. */
    int fd = open("/dev/input/event1", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) { perror("event1"); return 1; }
    int grabbed = 0, owned_session = 0;
    long last_volume = 0, last_toggle = 0;
    puts("AirPlay buttons ready");
    while (running) {
        while (waitpid(-1, NULL, WNOHANG) > 0) {}
        if (led_until && now_ms() >= led_until) restore_led();
        if (access("/tmp/shairport/playing", F_OK) == 0) owned_session = 1;
        else if (!session_connected()) owned_session = 0;
        if (owned_session != grabbed) {
            if (ioctl(fd, EVIOCGRAB, owned_session) == 0) {
                grabbed = owned_session;
                printf("AirPlay button ownership: %s\n", grabbed ? "active" : "released");
            }
        }
        struct pollfd pfd = {.fd = fd, .events = POLLIN};
        if (poll(&pfd, 1, led_until ? 20 : 200) <= 0) continue;
        if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) break;
        struct input_event ev;
        while (read(fd, &ev, sizeof(ev)) == sizeof(ev)) {
            if (ev.type != EV_KEY || ev.value == 0 || !grabbed) continue;
            long now = now_ms();
            if (ev.code == KEY_VOLUMEUP || ev.code == KEY_VOLUMEDOWN) {
                if (now - last_volume < 100) continue;
                last_volume = now;
                feedback(fd);
                char *args[] = {"/usr/bin/amixer", "-q", "sset", "Master", ev.code == KEY_VOLUMEUP ? "5%+" : "5%-", NULL};
                command(args);
                printf("key %u: volume %s\n", ev.code, ev.code == KEY_VOLUMEUP ? "up" : "down");
            } else if (ev.value == 1 && (ev.code == KEY_MUTE || ev.code == KEY_PLAYPAUSE || ev.code == KEY_PLAY || ev.code == KEY_PAUSE || ev.code == KEY_VOICECOMMAND)) {
                if (now - last_toggle < 700) continue;
                last_toggle = now;
                feedback(fd);
                char *args[] = {"/usr/bin/dbus-send", "--system", "--print-reply", "--reply-timeout=2000", "--dest=org.mpris.MediaPlayer2.ShairportSync", "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player.PlayPause", NULL};
                command(args);
                printf("key %u: play/pause\n", ev.code);
            } else {
                printf("unmapped key %u value %d\n", ev.code, ev.value);
            }
        }
    }
    restore_led();
    if (grabbed) ioctl(fd, EVIOCGRAB, 0);
    close(fd);
    return 0;
}
