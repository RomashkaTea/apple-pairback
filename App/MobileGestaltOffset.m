#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <string.h>

// Lara's lookup with bounds and exact-match checks. A failure never supplies an offset.
long pb_mobilegestalt_offset(const char *key) {
    if (!key || !*key) return -1;
    const char *imagePath = "/usr/lib/libMobileGestalt.dylib";
    if (!dlopen(imagePath, RTLD_LAZY | RTLD_GLOBAL)) return -1;

    const struct mach_header_64 *header = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strcmp(name, imagePath) == 0) {
            header = (const struct mach_header_64 *)_dyld_get_image_header(i);
            break;
        }
    }
    if (!header) return -1;

    unsigned long cstringLength = 0;
    const char *cstrings = getsectiondata(header, "__TEXT", "__cstring", &cstringLength);
    if (!cstrings) return -1;
    const char *matchingString = NULL;
    const size_t keyLength = strlen(key);
    for (size_t pos = 0; pos < cstringLength;) {
        size_t remaining = cstringLength - pos;
        size_t length = strnlen(cstrings + pos, remaining);
        if (length == remaining) return -1;
        if (length == keyLength && memcmp(cstrings + pos, key, length) == 0) {
            if (matchingString) return -1;
            matchingString = cstrings + pos;
        }
        pos += length + 1;
    }
    if (!matchingString) return -1;

    unsigned long constLength = 0;
    const uint8_t *constants = getsectiondata(header, "__AUTH_CONST", "__const", &constLength);
    if (!constants) constants = getsectiondata(header, "__DATA_CONST", "__const", &constLength);
    if (!constants || constLength < 0x9c) return -1;

    long result = -1;
    for (size_t pos = 0; pos + 0x9c <= constLength; pos += sizeof(uintptr_t)) {
        uintptr_t pointer = 0;
        memcpy(&pointer, constants + pos, sizeof(pointer));
        if (pointer != (uintptr_t)matchingString) continue;
        uint16_t encodedOffset = 0;
        memcpy(&encodedOffset, constants + pos + 0x9a, sizeof(encodedOffset));
        long offset = ((long)encodedOffset) << 3;
        if (result >= 0 && result != offset) return -1;
        result = offset;
    }
    return result;
}
