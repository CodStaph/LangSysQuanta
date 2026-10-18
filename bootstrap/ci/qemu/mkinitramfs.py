#!/usr/bin/env python3
"""mkinitramfs.py — build cpio/newc initramfs images without cpio or root.

Why a bespoke writer instead of `cpio` / `tar --format=newc`:

  * Git Bash (MSYS) ships no `cpio` at all.
  * `bsdtar --format=newc` on Windows cannot record POSIX permissions, so
    /init and /bin/bash would come out non-executable and the guest would not
    boot.
  * We never need the rootfs on disk: tarball members are streamed straight
    into the cpio archive with their original modes, so a ~30 MB rootfs is
    turned into an image in a few seconds on any host.

The image is written as newc. A trailing `.gz` on --out gzips it, anything
else is written raw so several layers can be concatenated cheaply: the Linux
kernel walks a cpio archive to its TRAILER!!! and keeps going, so
`cat base.cpio repo.cpio | gzip` is a valid layered initramfs. This is how the
base rootfs is cached while the small repo layer is rebuilt on every run.

Examples
--------
  # base layer: Ubuntu rootfs + /init + a readelf shim + console devices
  mkinitramfs.py --tar ubuntu-base.tar.gz \
                 --exclude usr/share/doc \
                 --add-file bootstrap/ci/qemu/init:/init:0755 \
                 --chardev /dev/console:5:1:0600 \
                 --out base.cpio

  # repo layer: the working tree mounted at /repo
  mkinitramfs.py --dir bootstrap:/repo/bootstrap --out repo.cpio
"""

import argparse
import gzip
import os
import re
import stat
import sys
import tarfile

MAGIC = b"070701"
HEADER_SIZE = 110  # 6 byte magic + 13 * 8 hex fields


class Entry:
    """One cpio member: a path, its full mode (type bits included) and data."""

    __slots__ = ("name", "mode", "data", "rdev")

    def __init__(self, name, mode, data=b"", rdev=(0, 0)):
        self.name = name
        self.mode = mode
        self.data = data
        self.rdev = rdev


def normalize(name):
    """cpio names are relative and never start with './' or '/'."""
    name = name.replace("\\", "/")
    while name.startswith("./"):
        name = name[2:]
    name = name.strip("/")
    return "" if name == "." else name


def is_excluded(name, patterns):
    for pat in patterns:
        pat = pat.strip("/")
        if not pat:
            continue
        if name == pat or name.startswith(pat + "/"):
            return True
    return False


def local_mode(name):
    """Permission bits for files that come from the working tree.

    The host filesystem (Windows) cannot express them, so use the repository
    convention: shell entry points and build outputs are executable, the rest
    is plain data.
    """
    if name.startswith("repo/bootstrap/build/"):
        return 0o755
    if name == "repo/bootstrap/seed/seed":
        return 0o755
    if name.endswith(".sh"):
        return 0o755
    return 0o644


def load_tar(path, entries, excludes, what):
    """Merge a rootfs tarball into `entries`. Later layers win."""
    print(f"mkinitramfs: layer {what}: {path}", file=sys.stderr)
    with tarfile.open(path, "r:*") as tf:
        for member in tf:
            name = normalize(member.name)
            if not name or is_excluded(name, excludes):
                continue
            if member.isdir():
                if not name:
                    continue
                entries[name] = Entry(name, stat.S_IFDIR | 0o755)
            elif member.issym():
                entries[name] = Entry(
                    name, stat.S_IFLNK | 0o777, member.linkname.encode()
                )
            elif member.islnk():
                target = entries.get(normalize(member.linkname))
                if target is not None and stat.S_ISREG(target.mode):
                    entries[name] = Entry(name, target.mode, target.data)
            elif member.isfile():
                handle = tf.extractfile(member)
                data = handle.read() if handle is not None else b""
                mode = (member.mode & 0o777) or 0o644
                entries[name] = Entry(name, stat.S_IFREG | mode, data)
            # block/char/fifo members are ignored: the kernel creates the
            # handful of device nodes we need from --chardev.


def load_dir(src, prefix, entries, excludes):
    """Recursively add a host directory under `prefix` inside the image."""
    src = os.path.abspath(src)
    if not os.path.isdir(src):
        raise SystemExit(f"mkinitramfs: not a directory: {src}")
    print(f"mkinitramfs: layer dir: {src} -> /{prefix}", file=sys.stderr)
    for root, dirs, files in os.walk(src):
        dirs.sort()
        files.sort()
        rel_root = os.path.relpath(root, src).replace("\\", "/")
        if rel_root == ".":
            rel_root = ""
        for d in list(dirs):
            rel = f"{rel_root}/{d}" if rel_root else d
            name = f"{prefix}/{rel}" if prefix else rel
            if is_excluded(name, excludes) or is_excluded(rel, excludes):
                dirs.remove(d)
                continue
            entries[name] = Entry(name, stat.S_IFDIR | 0o755)
        for fn in files:
            rel = f"{rel_root}/{fn}" if rel_root else fn
            name = f"{prefix}/{rel}" if prefix else rel
            if is_excluded(name, excludes) or is_excluded(rel, excludes):
                continue
            full = os.path.join(root, fn)
            if os.path.islink(full):
                entries[name] = Entry(
                    name, stat.S_IFLNK | 0o777, os.readlink(full).encode()
                )
                continue
            with open(full, "rb") as fh:
                data = fh.read()
            entries[name] = Entry(name, stat.S_IFREG | local_mode(name), data)


def parse_add_file(spec):
    """SRC:DEST:MODE — parsed from the right so 'D:/x' style paths work."""
    parts = spec.rsplit(":", 2)
    if len(parts) != 3:
        raise SystemExit(f"mkinitramfs: --add-file needs SRC:DEST:MODE, got: {spec}")
    src, dest, mode = parts
    return src, normalize(dest), int(mode, 8)


def parse_dir(spec):
    """LOCAL:DEST — parsed from the right so Windows drive letters work."""
    parts = spec.rsplit(":", 1)
    if len(parts) != 2:
        raise SystemExit(f"mkinitramfs: --dir needs LOCAL:DEST, got: {spec}")
    return parts[0], normalize(parts[1])


CHARDEV_RE = re.compile(r"^(.*):(\d+):(\d+):([0-7]+)$")


def parse_chardev(spec):
    m = CHARDEV_RE.match(spec)
    if not m:
        raise SystemExit(f"mkinitramfs: --chardev needs NAME:MAJ:MIN:MODE, got: {spec}")
    return normalize(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4), 8)


def ensure_parents(entries):
    """cpio members must be preceded by their parents."""
    for name in list(entries):
        parts = name.split("/")
        for i in range(1, len(parts)):
            parent = "/".join(parts[:i])
            if parent and parent not in entries:
                entries[parent] = Entry(parent, stat.S_IFDIR | 0o755)


def pad4(out, size):
    rem = size % 4
    if rem:
        out.write(b"\0" * (4 - rem))


def put(out, ino, name, mode, data=b"", rdev=(0, 0)):
    name_bytes = name.encode() + b"\0"
    nlink = 2 if stat.S_ISDIR(mode) else 1
    fields = (
        ino,
        mode,
        0,  # uid: everything is root inside the guest
        0,  # gid
        nlink,
        0,  # mtime: fixed so images are reproducible
        len(data),
        0,  # devmajor: single flat filesystem
        0,  # devminor
        rdev[0],
        rdev[1],
        len(name_bytes),
        0,  # check
    )
    out.write(MAGIC + b"".join(b"%08X" % (f & 0xFFFFFFFF) for f in fields))
    out.write(name_bytes)
    pad4(out, HEADER_SIZE + len(name_bytes))
    out.write(data)
    pad4(out, len(data))


def write_cpio(entries, out):
    ensure_parents(entries)
    # Parents before children; '.' is the root directory entry.
    ordered = sorted(entries.values(), key=lambda e: (e.name.count("/"), e.name))
    put(out, 1, ".", stat.S_IFDIR | 0o755)
    ino = 2
    for entry in ordered:
        put(out, ino, entry.name, entry.mode, entry.data, entry.rdev)
        ino += 1
    put(out, 0, "TRAILER!!!", 0)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--tar", action="append", default=[], metavar="TARBALL",
                    help="rootfs tarball to merge (may be repeated, later wins)")
    ap.add_argument("--dir", action="append", default=[], metavar="LOCAL:DEST",
                    help="host directory to add under DEST (may be repeated)")
    ap.add_argument("--add-file", action="append", default=[], metavar="SRC:DEST:MODE",
                    help="add a single host file, MODE in octal (may be repeated)")
    ap.add_argument("--chardev", action="append", default=[],
                    metavar="NAME:MAJ:MIN:MODE",
                    help="create a character device node (may be repeated)")
    ap.add_argument("--exclude", action="append", default=[], metavar="PATH",
                    help="skip this path and its subtree (may be repeated)")
    ap.add_argument("--out", required=True, metavar="FILE",
                    help="cpio image to write; a .gz suffix gzips it")
    args = ap.parse_args(argv)

    entries = {}
    for tarball in args.tar:
        load_tar(tarball, entries, args.exclude, "tar")
    for spec in args.dir:
        src, dest = parse_dir(spec)
        load_dir(src, dest, entries, args.exclude)
    for spec in args.add_file:
        src, dest, mode = parse_add_file(spec)
        with open(src, "rb") as fh:
            data = fh.read()
        entries[dest] = Entry(dest, stat.S_IFREG | mode, data)
    for spec in args.chardev:
        name, major, minor, mode = parse_chardev(spec)
        entries[name] = Entry(name, stat.S_IFCHR | mode, b"", (major, minor))

    if not entries:
        raise SystemExit("mkinitramfs: empty image")

    payload_size = sum(len(e.data) for e in entries.values())
    use_gzip = args.out.endswith(".gz")
    tmp = args.out + ".part"
    with open(tmp, "wb") as raw:
        if use_gzip:
            with gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=6, mtime=0) as gz:
                write_cpio(entries, gz)
        else:
            write_cpio(entries, raw)
    os.replace(tmp, args.out)

    out_size = os.path.getsize(args.out)
    print(
        f"mkinitramfs: {len(entries)} entries, {payload_size / 1048576:.1f} MiB payload "
        f"-> {args.out} ({out_size / 1048576:.1f} MiB "
        f"{'gzip' if use_gzip else 'raw'})",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
