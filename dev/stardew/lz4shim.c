// liblwjgl_lz4 for 32-bit ARM: Stardew's P/Invokes pass pointer-sized src/dst, LWJGL's C takes jlong.
#include "lz4.h"

int Java_org_lwjgl_util_lz4_LZ4_LZ4_1compressBound(void *env, void *clazz, int inputSize)
{
    return LZ4_compressBound(inputSize);
}

int Java_org_lwjgl_util_lz4_LZ4_nLZ4_1compress_1default(void *env, void *clazz, const char *src, char *dst,
                                                        int srcSize, int dstCapacity)
{
    return LZ4_compress_default(src, dst, srcSize, dstCapacity);
}

int Java_org_lwjgl_util_lz4_LZ4_nLZ4_1decompress_1safe(void *env, void *clazz, const char *src, char *dst,
                                                       int compressedSize, int dstCapacity)
{
    return LZ4_decompress_safe(src, dst, compressedSize, dstCapacity);
}
