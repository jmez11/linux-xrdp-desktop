#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <sys/types.h>

/*
 * libobs-v4l2-shim:
 * Compatibility shim for OBS Studio running inside Docker / XRDP.
 *
 * 1. sysfs emulation:
 *    OBS Studio's Linux V4L2 plugin enumerates devices by scanning
 *    /sys/class/video4linux. In container environments where sysfs is masked
 *    or does not contain video4linux, opendir() intercepts this path and
 *    returns an emulated directory populated with entries for active /dev/video* nodes.
 *
 * 2. Empty device_id safety:
 *    When a user creates a new V4L2 capture source via the OBS UI, libobs creates
 *    the source with an empty settings container before presenting the properties
 *    dialog. The V4L2 plugin unconditionally invokes v4l2_init("") which fails to
 *    open an empty path and aborts, causing libobs to dereference uninitialized frame
 *    buffers and crash with a segmentation fault. v4l2_open() intercepts empty or NULL
 *    paths and defaults them to the first accessible /dev/video* node.
 */

static DIR *(*real_opendir)(const char *name) = NULL;
static int (*real_v4l2_open)(const char *file, int oflag, ...) = NULL;

__attribute__((constructor))
static void init_shim(void) {
    real_opendir = dlsym(RTLD_NEXT, "opendir");
    real_v4l2_open = dlsym(RTLD_NEXT, "v4l2_open");
    if (!real_v4l2_open) {
        void *h = dlopen("libv4l2.so.0", RTLD_LAZY);
        if (h) real_v4l2_open = dlsym(h, "v4l2_open");
    }
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
        mkdir("/tmp/video4linux", 0755);
        for (int i = 0; i < 64; i++) {
            char devpath[32];
            snprintf(devpath, sizeof(devpath), "/dev/video%d", i);
            if (access(devpath, F_OK) == 0) {
                char nodepath[64];
                snprintf(nodepath, sizeof(nodepath), "/tmp/video4linux/video%d", i);
                mkdir(nodepath, 0755);
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
    return real_v4l2_open(target, oflag, mode);
}
