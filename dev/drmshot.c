// drmshot: writes the framebuffer on screen as PPM (stdout), even while a KMS app runs. Needs root.
#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <drm/drm_fourcc.h>

int main(int argc, char** argv) {
    int fd = open(argc > 1 ? argv[1] : "/dev/dri/card0", O_RDWR);
    if (fd < 0) { perror("open"); return 1; }
    uint32_t crtcs[8];
    struct drm_mode_card_res res = {0};
    res.crtc_id_ptr = (uintptr_t)crtcs; res.count_crtcs = 8;
    if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res)) { perror("res"); return 1; }
    for (unsigned i = 0; i < res.count_crtcs && i < 8; i++) {
        struct drm_mode_crtc c = { .crtc_id = crtcs[i] };
        if (ioctl(fd, DRM_IOCTL_MODE_GETCRTC, &c) || !c.fb_id) continue;
        struct drm_mode_fb_cmd2 fb = { .fb_id = c.fb_id };
        if (ioctl(fd, DRM_IOCTL_MODE_GETFB2, &fb)) { perror("getfb2"); return 1; }
        struct drm_mode_map_dumb map = { .handle = fb.handles[0] };
        if (ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map)) { perror("map"); return 1; }
        size_t size = (size_t)fb.pitches[0] * fb.height;
        uint8_t* p = mmap(0, size, PROT_READ, MAP_SHARED, fd, map.offset);
        if (p == MAP_FAILED) { perror("mmap"); return 1; }
        fprintf(stderr, "%ux%u fmt %.4s pitch %u\n", fb.width, fb.height, (char*)&fb.pixel_format, fb.pitches[0]);
        printf("P6\n%u %u\n255\n", fb.width, fb.height);
        for (uint32_t y = 0; y < fb.height; y++) {
            uint8_t* row = p + (size_t)y * fb.pitches[0];
            for (uint32_t x = 0; x < fb.width; x++) {
                uint8_t px[3];
                if (fb.pixel_format == DRM_FORMAT_RGB565) {
                    uint16_t v = ((uint16_t*)row)[x];
                    px[0] = (v >> 11) << 3; px[1] = ((v >> 5) & 63) << 2; px[2] = (v & 31) << 3;
                } else {
                    uint8_t* q = row + x * 4;
                    px[0] = q[2]; px[1] = q[1]; px[2] = q[0];
                }
                fwrite(px, 1, 3, stdout);
            }
        }
        return 0;
    }
    fprintf(stderr, "no active crtc\n");
    return 1;
}
