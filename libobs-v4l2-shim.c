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
#include <sys/mman.h>
#include <linux/videodev2.h>

/*
 * libobs-v4l2-shim:
 * Compatibility shim and diagnostics for OBS Studio running inside Docker / XRDP.
 *
 * 1. sysfs emulation, scandir, and readdir:
 *    OBS Studio enumerates video devices by calling scandir() on /sys/class/video4linux
 *    and skips any entry where d_type == DT_DIR. In container environments where sysfs
 *    is read-only or video4linux is missing, scandir returns -1, causing OBS to invoke
 *    free() on an uninitialized stack pointer and abort (SIGABRT).
 *    scandir/scandir64, opendir, readdir/readdir64, realpath, access, and fopen intercept
 *    /sys/class/video4linux, /dev/v4l/by-id, and /dev/v4l/by-path, redirecting to synthesized
 *    trees in /tmp with d_type = DT_LNK and guaranteed *namelist = NULL on error.
 *
 * 2. In-memory hotfix for OBS Linux-V4L2 PR 6493 NULL dereference bug:
 *    In OBS 30.0.2 linux-v4l2 plugin, v4l2_device_add_devices_from iterates
 *    `while (current_device->next != NULL)` without checking if `current_device` is NULL.
 *    When /dev/v4l/by-id and /dev/v4l/by-path have no devices, `first_device` is NULL,
 *    triggering a SIGSEGV at offset 0x50. The shim automatically patches this instruction
 *    sequence in linux-v4l2.so in memory to guard against NULL.
 *
 * 3. Empty device_id safety:
 *    When a source is created or queried without an explicit device_id, v4l2_open()
 *    defaults to the first accessible /dev/video* node rather than failing or aborting.
 *
 * 4. Control query safety (VIDIOC_QUERYCTRL / VIDIOC_QUERYMENU):
 *    On loopback or virtual V4L2 devices, menu controls often report step = 0 or
 *    trigger infinite iterations. v4l2_ioctl / ioctl intercept control queries to ensure
 *    step >= 1, bounds are safe, and strings are null-terminated.
 *
 * 5. Crash diagnostics:
 *    Captures SIGSEGV / SIGABRT / SIGBUS / SIGFPE / SIGILL and dumps a full stack backtrace
 *    to stderr and /tmp/obs-crash.log using async-signal-safe I/O before passing the signal
 *    to the default handler.
 */

static __thread int in_shim = 0;

static void *(*real_dlopen)(const char *filename, int flags) = NULL;
static DIR *(*real_opendir)(const char *name) = NULL;
static struct dirent *(*real_readdir)(DIR *dirp) = NULL;
static struct dirent64 *(*real_readdir64)(DIR *dirp) = NULL;
static int (*real_scandir)(const char *dirp,
                           struct dirent ***namelist,
                           int (*filter)(const struct dirent *),
                           int (*compar)(const struct dirent **, const struct dirent **)) = NULL;
static int (*real_scandir64)(const char *dirp,
                             struct dirent64 ***namelist,
                             int (*filter)(const struct dirent64 *),
                             int (*compar)(const struct dirent64 **, const struct dirent64 **)) = NULL;
static char *(*real_realpath)(const char *path, char *resolved_path) = NULL;
static int (*real_access)(const char *pathname, int mode) = NULL;
static FILE *(*real_fopen)(const char *pathname, const char *mode) = NULL;
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

static void patch_linux_v4l2_memory(void) {
    static int patched = 0;
    if (patched) return;

    FILE *f = fopen("/proc/self/maps", "r");
    if (!f) return;
    char line[512];
    uintptr_t start = 0, end = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "linux-v4l2.so") && strstr(line, "r-xp")) {
            if (sscanf(line, "%lx-%lx", &start, &end) == 2) {
                break;
            }
        }
    }
    fclose(f);

    if (start && end && end > start) {
        const unsigned char target[16] = {
            0x4c, 0x8b, 0xbd, 0x00, 0xef, 0xff, 0xff, 0xeb,
            0x20, 0x0f, 0x1f, 0x80, 0x00, 0x00, 0x00, 0x00
        };
        const unsigned char fix[9] = {
            0x4d, 0x85, 0xff, 0x74, 0x29, 0xeb, 0x1b, 0x90, 0x90
        };
        for (uintptr_t p = start; p <= end - sizeof(target); p++) {
            if (memcmp((void *)p, target, sizeof(target)) == 0) {
                uintptr_t page_start = (p + 7) & ~0xFFFUL;
                size_t page_len = (((p + 7 + sizeof(fix)) + 0xFFFUL) & ~0xFFFUL) - page_start;
                if (mprotect((void *)page_start, page_len, PROT_READ | PROT_WRITE | PROT_EXEC) == 0) {
                    memcpy((void *)(p + 7), fix, sizeof(fix));
                    mprotect((void *)page_start, page_len, PROT_READ | PROT_EXEC);
                    fprintf(stderr, "[libobs-v4l2-shim] Applied in-memory hotfix to linux-v4l2.so at %p\n", (void *)p);
                    patched = 1;
                }
                break;
            } else if (memcmp((void *)p, "\x4c\x8b\xbd\x00\xef\xff\xff\x4d\x85\xff\x74\x29\xeb\x1b\x90\x90", 16) == 0) {
                patched = 1;
                break;
            }
        }
    }
}

__attribute__((constructor))
static void init_shim(void) {
    install_crash_handlers();

    real_dlopen = (void *(*)(const char *, int))dlsym(RTLD_NEXT, "dlopen");
    real_opendir = (DIR *(*)(const char *))dlsym(RTLD_NEXT, "opendir");
    real_readdir = (struct dirent *(*)(DIR *))dlsym(RTLD_NEXT, "readdir");
    real_readdir64 = (struct dirent64 *(*)(DIR *))dlsym(RTLD_NEXT, "readdir64");
    real_scandir = (int (*)(const char *, struct dirent ***,
                            int (*)(const struct dirent *),
                            int (*)(const struct dirent **, const struct dirent **)))dlsym(RTLD_NEXT, "scandir");
    real_scandir64 = (int (*)(const char *, struct dirent64 ***,
                              int (*)(const struct dirent64 *),
                              int (*)(const struct dirent64 **, const struct dirent64 **)))dlsym(RTLD_NEXT, "scandir64");
    real_realpath = (char *(*)(const char *, char *))dlsym(RTLD_NEXT, "realpath");
    real_access = (int (*)(const char *, int))dlsym(RTLD_NEXT, "access");
    real_fopen = (FILE *(*)(const char *, const char *))dlsym(RTLD_NEXT, "fopen");
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

    patch_linux_v4l2_memory();

    fprintf(stderr, "[libobs-v4l2-shim] Compatibility shim initialized successfully\n");
}

void *dlopen(const char *filename, int flags) {
    if (!real_dlopen) {
        real_dlopen = (void *(*)(const char *, int))dlsym(RTLD_NEXT, "dlopen");
    }
    void *res = real_dlopen ? real_dlopen(filename, flags) : NULL;
    if (filename && strstr(filename, "linux-v4l2.so")) {
        patch_linux_v4l2_memory();
    }
    return res;
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

static void ensure_video4linux_tree(void) {
    mkdir("/tmp/video4linux-targets", 0755);
    mkdir("/tmp/video4linux", 0755);
    mkdir("/tmp/v4l", 0755);
    mkdir("/tmp/v4l/by-id", 0755);
    mkdir("/tmp/v4l/by-path", 0755);

    mkdir("/dev/v4l", 0755);
    mkdir("/dev/v4l/by-id", 0755);
    mkdir("/dev/v4l/by-path", 0755);

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

            char by_id[64], by_path[64];
            snprintf(by_id, sizeof(by_id), "/tmp/v4l/by-id/usb-xrdp-camera-video%d", i);
            snprintf(by_path, sizeof(by_path), "/tmp/v4l/by-path/platform-xrdp-camera-video%d", i);
            unlink(by_id);
            symlink(devpath, by_id);
            unlink(by_path);
            symlink(devpath, by_path);

            char dev_by_id[64], dev_by_path[64];
            snprintf(dev_by_id, sizeof(dev_by_id), "/dev/v4l/by-id/usb-xrdp-camera-video%d", i);
            snprintf(dev_by_path, sizeof(dev_by_path), "/dev/v4l/by-path/platform-xrdp-camera-video%d", i);
            unlink(dev_by_id);
            symlink(devpath, dev_by_id);
            unlink(dev_by_path);
            symlink(devpath, dev_by_path);
        }
    }
}

int scandir(const char *dirp,
            struct dirent ***namelist,
            int (*filter)(const struct dirent *),
            int (*compar)(const struct dirent **, const struct dirent **)) {
    if (namelist) {
        *namelist = NULL;
    }

    patch_linux_v4l2_memory();

    if (in_shim) {
        if (!real_scandir) {
            real_scandir = (int (*)(const char *, struct dirent ***,
                                    int (*)(const struct dirent *),
                                    int (*)(const struct dirent **, const struct dirent **)))dlsym(RTLD_NEXT, "scandir");
        }
        return real_scandir ? real_scandir(dirp, namelist, filter, compar) : -1;
    }

    in_shim = 1;

    if (!real_scandir) {
        real_scandir = (int (*)(const char *, struct dirent ***,
                                int (*)(const struct dirent *),
                                int (*)(const struct dirent **, const struct dirent **)))dlsym(RTLD_NEXT, "scandir");
    }

    const char *target = dirp;
    if (dirp) {
        if (strcmp(dirp, "/sys/class/video4linux") == 0) {
            ensure_video4linux_tree();
            target = "/tmp/video4linux";
        } else if (strncmp(dirp, "/dev/v4l/by-id", 14) == 0) {
            ensure_video4linux_tree();
            if (access(dirp, F_OK) != 0) {
                target = "/tmp/v4l/by-id";
            }
        } else if (strncmp(dirp, "/dev/v4l/by-path", 16) == 0) {
            ensure_video4linux_tree();
            if (access(dirp, F_OK) != 0) {
                target = "/tmp/v4l/by-path";
            }
        }
    }

    int n = 0;
    if (real_scandir) {
        n = real_scandir(target, namelist, filter, compar);
    }

    if (n < 0) {
        if (namelist) *namelist = NULL;
        n = 0;
    } else if (namelist && *namelist && n > 0) {
        for (int i = 0; i < n; i++) {
            struct dirent *de = (*namelist)[i];
            if (de && (strncmp(de->d_name, "video", 5) == 0 ||
                       strncmp(de->d_name, "usb-", 4) == 0 ||
                       strncmp(de->d_name, "platform-", 9) == 0)) {
                if (de->d_type == DT_DIR || de->d_type == DT_UNKNOWN) {
                    de->d_type = DT_LNK;
                }
            }
        }
    }

    in_shim = 0;
    return n;
}

int scandir64(const char *dirp,
              struct dirent64 ***namelist,
              int (*filter)(const struct dirent64 *),
              int (*compar)(const struct dirent64 **, const struct dirent64 **)) {
    if (namelist) {
        *namelist = NULL;
    }

    patch_linux_v4l2_memory();

    if (in_shim) {
        if (!real_scandir64) {
            real_scandir64 = (int (*)(const char *, struct dirent64 ***,
                                      int (*)(const struct dirent64 *),
                                      int (*)(const struct dirent64 **, const struct dirent64 **)))dlsym(RTLD_NEXT, "scandir64");
        }
        return real_scandir64 ? real_scandir64(dirp, namelist, filter, compar) : -1;
    }

    in_shim = 1;

    if (!real_scandir64) {
        real_scandir64 = (int (*)(const char *, struct dirent64 ***,
                                  int (*)(const struct dirent64 *),
                                  int (*)(const struct dirent64 **, const struct dirent64 **)))dlsym(RTLD_NEXT, "scandir64");
    }

    const char *target = dirp;
    if (dirp) {
        if (strcmp(dirp, "/sys/class/video4linux") == 0) {
            ensure_video4linux_tree();
            target = "/tmp/video4linux";
        } else if (strncmp(dirp, "/dev/v4l/by-id", 14) == 0) {
            ensure_video4linux_tree();
            if (access(dirp, F_OK) != 0) {
                target = "/tmp/v4l/by-id";
            }
        } else if (strncmp(dirp, "/dev/v4l/by-path", 16) == 0) {
            ensure_video4linux_tree();
            if (access(dirp, F_OK) != 0) {
                target = "/tmp/v4l/by-path";
            }
        }
    }

    int n = 0;
    if (real_scandir64) {
        n = real_scandir64(target, namelist, filter, compar);
    }

    if (n < 0) {
        if (namelist) *namelist = NULL;
        n = 0;
    } else if (namelist && *namelist && n > 0) {
        for (int i = 0; i < n; i++) {
            struct dirent64 *de = (*namelist)[i];
            if (de && (strncmp(de->d_name, "video", 5) == 0 ||
                       strncmp(de->d_name, "usb-", 4) == 0 ||
                       strncmp(de->d_name, "platform-", 9) == 0)) {
                if (de->d_type == DT_DIR || de->d_type == DT_UNKNOWN) {
                    de->d_type = DT_LNK;
                }
            }
        }
    }

    in_shim = 0;
    return n;
}

struct dirent *readdir(DIR *dirp) {
    if (!real_readdir) {
        real_readdir = (struct dirent *(*)(DIR *))dlsym(RTLD_NEXT, "readdir");
    }
    struct dirent *de = real_readdir ? real_readdir(dirp) : NULL;
    if (de && (strncmp(de->d_name, "video", 5) == 0 ||
               strncmp(de->d_name, "usb-", 4) == 0 ||
               strncmp(de->d_name, "platform-", 9) == 0)) {
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
    if (de && (strncmp(de->d_name, "video", 5) == 0 ||
               strncmp(de->d_name, "usb-", 4) == 0 ||
               strncmp(de->d_name, "platform-", 9) == 0)) {
        if (de->d_type == DT_DIR || de->d_type == DT_UNKNOWN) {
            de->d_type = DT_LNK;
        }
    }
    return de;
}

DIR *opendir(const char *name) {
    patch_linux_v4l2_memory();

    if (in_shim) {
        if (!real_opendir) real_opendir = (DIR *(*)(const char *))dlsym(RTLD_NEXT, "opendir");
        return real_opendir ? real_opendir(name) : NULL;
    }

    in_shim = 1;
    if (!real_opendir) {
        real_opendir = (DIR *(*)(const char *))dlsym(RTLD_NEXT, "opendir");
    }

    if (name) {
        if (strcmp(name, "/sys/class/video4linux") == 0) {
            ensure_video4linux_tree();
            DIR *d = real_opendir ? real_opendir("/tmp/video4linux") : NULL;
            in_shim = 0;
            return d;
        } else if (strncmp(name, "/dev/v4l/by-id", 14) == 0 && access(name, F_OK) != 0) {
            ensure_video4linux_tree();
            DIR *d = real_opendir ? real_opendir("/tmp/v4l/by-id") : NULL;
            in_shim = 0;
            return d;
        } else if (strncmp(name, "/dev/v4l/by-path", 16) == 0 && access(name, F_OK) != 0) {
            ensure_video4linux_tree();
            DIR *d = real_opendir ? real_opendir("/tmp/v4l/by-path") : NULL;
            in_shim = 0;
            return d;
        }
    }

    DIR *d = real_opendir ? real_opendir(name) : NULL;
    in_shim = 0;
    return d;
}

char *realpath(const char *path, char *resolved_path) {
    if (in_shim) {
        if (!real_realpath) real_realpath = (char *(*)(const char *, char *))dlsym(RTLD_NEXT, "realpath");
        return real_realpath ? real_realpath(path, resolved_path) : NULL;
    }

    in_shim = 1;
    if (!real_realpath) {
        real_realpath = (char *(*)(const char *, char *))dlsym(RTLD_NEXT, "realpath");
    }

    if (path) {
        if (strncmp(path, "/sys/class/video4linux", 22) == 0) {
            ensure_video4linux_tree();
            char redirected[128];
            snprintf(redirected, sizeof(redirected), "/tmp/video4linux%s", path + 22);
            char *res = real_realpath ? real_realpath(redirected, resolved_path) : NULL;
            in_shim = 0;
            return res;
        } else if (strncmp(path, "/dev/v4l/by-id/", 15) == 0 && access(path, F_OK) != 0) {
            ensure_video4linux_tree();
            char redirected[128];
            snprintf(redirected, sizeof(redirected), "/tmp/v4l/by-id/%s", path + 15);
            char *res = real_realpath ? real_realpath(redirected, resolved_path) : NULL;
            in_shim = 0;
            return res;
        } else if (strncmp(path, "/dev/v4l/by-path/", 17) == 0 && access(path, F_OK) != 0) {
            ensure_video4linux_tree();
            char redirected[128];
            snprintf(redirected, sizeof(redirected), "/tmp/v4l/by-path/%s", path + 17);
            char *res = real_realpath ? real_realpath(redirected, resolved_path) : NULL;
            in_shim = 0;
            return res;
        }
    }

    char *res = real_realpath ? real_realpath(path, resolved_path) : NULL;
    in_shim = 0;
    return res;
}

int access(const char *pathname, int mode) {
    if (in_shim) {
        if (!real_access) real_access = (int (*)(const char *, int))dlsym(RTLD_NEXT, "access");
        return real_access ? real_access(pathname, mode) : -1;
    }

    in_shim = 1;
    if (!real_access) {
        real_access = (int (*)(const char *, int))dlsym(RTLD_NEXT, "access");
    }

    if (pathname) {
        if (strncmp(pathname, "/sys/class/video4linux", 22) == 0) {
            ensure_video4linux_tree();
            char redirected[128];
            snprintf(redirected, sizeof(redirected), "/tmp/video4linux%s", pathname + 22);
            int res = real_access ? real_access(redirected, mode) : -1;
            in_shim = 0;
            return res;
        } else if (strncmp(pathname, "/dev/v4l/by-id/", 15) == 0 && real_access(pathname, mode) != 0) {
            ensure_video4linux_tree();
            char redirected[128];
            snprintf(redirected, sizeof(redirected), "/tmp/v4l/by-id/%s", pathname + 15);
            int res = real_access ? real_access(redirected, mode) : -1;
            in_shim = 0;
            return res;
        } else if (strncmp(pathname, "/dev/v4l/by-path/", 17) == 0 && real_access(pathname, mode) != 0) {
            ensure_video4linux_tree();
            char redirected[128];
            snprintf(redirected, sizeof(redirected), "/tmp/v4l/by-path/%s", pathname + 17);
            int res = real_access ? real_access(redirected, mode) : -1;
            in_shim = 0;
            return res;
        }
    }

    int res = real_access ? real_access(pathname, mode) : -1;
    in_shim = 0;
    return res;
}

FILE *fopen(const char *pathname, const char *mode) {
    if (in_shim) {
        if (!real_fopen) real_fopen = (FILE *(*)(const char *, const char *))dlsym(RTLD_NEXT, "fopen");
        return real_fopen ? real_fopen(pathname, mode) : NULL;
    }

    in_shim = 1;
    if (!real_fopen) {
        real_fopen = (FILE *(*)(const char *, const char *))dlsym(RTLD_NEXT, "fopen");
    }

    if (pathname) {
        if (strncmp(pathname, "/sys/class/video4linux", 22) == 0) {
            ensure_video4linux_tree();
            char redirected[128];
            snprintf(redirected, sizeof(redirected), "/tmp/video4linux%s", pathname + 22);
            FILE *f = real_fopen ? real_fopen(redirected, mode) : NULL;
            in_shim = 0;
            return f;
        } else if (strncmp(pathname, "/dev/v4l/by-id/", 15) == 0 && access(pathname, F_OK) != 0) {
            ensure_video4linux_tree();
            char redirected[128];
            snprintf(redirected, sizeof(redirected), "/tmp/v4l/by-id/%s", pathname + 15);
            FILE *f = real_fopen ? real_fopen(redirected, mode) : NULL;
            in_shim = 0;
            return f;
        } else if (strncmp(pathname, "/dev/v4l/by-path/", 17) == 0 && access(pathname, F_OK) != 0) {
            ensure_video4linux_tree();
            char redirected[128];
            snprintf(redirected, sizeof(redirected), "/tmp/v4l/by-path/%s", pathname + 17);
            FILE *f = real_fopen ? real_fopen(redirected, mode) : NULL;
            in_shim = 0;
            return f;
        }
    }

    FILE *f = real_fopen ? real_fopen(pathname, mode) : NULL;
    in_shim = 0;
    return f;
}

static void notify_bridge_wake(void) {
    int fd = open("/tmp/.xrdp-camera-wake", O_WRONLY | O_CREAT | O_NONBLOCK, 0666);
    if (fd >= 0) close(fd);
}

static void notify_bridge_active(const char *dev) {
    if (dev) {
        char canonical[PATH_MAX];
        const char *real_dev = realpath(dev, canonical) ? canonical : dev;
        if (strstr(real_dev, "video")) {
            int fd = open("/tmp/.xrdp-camera-active", O_WRONLY | O_CREAT | O_TRUNC, 0666);
            if (fd >= 0) {
                write(fd, real_dev, strlen(real_dev));
                close(fd);
            }
        }
    }
    notify_bridge_wake();
}

int v4l2_open(const char *file, int oflag, ...) {
    mode_t mode = 0;
    if (oflag & O_CREAT) {
        va_list ap;
        va_start(ap, oflag);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }

    patch_linux_v4l2_memory();

    if (!real_v4l2_open) {
        real_v4l2_open = (int (*)(const char *, int, ...))dlsym(RTLD_NEXT, "v4l2_open");
        if (!real_v4l2_open) {
            void *h = dlopen("libv4l2.so.0", RTLD_LAZY);
            if (h) real_v4l2_open = (int (*)(const char *, int, ...))dlsym(h, "v4l2_open");
        }
    }

    const char *target = file;
    char redirected[128];
    if (file && strncmp(file, "/dev/v4l/by-id/", 15) == 0 && access(file, F_OK) != 0) {
        ensure_video4linux_tree();
        snprintf(redirected, sizeof(redirected), "/tmp/v4l/by-id/%s", file + 15);
        target = redirected;
    } else if (file && strncmp(file, "/dev/v4l/by-path/", 17) == 0 && access(file, F_OK) != 0) {
        ensure_video4linux_tree();
        snprintf(redirected, sizeof(redirected), "/tmp/v4l/by-path/%s", file + 17);
        target = redirected;
    } else if (!target || target[0] == '\0') {
        target = get_default_v4l2_device();
    }

    int fd;
    if (!real_v4l2_open) {
        fd = open(target, oflag, mode);
    } else {
        fd = real_v4l2_open(target, oflag, mode);
    }
    fprintf(stderr, "[libobs-v4l2-shim] v4l2_open(\"%s\", oflag=0x%x) = %d\n", target ? target : "(null)", oflag, fd);
    if (fd >= 0) {
        notify_bridge_active(target);
    }
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
    notify_bridge_wake();
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
        cap->capabilities |= V4L2_CAP_VIDEO_CAPTURE;
        cap->device_caps |= V4L2_CAP_VIDEO_CAPTURE;
        if (cap->card[0] == '\0') {
            snprintf((char *)cap->card, sizeof(cap->card), "XRDP Camera");
        }
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
        if (ret < 0 && (request == VIDIOC_G_FMT || request == VIDIOC_S_FMT || request == VIDIOC_REQBUFS || request == VIDIOC_STREAMON)) {
            for (int retry = 0; retry < 25 && ret < 0; retry++) {
                notify_bridge_wake();
                usleep(40000);
                ret = real_v4l2_ioctl(fd, request, arg);
            }
        }
    } else {
        ret = ioctl(fd, request, arg);
        if (ret < 0 && (request == VIDIOC_G_FMT || request == VIDIOC_S_FMT || request == VIDIOC_REQBUFS || request == VIDIOC_STREAMON)) {
            for (int retry = 0; retry < 25 && ret < 0; retry++) {
                notify_bridge_wake();
                usleep(40000);
                ret = ioctl(fd, request, arg);
            }
        }
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
    if (ret < 0 && (request == VIDIOC_G_FMT || request == VIDIOC_S_FMT || request == VIDIOC_REQBUFS || request == VIDIOC_STREAMON)) {
        for (int retry = 0; retry < 25 && ret < 0; retry++) {
            notify_bridge_wake();
            usleep(40000);
            ret = real_ioctl(fd, request, arg);
        }
    }
    return handle_v4l2_ioctl_result(fd, request, arg, ret);
}
