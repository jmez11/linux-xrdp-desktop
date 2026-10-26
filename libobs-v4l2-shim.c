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
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/ioctl.h>
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
 *    On loopback or virtual V4L2 devices, menu controls often report step = 0 or
 *    trigger infinite iterations. v4l2_ioctl / ioctl intercept control queries to ensure
 *    step >= 1, bounds are safe, and strings are null-terminated.
 *
 * 4. Crash diagnostics:
 *    Captures SIGSEGV / SIGABRT / SIGBUS / SIGFPE / SIGILL and dumps a full stack backtrace
 *    to stderr and /tmp/obs-crash.log using async-signal-safe I/O before passing the signal
 *    to the default handler.
 */

static DIR *(*real_opendir)(const char *name) = NULL;
static struct dirent *(*real_readdir)(DIR *dirp) = NULL;
static struct dirent64 *(*real_readdir64)(DIR *dirp) = NULL;
static int (*real_ioctl)(int fd, unsigned long int request, ...) = NULL;
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

    int fd = open("/tmp/obs-crash.log", O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd >= 0) {
        char buf[256];
        int len = snprintf(buf, sizeof(buf), "OBS Crash Signal %d: %s\nFault Address: %p, Signal Code: %d\nCall Stack:\n",
                           sig, strsignal(sig), info ? info->si_addr : NULL, info ? info->si_code : 0);
        if (len > 0) write(fd, buf, len);
        backtrace_symbols_fd(frames, n, fd);
        close(fd);
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

    real_opendir = (DIR *(*)(const char *))dlsym(RTLD_NEXT, "opendir");
    real_readdir = (struct dirent *(*)(DIR *))dlsym(RTLD_NEXT, "readdir");
    real_readdir64 = (struct dirent64 *(*)(DIR *))dlsym(RTLD_NEXT, "readdir64");
    real_ioctl = (int (*)(int, unsigned long int, ...))dlsym(RTLD_NEXT, "ioctl");

    real_v4l2_open = (int (*)(const char *, int, ...))dlsym(RTLD_NEXT, "v4l2_open");
    real_v4l2_close = (int (*)(int))dlsym(RTLD_NEXT, "v4l2_close");
    real_v4l2_ioctl = (int (*)(int, unsigned long int, ...))dlsym(RTLD_NEXT, "v4l2_ioctl");

    void *h = dlopen("libv4l2.so.0", RTLD_LAZY);
    if (h) {
        if (!real_v4l2_open) real_v4l2_open = (int (*)(const char *, int, ...))dlsym(h, "v4l2_open");
        if (!real_v4l2_close) real_v4l2_close = (int (*)(int))dlsym(h, "v4l2_close");
        if (!real_v4l2_ioctl) real_v4l2_ioctl = (int (*)(int, unsigned long int, ...))dlsym(h, "v4l2_ioctl");
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

struct dirent *readdir(DIR *dirp) {
    if (!real_readdir) {
        real_readdir = (struct dirent *(*)(DIR *))dlsym(RTLD_NEXT, "readdir");
    }
    struct dirent *de = real_readdir ? real_readdir(dirp) : NULL;
    if (de && strncmp(de->d_name, "video", 5) == 0) {
        if (de->d_type == DT_DIR || de->d_type == DT_UNKNOWN) {
            de->d_type = DT_LNK;
        }
    }
    return de;
}

struct dirent64 *readdir64(DIR *dirp) {
    if (!real_readdir64) {
        real_readdir64 = (struct dirent64 *(*)(DIR *))dlsym(RTLD_NEXT, "readdir64");
    }
    struct dirent64 *de = real_readdir64 ? real_readdir64(dirp) : NULL;
    if (de && strncmp(de->d_name, "video", 5) == 0) {
        if (de->d_type == DT_DIR || de->d_type == DT_UNKNOWN) {
            de->d_type = DT_LNK;
        }
    }
    return de;
}

DIR *opendir(const char *name) {
    if (!real_opendir) {
        real_opendir = (DIR *(*)(const char *))dlsym(RTLD_NEXT, "opendir");
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
        real_v4l2_open = (int (*)(const char *, int, ...))dlsym(RTLD_NEXT, "v4l2_open");
        if (!real_v4l2_open) {
            void *h = dlopen("libv4l2.so.0", RTLD_LAZY);
            if (h) real_v4l2_open = (int (*)(const char *, int, ...))dlsym(h, "v4l2_open");
        }
    }

    const char *target = file;
    if (!target || target[0] == '\0') {
        target = get_default_v4l2_device();
    }

    if (!real_v4l2_open) {
        return open(target, oflag, mode);
    }
    int fd = real_v4l2_open(target, oflag, mode);
    fprintf(stderr, "[libobs-v4l2-shim] v4l2_open(\"%s\", oflag=0x%x) = %d\n", target ? target : "(null)", oflag, fd);
    return fd;
}

int v4l2_close(int fd) {
    if (!real_v4l2_close) {
        real_v4l2_close = (int (*)(int))dlsym(RTLD_NEXT, "v4l2_close");
        if (!real_v4l2_close) {
            void *h = dlopen("libv4l2.so.0", RTLD_LAZY);
            if (h) real_v4l2_close = (int (*)(int))dlsym(h, "v4l2_close");
        }
    }
    fprintf(stderr, "[libobs-v4l2-shim] v4l2_close(%d)\n", fd);
    return real_v4l2_close ? real_v4l2_close(fd) : close(fd);
}

static int handle_v4l2_ioctl_result(int fd, unsigned long int request, void *arg, int ret) {
    (void)fd;
    if (!arg) return ret;

    if (request == VIDIOC_QUERYCTRL && ret == 0) {
        struct v4l2_queryctrl *qc = (struct v4l2_queryctrl *)arg;
        if (qc->step == 0) {
            qc->step = 1;
        }
        if (qc->maximum < qc->minimum) {
            qc->maximum = qc->minimum;
        }
        if (qc->type == V4L2_CTRL_TYPE_MENU && (qc->maximum - qc->minimum) > 256) {
            qc->maximum = qc->minimum + 256;
        }
        qc->name[sizeof(qc->name) - 1] = '\0';
    } else if (request == VIDIOC_QUERYMENU && ret == 0) {
        struct v4l2_querymenu *qm = (struct v4l2_querymenu *)arg;
        qm->name[sizeof(qm->name) - 1] = '\0';
    } else if (request == VIDIOC_ENUM_FRAMEINTERVALS) {
        struct v4l2_frmivalenum *fi = (struct v4l2_frmivalenum *)arg;
        if (ret != 0) {
            fi->type = 0;
        } else if (fi->type == V4L2_FRMIVAL_TYPE_DISCRETE) {
            if (fi->discrete.numerator == 0) fi->discrete.numerator = 1;
            if (fi->discrete.denominator == 0) fi->discrete.denominator = 30;
        }
    } else if (request == VIDIOC_ENUM_FRAMESIZES) {
        struct v4l2_frmsizeenum *fs = (struct v4l2_frmsizeenum *)arg;
        if (ret != 0) {
            fs->type = 0;
        } else if (fs->type == V4L2_FRMSIZE_TYPE_DISCRETE) {
            if (fs->discrete.width == 0) fs->discrete.width = 1920;
            if (fs->discrete.height == 0) fs->discrete.height = 1080;
        }
    } else if (request == VIDIOC_QUERYCAP && ret == 0) {
        struct v4l2_capability *cap = (struct v4l2_capability *)arg;
        cap->driver[sizeof(cap->driver) - 1] = '\0';
        cap->card[sizeof(cap->card) - 1] = '\0';
        cap->bus_info[sizeof(cap->bus_info) - 1] = '\0';
    }

    return ret;
}

int v4l2_ioctl(int fd, unsigned long int request, ...) {
    va_list ap;
    va_start(ap, request);
    void *arg = va_arg(ap, void *);
    va_end(ap);

    if (!real_v4l2_ioctl) {
        real_v4l2_ioctl = (int (*)(int, unsigned long int, ...))dlsym(RTLD_NEXT, "v4l2_ioctl");
        if (!real_v4l2_ioctl) {
            void *h = dlopen("libv4l2.so.0", RTLD_LAZY);
            if (h) real_v4l2_ioctl = (int (*)(int, unsigned long int, ...))dlsym(h, "v4l2_ioctl");
        }
    }

    int ret;
    if (real_v4l2_ioctl) {
        ret = real_v4l2_ioctl(fd, request, arg);
    } else {
        ret = ioctl(fd, request, arg);
    }

    return handle_v4l2_ioctl_result(fd, request, arg, ret);
}

int ioctl(int fd, unsigned long int request, ...) {
    va_list ap;
    va_start(ap, request);
    void *arg = va_arg(ap, void *);
    va_end(ap);

    if (!real_ioctl) {
        real_ioctl = (int (*)(int, unsigned long int, ...))dlsym(RTLD_NEXT, "ioctl");
    }
    if (!real_ioctl) {
        return -1;
    }

    int ret = real_ioctl(fd, request, arg);
    return handle_v4l2_ioctl_result(fd, request, arg, ret);
}
