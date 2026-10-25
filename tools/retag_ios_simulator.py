#!/usr/bin/env python3
"""Copies an arm64 iOS device static library, retagging it for the iOS Simulator.

Usage: retag_ios_simulator.py <device libfoo.a> <output libfoo.a>

Godot 4.7.2's official iOS template ships an x86_64-only simulator libgodot.a,
and the iOS 27 Simulator runs arm64 only. arm64 device and arm64 simulator code
are the same machine code; the linker only tells them apart by the platform in
each object's LC_BUILD_VERSION load command (2 = iOS, 7 = iOS Simulator). This
rewrites that one field in every object and changes nothing else, so member
sizes and the archive's symbol table stay valid. Test harness only: never ship
the result.
"""
import struct
import sys

LC_BUILD_VERSION = 0x32
PLATFORM_IOS = 2
PLATFORM_IOSSIMULATOR = 7
MH_MAGIC_64 = 0xFEEDFACF
AR_MAGIC = b"!<arch>\n"
AR_HEADER_SIZE = 60


def retag_object(data: bytearray, start: int) -> bool:
    """Retags one Mach-O object; returns False when it has no iOS build version."""
    ncmds = struct.unpack_from("<I", data, start + 16)[0]
    command = start + 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, command)
        if cmd == LC_BUILD_VERSION:
            platform = struct.unpack_from("<I", data, command + 8)[0]
            if platform == PLATFORM_IOS:
                struct.pack_into("<I", data, command + 8, PLATFORM_IOSSIMULATOR)
                return True
            return platform == PLATFORM_IOSSIMULATOR
        command += cmdsize
    return False


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.splitlines()[2], file=sys.stderr)
        return 2
    with open(sys.argv[1], "rb") as source:
        data = bytearray(source.read())
    if not data.startswith(AR_MAGIC):
        print(f"retag_ios_simulator: {sys.argv[1]} is not an ar archive", file=sys.stderr)
        return 1

    objects = 0
    untagged = []
    member = len(AR_MAGIC)
    while member < len(data):
        header = data[member:member + AR_HEADER_SIZE]
        name = header[0:16].decode("ascii").strip()
        size = int(header[48:58].decode("ascii").strip())
        body = member + AR_HEADER_SIZE
        # BSD archives store long names ("#1/<length>") at the start of the body.
        name_length = int(name[3:]) if name.startswith("#1/") else 0
        content = body + name_length
        end = body + size
        if end - content >= 32 and struct.unpack_from("<I", data, content)[0] == MH_MAGIC_64:
            objects += 1
            if not retag_object(data, content):
                untagged.append(data[body:content].rstrip(b"\0").decode("utf-8", "replace") or name)
        member = end + (end & 1)

    if untagged:
        print(f"retag_ios_simulator: no iOS LC_BUILD_VERSION in {', '.join(untagged[:5])}", file=sys.stderr)
        return 1
    with open(sys.argv[2], "wb") as output:
        output.write(data)
    print(f"retag_ios_simulator: retagged {objects} objects")
    return 0


if __name__ == "__main__":
    sys.exit(main())
