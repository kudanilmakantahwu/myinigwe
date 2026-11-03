#!/usr/bin/env python3
"""Build Android boot.img (legacy v0 header) untuk xiaomi-lavender.

kernel = vmlinuz + appended DTB (CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE)
Header/name/cmdline/alamat disalin dari boot.img referensi yang terbukti boot.
"""
import hashlib
import struct
import sys

REF = "/home/maf/.local/var/pmbootstrap/chroot_rootfs_xiaomi-lavender/boot/boot.img"
PAGE = 4096

def pad(b, page=PAGE):
    n = (len(b) + page - 1) // page * page
    return b + b"\x00" * (n - len(b))

def build(vmlinuz, dtb, ramdisk, out):
    kernel = open(vmlinuz, "rb").read() + open(dtb, "rb").read()
    rd = open(ramdisk, "rb").read()
    ref = bytearray(open(REF, "rb").read()[:PAGE])

    struct.pack_into("<I", ref, 8, len(kernel))
    struct.pack_into("<I", ref, 16, len(rd))
    struct.pack_into("<I", ref, 24, 0)  # second_size

    # mkbootimg-style id
    h = hashlib.sha1()
    h.update(kernel)
    h.update(rd)
    h.update(struct.pack("<III", len(kernel), len(rd), 0))
    img_id = h.digest()  # 20 bytes
    ref[576:596] = img_id
    ref[596:608] = b"\x00" * 12

    img = bytes(ref) + pad(kernel) + pad(rd)
    open(out, "wb").write(img)
    print("kernel:", len(kernel), "(vmlinuz", len(open(vmlinuz,'rb').read()), "+ dtb", len(open(dtb,'rb').read()), ")")
    print("ramdisk:", len(rd))
    print("total:", len(img), "->", out)

if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])