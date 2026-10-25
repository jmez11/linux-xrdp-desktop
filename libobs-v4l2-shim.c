#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <signal.h>
#include <execinfo.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <linux/videodev2.h>

/*
 * libobs-v4l2-shim:
 * Compatibility shim and diagnostics for OBS Studio running inside Docker / XRDP.
 *
 * 1. sysfs emulation and readdir d_type:
 *    OBS Studio enumerates video devices by scanning /sys/class/video4linux and
 *    skips any entry where d_type == DT_DIR. In container environments where video
 *    nodes are synthesized as directories or over tmpfs, readdir/readdir64 are patched
 *    to return d_type = DT_LNK so OBS discovers all active /dev/video* devices.
 *
 * 2. Empty device_id safety:
 *    When a source is created or queried without an explicit device_id, v4l2_open()
 *    defaults to the first accessible /dev/video* node rather than failing or aborting.
 *
 * 3. Control query safety (VIDIOC_QUERYCTRL / VIDIOC_QUERYMENU):
 *    On loopback or virtual V4L2 devices, menu controls often report step = 0.
 *    OBS's v4l2-controls iterates with `index += qctrl->step`, causing an infinite
 *    loop and memory exhaustion. v4l2_ioctl intercepts control queries to ensure
 *    step >= 1 and strings are null-terminated.
 *
 * 4. Crash diagnostics:
 *    Captures SIGSEGV / SIGABRT / SIGBUS / SIGFPE and dumps a full stack backtrace
 *    to stderr and /tmp/obs-crash.log before passing the signal to the default handler.
 */

static DIR *(*real_opendir)(const char *name) = NULL;
static struct dirent *(*real_readdir)(DIR *dirp) = NULL;
static struct dirent *(*real_readdir64)(DIR *dirp) = NULL;
static int (*real_v4l2_open)(const char *file, int oflag, ...) = NULL;
static int (*real_v4l2_close)(int fd) = NULL;
static int (*real_v4l2_ioctl)(int fd, unsigned long int request, ...) = NULL;

static void crash_handler(int sig, siginfo_t *info, void *ucontext) {
    (void)ucontext;
    void *frames[128];
    int n = backtrace(frames, 128);

    fprintf(stderr, "\n=================================================================\n");
    fprintf(stderr, "=== OBS CRASH CAUGHT BY LIBOBS-V4L2-SHIM (Signal %d: %s) ===\n", sig, strsignal(sig));
    if (info) {
        fprintf(stderr, "=== Fault Address: %p, Signal Code: %d ===\n", info->si_addr, info->si_code);
    }
    fprintf(stderr, "=== Call Stack (%d frames): ===\n", n);
    backtrace_symbols_fd(frames, n, STDERR_FILENO);
    fprintf(stderr, "=================================================================\n\n");
    fflush(stderr);

    FILE *f = fopen("/tmp/obs-crash.log", "w");
    if (f) {
        fprintf(f, "OBS Crash Signal %d: %s\n", sig, strsignal(sig));
        if (info) fprintf(f, "Fault Address: %p, Signal Code: %d\n", info->si_addr, info->si_code);
        backtrace_symbols_fd(frames, n, fileno(f));
        fclose(f);
    }

    signal(sig, SIG_DFL);
    raise(sig);
}

static void install_crash_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = crash_handler;
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND;
    sigemptyset(&sa.sa_mask);

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGFPE, &sa, NULL);
    sigaction(SIGILL, &sa, NULL);
}

__attribute__((constructor))
static void init_shim(void) {
    install_crash_handlers();

    real_opendir = dlsym(RTLD_NEXT, "opendir");
    real_readdir = dlsym(RTLD_NEXT, "readdir");
    real_readdir64 = dlsym(RTLD_NEXT, "readdir64");
    if (!real_readdir64) real_readdir64 = real_readdir;

    real_v4l2_open = dlsym(RTLD_NEXT, "v4l2_open");
    real_v4l2_close = dlsym(RTLD_NEXT, "v4l2_close");
    real_v4l2_ioctl = dlsym(RTLD_NEXT, "v4l2_ioctl");

    void *h = dlopen("libv4l2.so.0", RTLD_LAZY);
    if (h) {
        if (!real_v4l2_open) real_v4l2_open = dlsym(h, "v4l2_open");
        if (!real_v4l2_close) real_v4l2_close = dlsym(h, "v4l2_close");
        if (!real_v4l2_ioctl) real_v4l2_ioctl = dlsym(h, "v4l2_ioctl");
    }

    fprintf(stderr, "[libobs-v4l2-shim] Compatibility shim initialized successfully\n");
}

static const char *get_default_v4l2_device(void) {
    static char found[64] = "";
    if (found[0] != '\0' && access(found, F_OK) == 0) {
        return found;
    }
    for (int i = 0; i < 64; i++) {
        char devpath[32];
        snprintf(devpath, sizeof(devpath), "/dev/video%d", i);
        if (access(devpath, F_OK) == 0) {
            strncpy(found, devpath, sizeof(found) - 1);
            return found;
        }
    }
    return "/dev/video0";
}

static struct dirent *patch_dirent(struct dirent *de) {
    if (de && strncmp(de->d_name, "video", 5) == 0) {
        if (de->d_type == DT_DIR || de->d_type == DT_UNKNOWN) {
            de->d_type = DT_LNK;
        }
    }
    return de;
}

struct dirent *readdir(DIR *dirp) {
    if (!real_readdir) {
        real_readdir = dlsym(RTLD_NEXT, "readdir");
    }
    return patch_dirent(real_readdir ? real_readdir(dirp) : NULL);
}

struct dirent *readdir64(DIR *dirp) {
    if (!real_readdir64) {
        real_readdir64 = dlsym(RTLD_NEXT, "readdir64");
        if (!real_readdir64) real_readdir64 = real_readdir;
    }
    return patch_dirent(real_readdir64 ? real_readdir64(dirp) : NULL);
}

DIR *opendir(const char *name) {
    if (!real_opendir) {
        real_opendir = dlsym(RTLD_NEXT, "opendir");
    }

    if (name && strcmp(name, "/sys/class/video4linux") == 0) {
        DIR *d = real_opendir ? real_opendir(name) : NULL;
        if (d) {
            struct dirent *de;
            int count = 0;
            while ((de = readdir(d)) != NULL) {
                if (strncmp(de->d_name, "video", 5) == 0) {
                    count++;
                }
            }
            rewinddir(d);
            if (count > 0) {
                return d;
            }
            closedir(d);
        }

        /* Real /sys/class/video4linux is absent or has no entries; synthesize in /tmp/video4linux */
        mkdir("/tmp/video4linux-targets", 0755);
        mkdir("/tmp/video4linux", 0755);
        for (int i = 0; i < 64; i++) {
            char devpath[32];
            snprintf(devpath, sizeof(devpath), "/dev/video%d", i);
            if (access(devpath, F_OK) == 0) {
                char targetpath[64], linkpath[64];
                snprintf(targetpath, sizeof(targetpath), "/tmp/video4linux-targets/video%d", i);
                snprintf(linkpath, sizeof(linkpath), "/tmp/video4linux/video%d", i);
                mkdir(targetpath, 0755);
                char namepath[80];
                snprintf(namepath, sizeof(namepath), "%s/name", targetpath);
                FILE *nf = fopen(namepath, "w");
                if (nf) {
                    fprintf(nf, "XRDP Camera %d\n", i);
                    fclose(nf);
                }
                char idxpath[80];
                snprintf(idxpath, sizeof(idxpath), "%s/index", targetpath);
                FILE *ifile = fopen(idxpath, "w");
                if (ifile) {
                    fprintf(ifile, "%d\n", i);
                    fclose(ifile);
                }
                unlink(linkpath);
                symlink(targetpath, linkpath);
            }
        }
        return real_opendir ? real_opendir("/tmp/video4linux") : NULL;
    }

    return real_opendir ? real_opendir(name) : NULL;
}

int v4l2_open(const char *file, int oflag, ...) {
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list ap;
        va_start(ap, oflag);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }

    if (!real_v4l2_open) {
        real_v4l2_open = dlsym(RTLD_NEXT, "v4l2_open");
        if (!real_v4l2_open) {
            void *h = dlopen("libv4l2.so.0", RTLD_LAZY);
            if (h) real_v4l2_open = dlsym(h, "v4l2_open");
        }
    }

    const char *target = file;
    if (!target || target[0] == '\0') {
        target = get_default_v4l2_device();
    }

    if (!real_v4l2_open) {
        return -1;
    }
    int fd = real_v4l2_open(target, oflag, mode);
    fprintf(stderr, "[libobs-v4l2-shim] v4l2_open(\"%s\", oflag=0x%x) = %d\n", target ? target : "(null)", oflag, fd);
    return fd;
}

int v4l2_close(int fd) {
    if (!real_v4l2_close) {
        real_v4l2_close = dlsym(RTLD_NEXT, "v4l2_close");
        if (!real_v4l2_close) {
            void *h = dlopen("libv4l2.so.0", RTLD_LAZY);
            if (h) real_v4l2_close = dlsym(h, "v4l2_close");
        }
    }
    fprintf(stderr, "[libobs-v4l2-shim] v4l2_close(%d)\n", fd);
    return real_v4l2_close ? real_v4l2_close(fd) : close(fd);
}

int v4l2_ioctl(int fd, unsigned long int request, ...) {
    va_list ap;
    va_start(ap, request);
    void *arg = va_arg(ap, void *);
    va_end(ap);

    if (!real_v4l2_ioctl) {
        real_v4l2_ioctl = dlsym(RTLD_NEXT, "v4l2_ioctl");
        if (!real_v4l2_ioctl) {
            void *h = dlopen("libv4l2.so.0", RTLD_LAZY);
            if (h) real_v4l2_ioctl = dlsym(h, "v4l2_ioctl");
        }
    }
    if (!real_v4l2_ioctl) {
        return -1;
    }

    int ret = real_v4l2_ioctl(fd, request, arg);

    if (request == VIDIOC_QUERYCTRL && ret == 0 && arg) {
        struct v4l2_queryctrl *qc = (struct v4l2_queryctrl *)arg;
        if (qc->step == 0) {
            qc->step = 1;
        }
        qc->name[sizeof(qc->name) - 1] = '\0';
    } else if (request == VIDIOC_QUERYMENU && ret == 0 && arg) {
        struct v4l2_querymenu *qm = (struct v4l2_querymenu *)arg;
        qm->name[sizeof(qm->name) - 1] = '\0';
    } else if (request == VIDIOC_ENUM_FRAMEINTERVALS && ret != 0 && arg) {
        struct v4l2_frmivalenum *fi = (struct v4l2_frmivalenum *)arg;
        fi->type = 0;
    } else if (request == VIDIOC_ENUM_FRAMESIZES && ret != 0 && arg) {
        struct v4l2_frmsizeenum *fs = (struct v4l2_frmsizeenum *)arg;
        fs->type = 0;
    }

    return ret;
}
