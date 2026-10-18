#!/usr/bin/env bash
# run-qemu.sh — run the Linux bootstrap CI inside a local QEMU VM.
#
# Why this exists
# ---------------
# The project's CI has to *execute* the bare x86_64 ELF binaries that seed
# emits, which needs a real Linux kernel. Hosts without VT-x/SLAT (nested
# cloud VMs, Windows 10 1809) cannot run VirtualBox, Hyper-V, WSL2 or Docker
# Desktop, so this script uses QEMU's pure software accelerator (TCG): no
# virtualization extensions, no admin rights, no kernel driver, no reboot.
#
# Division of labour
# ------------------
#   host  : download a Linux kernel + rootfs, cross-compile seed.c into a
#           freestanding x86_64 Linux ELF with the same flags build.sh uses on
#           Linux (`clang --target=x86_64-unknown-linux-gnu -nostdlib ...`).
#   guest : bootstrap/build.sh turns that seed into every test binary with the
#           prebuilt seed (SKIP_SEED_CC=1), then run-linux.sh and run-stage1.sh
#           execute and assert on them — including the stage2 == stage3 fixed
#           point. So everything below the seed compiler runs on Linux.
#
# Everything is cached in .qemu-cache/ and the working tree is never touched
# (the guest gets a copy at /repo inside the initramfs).
#
# Usage
# -----
#   ./bootstrap/ci/run-qemu.sh          # first run downloads ~250 MiB
#   QEMU_TIMEOUT=1800 ./bootstrap/ci/run-qemu.sh
#
# Environment
# -----------
#   QEMU_CACHE      cache + scratch dir (default: <repo>/.qemu-cache)
#   QEMU_SYSTEM     existing qemu-system-x86_64 binary to use
#   QEMU_TIMEOUT    seconds before the VM is killed (default: 1200)
#   QEMU_MEM        guest RAM in MiB (default: 1024)
#   QEMU_SMP        guest vCPUs (default: 2)
#   QEMU_ACCEL      -accel value (default: tcg,thread=multi)
#   QEMU_FORCE=1    use the VM even on a native Linux host
#   CC              host C compiler for the cross build (default: clang)
#   KERNEL_URL      kernel image to boot (default: Alpine netboot vmlinuz-virt)
#   ROOTFS_URL      rootfs tarball (default: Ubuntu 24.04 base)
#   QEMU_URL_BASE   where to look for the Windows QEMU installer
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CACHE="${QEMU_CACHE:-$ROOT/.qemu-cache}"
TIMEOUT="${QEMU_TIMEOUT:-1200}"
MEM="${QEMU_MEM:-1024}"
SMP="${QEMU_SMP:-2}"
ACCEL="${QEMU_ACCEL:-tcg,thread=multi}"
KERNEL_URL="${KERNEL_URL:-https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/netboot/vmlinuz-virt}"
ROOTFS_URL="${ROOTFS_URL:-https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz}"
QEMU_URL_BASE="${QEMU_URL_BASE:-https://qemu.weilnetz.de/w64/}"

# Diagnostics go to stderr: find_qemu/install_qemu_windows return the qemu path
# on stdout, so anything printed there would corrupt command substitution.
msg() { printf 'run-qemu: %s\n' "$*" >&2; }
die() { printf 'run-qemu: %s\n' "$*" >&2; exit 1; }

host="$(uname -s 2>/dev/null || echo unknown)"
case "$host" in
    *MINGW* | *MSYS* | *CYGWIN* | *Windows*) PLATFORM=windows ;;
    Linux*) PLATFORM=linux ;;
    Darwin*) PLATFORM=darwin ;;
    *) PLATFORM=unknown ;;
esac

if [ "$PLATFORM" = linux ] && [ "${QEMU_FORCE:-0}" != "1" ]; then
    msg "native Linux host: running the CI directly (QEMU_FORCE=1 for the VM)"
    bash "$ROOT/bootstrap/ci/run-linux.sh"
    exec bash "$ROOT/bootstrap/ci/run-stage1.sh"
fi

DL="$CACHE/dl"
WORK="$CACHE/work"
mkdir -p "$DL" "$WORK"

PY="$(command -v python || command -v python3 || true)"
[ -n "$PY" ] || die "python not found (needed by bootstrap/ci/qemu/mkinitramfs.py)"

fetch() { # url dest
    local url="$1" dest="$2"
    if [ -s "$dest" ]; then
        msg "cached $(basename "$dest")"
        return 0
    fi
    msg "downloading $url"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$dest.part" "$url" ||
        die "download failed: $url"
    mv "$dest.part" "$dest"
}

# Native Windows programs (qemu, clang, the NSIS installer, anaconda python)
# cannot read MSYS paths like /d/foo, so hand them Windows paths explicitly.
wp() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

# MSYS additionally rewrites any argument that *looks* like a path list, which
# turns `SRC:DEST:MODE` into `SRC;D:\DEST;MODE` and `file:qemu.log` into
# `file;qemu.log`. Every native-program call is therefore prefixed with
# MSYS2_ARG_CONV_EXCL='*' and passes already-converted paths.

install_qemu_windows() {
    local bin="$CACHE/qemu/qemu-system-x86_64.exe"
    [ -x "$bin" ] && { printf '%s' "$bin"; return 0; }

    msg "QEMU not found, installing a portable copy into $CACHE/qemu"
    local listing latest
    listing="$(curl -fsSL --connect-timeout 20 "$QEMU_URL_BASE" || true)"
    latest="$(printf '%s' "$listing" |
        grep -oE 'qemu-w64-setup-[0-9]+\.exe' | sort -u | tail -1)"
    [ -n "$latest" ] || die "cannot find a qemu-w64-setup-*.exe at $QEMU_URL_BASE"

    fetch "$QEMU_URL_BASE$latest" "$DL/$latest"
    mkdir -p "$CACHE/qemu"
    local wdir
    wdir="$(wp "$CACHE/qemu")"
    case "$wdir" in
        *" "*) die "QEMU_CACHE must not contain spaces (NSIS /D=): $wdir" ;;
    esac
    msg "installing QEMU silently: $latest"
    # NSIS: /S is silent, /D= must be last and unquoted.
    MSYS2_ARG_CONV_EXCL='*' "$(wp "$DL/$latest")" /S "/D=$wdir" ||
        die "silent install failed; install QEMU yourself and set QEMU_SYSTEM=<path>"
    [ -x "$bin" ] || die "qemu-system-x86_64.exe missing after install: $bin"
    printf '%s' "$bin"
}

find_qemu() {
    if [ -n "${QEMU_SYSTEM:-}" ]; then
        [ -x "$QEMU_SYSTEM" ] || die "QEMU_SYSTEM is not executable: $QEMU_SYSTEM"
        printf '%s' "$QEMU_SYSTEM"
        return 0
    fi
    case "$PLATFORM" in
        windows) install_qemu_windows ;;
        *)
            command -v qemu-system-x86_64 >/dev/null 2>&1 ||
                die "qemu-system-x86_64 not found (install QEMU first)"
            command -v qemu-system-x86_64
            ;;
    esac
}

# Copy the working tree (source only) and cross-compile seed for Linux.
build_seed() {
    local repo="$WORK/repo"
    rm -rf "$WORK/repo"
    mkdir -p "$repo"
    msg "staging working tree -> $repo"
    (
        cd "$ROOT" &&
            tar -cf - \
                --exclude=bootstrap/build \
                --exclude=bootstrap/seed/seed \
                --exclude=bootstrap/seed/seed.exe \
                bootstrap
    ) | (cd "$repo" && tar -xf -)

    # This checkout has core.autocrlf=true, but a real Linux CI checkout (and
    # the .gitattributes eol=lf rule) is LF. A CRLF run-linux.sh fails at
    # `set -o pipefail\r`, so normalize text files in the snapshot while
    # leaving binaries (seed ELF, images) untouched.
    msg "normalizing line endings (CRLF -> LF) in the snapshot"
    REPO_ROOT="$(wp "$repo")" "$PY" - <<'PY'
import os
import sys

root = os.environ["REPO_ROOT"]
changed = 0
for dirpath, _, filenames in os.walk(root):
    for filename in filenames:
        path = os.path.join(dirpath, filename)
        try:
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError:
            continue
        if b"\0" in data or b"\r\n" not in data:
            continue
        with open(path, "wb") as handle:
            handle.write(data.replace(b"\r\n", b"\n"))
        changed += 1
print(f"run-qemu: normalized {changed} text files", file=sys.stderr)
PY

    local cc="${CC:-clang}"
    command -v "$cc" >/dev/null 2>&1 ||
        die "host C compiler '$cc' not found (set CC=/path/to/clang)"
    msg "cross-compiling seed.c -> x86_64 Linux ELF with $cc"
    # Same flags as build.sh's Linux branch, plus an explicit ELF target so the
    # MSYS/macOS clang emits a Linux binary instead of a PE/Mach-O one.
    MSYS2_ARG_CONV_EXCL='*' "$cc" --target=x86_64-unknown-linux-gnu \
        -nostdlib -static -fno-pic -fno-stack-protector -fno-builtin -O2 \
        "$(wp "$repo/bootstrap/seed/seed.c")" -o "$(wp "$repo/bootstrap/seed/seed")" ||
        die "cross-compile failed"
    chmod +x "$repo/bootstrap/seed/seed"
}

build_initramfs() {
    local mk="$ROOT/bootstrap/ci/qemu/mkinitramfs.py"
    local base="$CACHE/base.cpio"
    local repo="$CACHE/repo.cpio"
    local image="$CACHE/initramfs.cpio.gz"

    if [ ! -s "$base" ]; then
        msg "building base initramfs (rootfs + /init + readelf shim)"
        MSYS2_ARG_CONV_EXCL='*' "$PY" "$(wp "$mk")" \
            --tar "$(wp "$DL/$(basename "$ROOTFS_URL")")" \
            --exclude usr/share/doc \
            --exclude usr/share/man \
            --exclude usr/share/locale \
            --exclude usr/share/info \
            --exclude var/lib/apt \
            --exclude var/cache \
            --add-file "$(wp "$ROOT/bootstrap/ci/qemu/init"):/init:0755" \
            --add-file "$(wp "$ROOT/bootstrap/ci/qemu/readelf-shim"):/usr/local/bin/readelf:0755" \
            --chardev /dev/console:5:1:0600 \
            --chardev /dev/null:1:3:0666 \
            --chardev /dev/tty:5:0:0666 \
            --chardev /dev/urandom:1:9:0666 \
            --out "$(wp "$base")"
    else
        msg "cached base.cpio"
    fi

    msg "building repo initramfs (source snapshot at /repo)"
    MSYS2_ARG_CONV_EXCL='*' "$PY" "$(wp "$mk")" \
        --dir "$(wp "$WORK/repo/bootstrap"):/repo/bootstrap" \
        --out "$(wp "$repo")"

    # QEMU does not split `-initrd a,b` here, so concatenate the layers into
    # one archive. The kernel reads a cpio image up to TRAILER!!! and continues
    # with the next one, which is exactly how layered initramfs work.
    local base_mb
    base_mb=$(( $(wc -c <"$base" | tr -d ' ') / 1048576 ))
    msg "compressing initramfs (${base_mb} MiB base layer + repo layer)"
    cat "$base" "$repo" | gzip -6 -n >"$image.part"
    mv "$image.part" "$image"
    msg "initramfs: $image"
}

# Boot the VM, stream the console, and decide the result from the log marker.
run_vm() {
    local qemu; qemu="$(wp "$1")"
    local log="$CACHE/qemu.log"
    rm -f "$log"

    msg "booting guest: -M q35 -m $MEM -smp $SMP -accel $ACCEL"
    (
        cd "$CACHE" || exit 1
        # Relative paths on purpose: QEMU resolves them against its own cwd,
        # which avoids passing any path with a drive letter to -serial/-initrd.
        exec env MSYS2_ARG_CONV_EXCL='*' "$qemu" \
            -M q35 \
            -m "$MEM" \
            -smp "$SMP" \
            -accel "$ACCEL" \
            -kernel dl/vmlinuz-virt \
            -initrd initramfs.cpio.gz \
            -append "console=ttyS0 panic=-1 quiet loglevel=4" \
            -display none \
            -serial file:qemu.log \
            -monitor none \
            -no-reboot
    ) &
    local pid=$!
    local started=$SECONDS last=0 cur

    while :; do
        if [ -f "$log" ]; then
            cur="$(wc -c <"$log" 2>/dev/null || echo 0)"
            cur="${cur//[!0-9]/}"
            if [ -n "$cur" ] && [ "$cur" -gt "$last" ]; then
                tail -c +$((last + 1)) "$log"
                last="$cur"
            fi
            if grep -q 'QEMU-GUEST: RESULT=' "$log" 2>/dev/null; then
                sleep 1
                cur="$(wc -c <"$log" 2>/dev/null || echo 0)"
                cur="${cur//[!0-9]/}"
                if [ -n "$cur" ] && [ "$cur" -gt "$last" ]; then
                    tail -c +$((last + 1)) "$log"
                fi
                break
            fi
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            msg "guest exited"
            break
        fi
        if [ $((SECONDS - started)) -gt "$TIMEOUT" ]; then
            msg "guest timed out after ${TIMEOUT}s"
            break
        fi
        sleep 1
    done

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    if grep -q 'QEMU-GUEST: RESULT=PASS' "$log" 2>/dev/null; then
        msg "PASS: Linux CI completed inside the QEMU guest"
        msg "log: $log"
        return 0
    fi

    msg "FAIL: Linux CI failed in the guest"
    msg "log: $log"
    printf '\n----- last 80 log lines -----\n' >&2
    tail -n 80 "$log" >&2 2>/dev/null || true
    return 1
}

main() {
    msg "host $host ($PLATFORM), cache $CACHE"
    fetch "$KERNEL_URL" "$DL/vmlinuz-virt"
    fetch "$ROOTFS_URL" "$DL/$(basename "$ROOTFS_URL")"
    local qemu
    qemu="$(find_qemu)"
    msg "qemu: $qemu"
    build_seed
    build_initramfs
    run_vm "$qemu"
}

main "$@"
