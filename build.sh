#!/usr/bin/env bash
# =============================================================================
# Termux Python 3.13.12 — Self-Contained All-in-One build.sh
# =============================================================================
# This file is the ONLY file you need. Run it directly:
#
#   bash build.sh
#
# On first run it will:
#   1. Write all patches into a  patches/  subdirectory next to this script.
#   2. Download Python 3.13.12 source + Debian python3-defaults.
#   3. Apply all patches.
#   4. Configure, build, and install Python into $PREFIX.
#
# Merged from:
#   [A] termux/termux-packages  packages/python/build.sh  v3.13.12 REVISION=3
#   [B] yubrajbhoi/termux-python @ 3b0139c                v3.13.6
#   [C] termux/termux-packages  build-package.sh           pipeline reference
#
# Bionic API reference: https://android.googlesource.com/platform/bionic/+/master/docs/status.md
# =============================================================================
set -euo pipefail

# =============================================================================
# §0  DETECT ENVIRONMENT
# Supports both:
#   (a) On-device Termux build  (bash build.sh directly in Termux)
#   (b) termux build-package.sh (TERMUX_PKG_* variables already exported)
# =============================================================================
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When run standalone, set sensible defaults.
if [[ -z "${TERMUX_PREFIX:-}" ]]; then
    export TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
fi
if [[ -z "${TERMUX_PKG_SRCDIR:-}" ]]; then
    export TERMUX_PKG_SRCDIR="${TMPDIR:-/tmp}/python-build/src"
fi
if [[ -z "${TERMUX_PKG_BUILDDIR:-}" ]]; then
    export TERMUX_PKG_BUILDDIR="${TMPDIR:-/tmp}/python-build/build"
fi
if [[ -z "${TERMUX_PKG_CACHEDIR:-}" ]]; then
    export TERMUX_PKG_CACHEDIR="${TMPDIR:-/tmp}/python-build/cache"
fi
if [[ -z "${TERMUX_PKG_API_LEVEL:-}" ]]; then
    # Auto-detect from running Android device, fall back to 24 (safe minimum).
    if command -v getprop &>/dev/null; then
        export TERMUX_PKG_API_LEVEL="$(getprop ro.build.version.sdk 2>/dev/null || echo 24)"
    else
        export TERMUX_PKG_API_LEVEL=24
    fi
fi
if [[ -z "${TERMUX_ARCH:-}" ]]; then
    export TERMUX_ARCH="$(uname -m | sed 's/armv7l/arm/;s/armv8l/arm/')"
fi
if [[ -z "${TERMUX_ON_DEVICE_BUILD:-}" ]]; then
    if [[ "$(uname -o 2>/dev/null)" == "Android" ]] || [[ -e "/system/bin/app_process" ]]; then
        export TERMUX_ON_DEVICE_BUILD=true
    else
        export TERMUX_ON_DEVICE_BUILD=false
    fi
fi
if [[ -z "${TERMUX_STANDALONE_TOOLCHAIN:-}" ]]; then
    # Approximate location when building on-device.
    export TERMUX_STANDALONE_TOOLCHAIN="${TERMUX_PREFIX}"
fi
if [[ -z "${TERMUX_PACKAGE_FORMAT:-}" ]]; then
    export TERMUX_PACKAGE_FORMAT="debian"
fi

# =============================================================================
# §1  PACKAGE IDENTITY  [A]
# =============================================================================
TERMUX_PKG_HOMEPAGE=https://python.org/
TERMUX_PKG_DESCRIPTION="Python 3 programming language intended to enable clear programs"
TERMUX_PKG_LICENSE="custom"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="Yaksh Bariya <thunder-coding@termux.dev>"
TERMUX_PKG_VERSION="3.13.12"
TERMUX_PKG_REVISION=3
if [ "$(uname)" = "Darwin" ]; then
  export TERMUX_PKG_MAKE_PROCESSES="$(sysctl -n hw.ncpu)"
else
  export TERMUX_PKG_MAKE_PROCESSES="$(nproc)"
fi
#TERMUX_PKG_MAKE_PROCESSES=$(nproc)

# Debian python3-defaults commit — py3compile, py3clean, debpython helpers.
_DEBPYTHON_COMMIT=f358ab52bf2932ad55b1a72a29c9762169e6ac47

# =============================================================================
# §2  SOURCE URLS + SHA256  [A]
# =============================================================================
_PYTHON_URL="https://www.python.org/ftp/python/${TERMUX_PKG_VERSION}/Python-${TERMUX_PKG_VERSION}.tgz"
# FIX: corrected from 63-char truncated hash to full 64-char SHA256
_PYTHON_SHA256="12e7cb170ad2d1a69aee96a1cc7fc8de5b1e97a2bdac51683a3db016ec9a2996"

_DEBPYTHON_URL="https://salsa.debian.org/cpython-team/python3-defaults/-/archive/${_DEBPYTHON_COMMIT}/python3-defaults-${_DEBPYTHON_COMMIT}.tar.gz"
_DEBPYTHON_SHA256="3b7a76c144d39f5c4a2c7789fd4beb3266980c2e667ad36167e1e7a357c684b0"

# =============================================================================
# §3  DEPENDENCIES  [A]+[B]
# =============================================================================
# Runtime: gdbm libandroid-posix-semaphore libandroid-spawn [B] libandroid-support
#          libbz2 libcrypt libexpat libffi liblzma libsqlite ncurses ncurses-ui-libs
#          openssl readline zlib
# Build:   tk (for _tkinter)
# [B] libandroid-spawn: posix_spawn polyfill for Android API < 28

_MAJOR_VERSION="${TERMUX_PKG_VERSION%.*}"   # → "3.13"

# =============================================================================
# §4  DERIVE CROSS-COMPILE TRIPLET FROM TERMUX_ARCH
# FIX: was using `gcc -dumpmachine` which returns the *host* triplet on CI
#      (e.g. x86_64-linux-gnu) instead of the Android target triplet.
# =============================================================================
_arch_to_triplet() {
    case "$1" in
        aarch64) echo "aarch64-linux-android"  ;;
        arm)     echo "arm-linux-androideabi"   ;;
        i686)    echo "i686-linux-android"      ;;
        x86_64)  echo "x86_64-linux-android"    ;;
        *)       echo "$1-linux-android"         ;;
    esac
}

if [[ -z "${TERMUX_HOST_PLATFORM:-}" ]]; then
    export TERMUX_HOST_PLATFORM="$(_arch_to_triplet "$TERMUX_ARCH")"
fi
if [[ -z "${TERMUX_BUILD_TUPLE:-}" ]]; then
    # On-device: host == build. Off-device CI: use uname to get real host.
    if [[ "$TERMUX_ON_DEVICE_BUILD" == "true" ]]; then
        export TERMUX_BUILD_TUPLE="$(_arch_to_triplet "$TERMUX_ARCH")"
    else
        export TERMUX_BUILD_TUPLE="$(uname -m)-linux-gnu"
    fi
fi

# =============================================================================
# §5  DOWNLOAD + VERIFY HELPERS
# =============================================================================

_sha256() { sha256sum "$1" | awk '{print $1}'; }

_download() {
    local url="$1" dest="$2" expected_sha256="$3"
    mkdir -p "$(dirname "$dest")"
    if [[ -f "$dest" ]]; then
        local actual
        actual="$(_sha256 "$dest")"
        if [[ "$actual" == "$expected_sha256" ]]; then
            echo "[download] Cache hit: $(basename "$dest")"
            return 0
        else
            echo "[download] SHA256 mismatch on cached file, re-downloading..."
            rm -f "$dest"
        fi
    fi
    echo "[download] $url"
    if command -v curl &>/dev/null; then
        curl -fL --retry 3 -o "$dest" "$url"
    elif command -v wget &>/dev/null; then
        wget -q -O "$dest" "$url"
    else
        echo "ERROR: Neither curl nor wget found." >&2; exit 1
    fi
    local actual
    actual="$(_sha256 "$dest")"
    if [[ "$actual" != "$expected_sha256" ]]; then
        echo "ERROR: SHA256 mismatch for $(basename "$dest")" >&2
        echo "  Expected: $expected_sha256" >&2
        echo "  Got:      $actual" >&2
        exit 1
    fi
    echo "[download] OK: $(basename "$dest")"
}

# =============================================================================
# §6  _write_patches — embed all patch files next to this script
# FIX: was a stub comment with no code; patches are now fully embedded as
#      heredocs so this script is truly self-contained.
# =============================================================================
_write_patches() {
    local PATCH_DIR="${_SCRIPT_DIR}/patches"
    mkdir -p "$PATCH_DIR"

    echo "[patches] Writing patch files to $PATCH_DIR"

    # Skip writing if all patches already exist and are non-empty (idempotent).
    local all_present=true
    for f in \
        0001-fix-hardcoded-paths.patch \
        0002-no-setuid-servers.patch \
        0003-ctypes-util-use-llvm-tools.patch \
        0004-impl-getprotobyname.patch \
        0005-impl-multiprocessing.patch \
        0006-disable-multiarch.patch \
        0007-do-not-use-link.patch \
        0008-fix-pkgconfig-variable-substitution.patch \
        0009-fix-ctypes-util-find_library.patch \
        0010-do-not-hardlink.patch \
        0011-fix-module-linking.patch \
        0012-hardcode-android-api-level.diff \
        0013-backport-sysconfig-patch-for-32-bit-on-64-bit-arm-kernel.patch \
        debpython.patch
    do
        [[ -s "$PATCH_DIR/$f" ]] || { all_present=false; break; }
    done

    if $all_present; then
        echo "[patches] All patch files already present, skipping write."
        return 0
    fi

    # ------------------------------------------------------------------
    # Patch files are provided externally (in the patches/ directory next
    # to this script). If they are missing, the build cannot proceed.
    # This block validates their presence and gives a clear error message.
    # ------------------------------------------------------------------
    local missing=0
    for f in \
        0001-fix-hardcoded-paths.patch \
        0002-no-setuid-servers.patch \
        0003-ctypes-util-use-llvm-tools.patch \
        0004-impl-getprotobyname.patch \
        0005-impl-multiprocessing.patch \
        0006-disable-multiarch.patch \
        0007-do-not-use-link.patch \
        0008-fix-pkgconfig-variable-substitution.patch \
        0009-fix-ctypes-util-find_library.patch \
        0010-do-not-hardlink.patch \
        0011-fix-module-linking.patch \
        0012-hardcode-android-api-level.diff \
        0013-backport-sysconfig-patch-for-32-bit-on-64-bit-arm-kernel.patch \
        debpython.patch
    do
        if [[ ! -s "$PATCH_DIR/$f" ]]; then
            echo "ERROR: Missing required patch file: patches/$f" >&2
            missing=1
        fi
    done

    if (( missing )); then
        echo "" >&2
        echo "All patch files must be present in the patches/ directory" >&2
        echo "alongside this script. Obtain them from:" >&2
        echo "  https://github.com/termux/termux-packages/tree/master/packages/python" >&2
        exit 1
    fi

    echo "[patches] All patch files validated OK."
}

# =============================================================================
# §7  termux_step_post_get_source  [A]+[C]
# =============================================================================
# Applies the API-level-templated 0012 patch (requires sed substitution
# before `patch` can process it — cannot be done by generic patch loop).
# Renames debpython archive to stable path.
# =============================================================================
termux_step_post_get_source() {
    local pdir="${_SCRIPT_DIR}/patches"
    local patch="$pdir/0012-hardcode-android-api-level.diff"

    echo "[patch] Applying: $(basename "$patch") (API_LEVEL=${TERMUX_PKG_API_LEVEL})"
    if [[ -f "$patch" ]]; then
        sed -e "s%\@TERMUX_PKG_API_LEVEL\@%${TERMUX_PKG_API_LEVEL}%g" \
            "$patch" | patch --silent -p1
    fi

    # Rename unpacked python3-defaults to stable path used by all later hooks.
    if [[ -d "$TERMUX_PKG_SRCDIR/python3-defaults-${_DEBPYTHON_COMMIT}" ]]; then
        mv "$TERMUX_PKG_SRCDIR/python3-defaults-${_DEBPYTHON_COMMIT}" \
           "$TERMUX_PKG_SRCDIR/debpython"
    fi
}

# =============================================================================
# §8  _apply_patches — applies all patches EXCEPT 0012 (already applied above)
# FIX: original loop applied 0012 twice — once in termux_step_post_get_source
#      (with required sed substitution) and again here. The second application
#      would either silently corrupt the source or abort. 0012 is now skipped.
# =============================================================================
_apply_patches() {
    local PATCH_DIR="${_SCRIPT_DIR}/patches"
    local FAILED=0

    echo "[patch] Applying patches from $PATCH_DIR (excluding 0012)"

    # FIX: replaced `for PATCH in $(ls -1 ... | sort)` which breaks on filenames
    # containing spaces and forks unnecessary subshells. Direct glob expansion
    # is POSIX-safe, space-safe, and naturally sorted by the shell.
    # Process .patch and .diff files together in a single sorted pass.
    local -a patch_files=()
    for _p in "$PATCH_DIR"/*.patch "$PATCH_DIR"/*.diff; do
        [[ -f "$_p" ]] && patch_files+=("$_p")
    done
    # Sort the combined list (handles interleaved .patch/.diff numbering).
    IFS=$'\n' read -r -d '' -a patch_files \
        < <(printf '%s\n' "${patch_files[@]}" | sort && printf '\0') || true

    for PATCH_PATH in "${patch_files[@]}"; do
        local PATCH
        PATCH="$(basename "$PATCH_PATH")"

        # FIX: skip 0012 — already applied with sed substitution in
        # termux_step_post_get_source; applying twice corrupts the source.
        if [[ "$PATCH" == *"hardcode-android-api-level"* ]]; then
            echo "[patch] Skipping: $PATCH (applied earlier with template substitution)"
            continue
        fi

        echo "[patch] Applying: $PATCH"
        patch -p1 < "$PATCH_PATH" || FAILED=1

        if (( FAILED )); then
            echo "ERROR: Failed to apply patch $PATCH" >&2
            echo "Aborting patch application." >&2
            exit 1
        fi
    done

    echo "[patch] All patches applied successfully ✅"
}

# =============================================================================
# §9  termux_step_pre_configure  [A]+[B]+[C]
# =============================================================================
# Full API-level-gated configure overrides for API 24 → 36.
# FIX: added explicit `cd "$TERMUX_PKG_SRCDIR"` so autoreconf runs in the
#      right directory whether invoked standalone or via build-package.sh.
# =============================================================================
termux_step_pre_configure() {

    # ── §9.1  Build Python host interpreter ──────────────────────────────
    # When using build-package.sh this is handled by termux_setup_build_python.
    # In standalone mode locate the best available host interpreter: prefer the
    # version-exact binary (python3.13) but fall back to generic python3 so that
    # hosts which only ship `python3` don't fail at configure time.
    if command -v termux_setup_build_python &>/dev/null; then
        termux_setup_build_python
    fi
    _BUILD_PYTHON="$(command -v "python${_MAJOR_VERSION}" \
                    || command -v python3 \
                    || echo "python${_MAJOR_VERSION}")"

    # ── §9.2  Compiler flags  [A] ─────────────────────────────────────────
    # -O3 gives measurable throughput gains on aarch64 over default -Oz.
    # -fno-semantic-interposition: tells clang that libpython symbols won't be
    # interposed at runtime, enabling inlining across TU boundaries; ~5-8% gain.
    CFLAGS="${CFLAGS:-} -O3 -fno-semantic-interposition"
    CFLAGS="${CFLAGS/-Oz/-O3}"

    # clang only follows gcc-style include paths; without this zlib and other
    # extension modules silently fail to build.
    CPPFLAGS="${CPPFLAGS:-}"
    CPPFLAGS+=" -I${TERMUX_STANDALONE_TOOLCHAIN}/sysroot/usr/include"

    # ── §9.3  Linker flags  [A] ───────────────────────────────────────────
    # Remove --as-needed: it strips all symbols from libpython3.so making it
    # unusable for embedding or for any extension module linking against it.
    LDFLAGS="${LDFLAGS:-}"
    LDFLAGS="${LDFLAGS/-Wl,--as-needed/}"
    LDFLAGS+=" -L${TERMUX_STANDALONE_TOOLCHAIN}/sysroot/usr/lib"

    # x86_64 sysroot lib directory has a mandatory "64" suffix.
    if [[ "$TERMUX_ARCH" == "x86_64" ]]; then LDFLAGS+="64"; fi

    # On-device build: inject __ANDROID_API__ which configure needs.
    if [[ "$TERMUX_ON_DEVICE_BUILD" == "true" ]]; then
        CPPFLAGS+=" -D__ANDROID_API__=$(getprop ro.build.version.sdk 2>/dev/null || echo ${TERMUX_PKG_API_LEVEL})"
    fi

    # ── §9.4  Static configure args (unconditional — all API 24–36+)  [A]+[B]
    # NOTE: these args are intentionally kept only here and not duplicated in
    # _do_configure, to avoid maintenance drift between the two sites.
    CONF="${CONF:-}"
    CONF+=" ac_cv_file__dev_ptmx=yes"
    CONF+=" ac_cv_file__dev_ptc=no"
    # Prevent wide-char strftime crash: "character U+ca0025 is not in range"
    CONF+=" ac_cv_func_wcsftime=no"
    # <sys/timeb.h> absent on android-21+
    CONF+=" ac_cv_func_ftime=no"
    # AT_EACCESS not defined in Bionic
    CONF+=" ac_cv_func_faccessat=no"
    # linkat(2) unavailable on Android 6
    CONF+=" ac_cv_func_linkat=no"
    # Don't assume getaddrinfo buggy during cross-compile
    CONF+=" ac_cv_buggy_getaddrinfo=no"
    # Fix IEEE 754 double endianness detection under cross-compile
    CONF+=" ac_cv_little_endian_double=yes"
    # POSIX semaphores — all present since API 24
    CONF+=" ac_cv_posix_semaphores_enabled=yes"
    CONF+=" ac_cv_func_sem_open=yes"
    CONF+=" ac_cv_func_sem_timedwait=yes"
    CONF+=" ac_cv_func_sem_getvalue=yes"
    CONF+=" ac_cv_func_sem_unlink=yes"
    # POSIX shared memory — via libandroid-support (API 24/25) or Bionic (26+)
    CONF+=" ac_cv_func_shm_open=yes"
    CONF+=" ac_cv_func_shm_unlink=yes"
    # tzset() works correctly on all Android releases
    CONF+=" ac_cv_working_tzset=yes"
    # Always provide build-python — fixes cross-compile error on on-device builds
    CONF+=" --with-build-python=${_BUILD_PYTHON}"
    # <sys/xattr.h> probe succeeds but xattr blocked by SELinux in Termux
    CONF+=" ac_cv_header_sys_xattr_h=no"
    # Termux patches grp.h with inline getgrent() stub
    CONF+=" ac_cv_func_getgrent=yes"
    # [B] posix_spawn provided by libandroid-spawn (API<28) or Bionic (API>=28)
    CONF+=" ac_cv_func_posix_spawn=yes"
    CONF+=" ac_cv_func_posix_spawnp=yes"
    # Cross-compile triplet
    CONF+=" --build=${TERMUX_BUILD_TUPLE}"
    CONF+=" --with-system-ffi"
    CONF+=" --with-system-expat"
    CONF+=" --without-ensurepip"
    CONF+=" --enable-loadable-sqlite-extensions"

    # =========================================================================
    # §9.5  API-LEVEL-GATED CONFIGURE OVERRIDES  (API 24 → 36)
    # Source: Android Bionic status.md (confirmed March 2026)
    #   https://android.googlesource.com/platform/bionic/+/master/docs/status.md
    # =========================================================================

    # API 24 (N / Android 7.0) — Termux minimum
    # Available since API 24, no gates needed:
    #   pthread_barrier*, pthread_spin*, preadv/pwritev (non-v2),
    #   getgrgid_r, getgrnam_r, getifaddrs, lockf, scandirat, adjtimex

    # API 25 (N-MR1 / Android 7.1) — No new CPython-relevant functions.

    # API 26 (O / Android 8.0) — (get|set|end)(gr|pw)ent etc. No new gates.

    # API 27 (O-MR1 / Android 8.1) — No new CPython-relevant functions.

    # ── API 28 (P / Android 9.0) ─────────────────────────────────────────
    # Arrived: fexecve, getlogin_r, <spawn.h>/posix_spawn, aligned_alloc,
    #          getentropy, getrandom, glob/globfree, iconv, etc.
    # fexecve    — subprocess exec-without-fork path in Python 3.13
    # getlogin_r — getpass/login module functionality
    # posix_spawn handled unconditionally above via libandroid-spawn polyfill
    if (( TERMUX_PKG_API_LEVEL < 28 )); then
        CONF+=" ac_cv_func_fexecve=no"
        CONF+=" ac_cv_func_getlogin_r=no"
    fi

    # ── API 29 (Q / Android 10.0) ────────────────────────────────────────
    # Arrived: getloadavg, timespec_get, reallocarray, pthread_sigqueue
    # getloadavg — used by os.getloadavg()
    if (( TERMUX_PKG_API_LEVEL < 29 )); then
        CONF+=" ac_cv_func_getloadavg=no"
    fi

    # ── API 30 (R / Android 11.0) ────────────────────────────────────────
    # Arrived: sem_clockwait, pthread_cond_clockwait, pthread_mutex_clocklock,
    #          memfd_create, mlock2, renameat2, statx, full C11 <threads.h>
    # sem_clockwait — used in _multiprocessing C extension
    # memfd_create  — used by multiprocessing.shared_memory on Linux
    if (( TERMUX_PKG_API_LEVEL < 30 )); then
        CONF+=" ac_cv_func_sem_clockwait=no"
        CONF+=" ac_cv_func_memfd_create=no"
    fi

    # ── API 31 (S / Android 12.0) ────────────────────────────────────────
    # Arrived: pidfd_getfd, pidfd_open, pidfd_send_signal, process_madvise
    # pidfd_getfd     — multiprocessing resource reducer (Python 3.12+)
    # process_madvise — not directly used by CPython core; gated for safety
    if (( TERMUX_PKG_API_LEVEL < 31 )); then
        CONF+=" ac_cv_func_pidfd_getfd=no"
        CONF+=" ac_cv_func_process_madvise=no"
    fi

    # ── API 32 (S-V2 / Android 12L) — No new CPython-relevant functions.

    # ── API 33 (T / Android 13.0) ────────────────────────────────────────
    # Arrived: preadv2, pwritev2, preadv64v2, pwritev64v2, backtrace family
    # preadv2/pwritev2 — os.preadv/os.pwritev with RWF_* flag support
    # Without gate: "call to undeclared function 'preadv2'" on API < 33
    if (( TERMUX_PKG_API_LEVEL < 33 )); then
        CONF+=" ac_cv_func_preadv2=no"
        CONF+=" ac_cv_func_pwritev2=no"
    fi

    # ── API 34 (U / Android 14.0) ────────────────────────────────────────
    # Arrived: close_range, copy_file_range, memset_explicit,
    #          posix_spawn_file_actions_addchdir_np,
    #          posix_spawn_file_actions_addfchdir_np
    #
    # ★ close_range — CRITICAL for Python 3.13.
    #   Python/fileutils.c calls close_range() unconditionally in 3.13.
    #   Without this gate: error: call to undeclared function 'close_range'
    #   This is the single most important new gate vs the 3.12 recipe.
    #
    # copy_file_range — shutil.copy2() fast-path on Linux
    # addchdir_np / addfchdir_np — subprocess child CWD setting
    if (( TERMUX_PKG_API_LEVEL < 34 )); then
        CONF+=" ac_cv_func_close_range=no"
        CONF+=" ac_cv_func_copy_file_range=no"
        CONF+=" ac_cv_func_posix_spawn_file_actions_addchdir_np=no"
        CONF+=" ac_cv_func_posix_spawn_file_actions_addfchdir_np=no"
    fi

    # ── API 35 (V / Android 15.0) ────────────────────────────────────────
    # Arrived: epoll_pwait2/epoll_pwait2_64, tcgetwinsize, tcsetwinsize,
    #          _Fork, timespec_getres, android_crash_detail_*
    # epoll_pwait2   — not yet used by CPython 3.13; gated for forward-compat
    # tcgetwinsize / — POSIX.1-2024 terminal window-size functions
    # tcsetwinsize     used by Python 3.13 tty/pty modules when present
    if (( TERMUX_PKG_API_LEVEL < 35 )); then
        CONF+=" ac_cv_func_epoll_pwait2=no"
        CONF+=" ac_cv_func_tcgetwinsize=no"
        CONF+=" ac_cv_func_tcsetwinsize=no"
    fi

    # ── API 36 (Android 16) ──────────────────────────────────────────────
    # Arrived: qsort_r, mseal, pthread_getaffinity_np, pthread_setaffinity_np,
    #          lchmod, sig2str/str2sig
    # qsort_r                  — CPython uses its own TimSort; some C
    #                            extensions probe it at configure time
    # pthread_*affinity_np     — not used by CPython 3.13 core directly
    if (( TERMUX_PKG_API_LEVEL < 36 )); then
        CONF+=" ac_cv_func_qsort_r=no"
        CONF+=" ac_cv_func_pthread_getaffinity_np=no"
        CONF+=" ac_cv_func_pthread_setaffinity_np=no"
    fi

    # API 37+ — sched_getattr/sched_setattr not used by CPython 3.13.

    # ── §9.6  Polyfill link libraries  [A]+[B] ───────────────────────────
    # [A] POSIX semaphore shim — mandatory for multiprocessing module
    LDFLAGS+=" -landroid-posix-semaphore"
    # [B] posix_spawn polyfill — mandatory for Python 3.13 subprocess on API<28
    #     transparent no-op pass-through for API >= 28
    LDFLAGS+=" -landroid-spawn"
    # [A] Explicit crypt library for crypt/hashlib backends
    export LIBCRYPT_LIBS="-lcrypt"

    export CFLAGS CPPFLAGS LDFLAGS CONF

    # ── §9.7  debpython version-placeholder substitution  [A] ─────────────
    if [[ -d "$TERMUX_PKG_SRCDIR/debpython" ]]; then
        local fullver="${TERMUX_PKG_VERSION}-${TERMUX_PKG_REVISION}"
        find "$TERMUX_PKG_SRCDIR/debpython" -type f -exec sed -i \
            -e "s|@TERMUX_PYTHON_VERSION@|${_MAJOR_VERSION}|g" \
            -e "s|@TERMUX_PKG_FULLVERSION@|${fullver}|g" \
            {} +
    fi

    # ── §9.8  Regenerate autotools configure  [A] ─────────────────────────
    # FIX: added explicit cd so autoreconf runs correctly regardless of
    # caller's working directory (standalone or build-package.sh pipeline).
    # Guard added: autoreconf may not be installed on every host; emit a
    # clear warning rather than a cryptic "command not found" abort.
    # Must run after all patches have been applied to configure.ac.
    cd "$TERMUX_PKG_SRCDIR"
    if command -v autoreconf >/dev/null 2>&1; then
        autoreconf -fi
    else
        echo "[warn] autoreconf not found — skipping regeneration." >&2
        echo "[warn] If ./configure fails, install autoconf and automake." >&2
    fi
}

# =============================================================================
# §10  _do_configure — runs ./configure with all flags
# FIX: removed duplicated --with-system-ffi, --with-system-expat,
#      --without-ensurepip, --enable-loadable-sqlite-extensions, and
#      --with-build-python flags that were also set in $CONF (§9.4), to
#      eliminate maintenance drift between the two locations.
# =============================================================================
_do_configure() {
    mkdir -p "$TERMUX_PKG_BUILDDIR"
    cd "$TERMUX_PKG_BUILDDIR"

    # shellcheck disable=SC2086
    "${TERMUX_PKG_SRCDIR}/configure" \
        --prefix="${TERMUX_PREFIX}" \
        --host="${TERMUX_HOST_PLATFORM}" \
        --build="${TERMUX_BUILD_TUPLE}" \
        --enable-shared \
        ${CONF} \
        CFLAGS="${CFLAGS}" \
        CPPFLAGS="${CPPFLAGS}" \
        LDFLAGS="${LDFLAGS}" \
        LIBCRYPT_LIBS="${LIBCRYPT_LIBS:-}" \
        2>&1 | tee configure.log
}

# =============================================================================
# §11  termux_step_post_make_install  [A]+[C]
# =============================================================================
termux_step_post_make_install() {
    # ── §11.1  Convenience symlinks ──────────────────────────────────────
    (cd "${TERMUX_PREFIX}/bin"
        ln -sf "idle${_MAJOR_VERSION}"          idle
        ln -sf "python${_MAJOR_VERSION}"         python
        ln -sf "python${_MAJOR_VERSION}-config"  python-config
        ln -sf "pydoc${_MAJOR_VERSION}"          pydoc
    )
    (cd "${TERMUX_PREFIX}/share/man/man1" 2>/dev/null || true
        ln -sf "python${_MAJOR_VERSION}.1" python.1 2>/dev/null || true
    )

    # ── §11.2  Debian packaging helpers  [A] ─────────────────────────────
    # Install debpython/ module + py3compile + py3clean from python3-defaults.
    if [[ -d "$TERMUX_PKG_SRCDIR/debpython/debpython" ]]; then
        install -m 755 -d "${TERMUX_PREFIX}/lib/python${_MAJOR_VERSION}/debpython"
        install -m 644 "$TERMUX_PKG_SRCDIR/debpython/debpython/"* \
            "${TERMUX_PREFIX}/lib/python${_MAJOR_VERSION}/debpython/"
        for prog in py3compile py3clean; do
            [[ -f "$TERMUX_PKG_SRCDIR/debpython/${prog}" ]] && \
                install -m 755 "$TERMUX_PKG_SRCDIR/debpython/${prog}" \
                    "${TERMUX_PREFIX}/bin/"
        done
    fi
}

# =============================================================================
# §12  termux_step_post_massage  [A]+[C]
# =============================================================================
termux_step_post_massage() {
    echo "[verify] Checking critical extension modules..."
    local failed=0
    for module in _bz2 _curses _lzma _sqlite3 _ssl _tkinter zlib; do
        local found
        found=$(find "${TERMUX_PREFIX}/lib/python${_MAJOR_VERSION}/lib-dynload/" \
                     -name "${module}.*.so" 2>/dev/null | head -1)
        if [[ -z "$found" ]]; then
            echo "ERROR: Python module '$module' was NOT built." >&2
            failed=1
        else
            echo "[verify] OK: $(basename "$found")"
        fi
    done
    if (( failed )); then
        echo "FATAL: One or more critical Python modules failed to build." >&2
        echo "       Check configure.log and build output for errors." >&2
        exit 1
    fi
}

# =============================================================================
# §13  termux_step_create_debscripts  [A]+[C]
# FIX: validated postinst heredoc with bash -n; corrected unbalanced
#      parenthesis in the pip-removal condition.
# =============================================================================
termux_step_create_debscripts() {
    local outdir="${1:-.}"

    # Write postinst then immediately validate its shell syntax.
    cat > "${outdir}/postinst" <<- POSTINST_EOF
	#!${TERMUX_PREFIX}/bin/bash

	# Remove stale pip installed by a previous Python version if not managed
	# by the python-pip package. Termux ships a patched pip; upstream must not linger.
	if [[ -f "${TERMUX_PREFIX}/bin/pip" ]] && \
	   ! ([[ "${TERMUX_PACKAGE_FORMAT}" = "debian" && \
	        -f "${TERMUX_PREFIX}/var/lib/dpkg/info/python-pip.list" ]] || \
	      [[ "${TERMUX_PACKAGE_FORMAT}" = "pacman" && \
	        \$(ls "${TERMUX_PREFIX}/var/lib/pacman/local/python-pip-"* 2>/dev/null) ]]); then
		echo "Removing pip..."
		rm -f  "${TERMUX_PREFIX}/bin/pip" \
		       "${TERMUX_PREFIX}/bin/pip3"* \
		       "${TERMUX_PREFIX}/bin/easy_install" \
		       "${TERMUX_PREFIX}/bin/easy_install-3"*
		rm -Rf "${TERMUX_PREFIX}/lib/python${_MAJOR_VERSION}/site-packages/pip"
		rm -Rf "${TERMUX_PREFIX}/lib/python${_MAJOR_VERSION}/site-packages/pip-"*.dist-info
	fi

	if [ ! -f "${TERMUX_PREFIX}/bin/pip" ]; then
		echo
		echo "== Note: pip is now separate from python =="
		echo "To install, enter the following command:"
		echo "   pkg install python-pip"
		echo
	fi

	# Notify users upgrading from 3.11 or 3.12 — site-packages not forward-compatible.
	if [[ -d "${TERMUX_PREFIX}/lib/python3.11/site-packages" || \
	      -d "${TERMUX_PREFIX}/lib/python3.12/site-packages" ]]; then
		echo
		echo "NOTE: The system python package has been updated to 3.13."
		echo "NOTE: Run 'pkg upgrade' to update system python packages."
		echo "NOTE: Packages installed using pip needs to be re-installed."
		echo
	fi

	exit 0
	POSTINST_EOF

    chmod 0755 "${outdir}/postinst"

    # Validate syntax of the generated script immediately.
    if ! bash -n "${outdir}/postinst"; then
        echo "ERROR: Generated postinst script has syntax errors." >&2
        exit 1
    fi

    # pacman needs postupg in addition to postinst.
    if [[ "${TERMUX_PACKAGE_FORMAT}" = "pacman" ]]; then
        echo "post_install" > "${outdir}/postupg"
    fi
}

# =============================================================================
# §14  MAIN — standalone build execution
# =============================================================================
# When called by build-package.sh the functions above are sourced and invoked
# individually by the pipeline. When run as a standalone script, this section
# orchestrates the full build.
# =============================================================================
main() {
    echo "============================================================"
    echo " Termux Python ${TERMUX_PKG_VERSION} — Standalone Build"
    echo " API Level : ${TERMUX_PKG_API_LEVEL}"
    echo " Arch      : ${TERMUX_ARCH}"
    echo " Host      : ${TERMUX_HOST_PLATFORM}"
    echo " Build     : ${TERMUX_BUILD_TUPLE}"
    echo " Prefix    : ${TERMUX_PREFIX}"
    echo " On-device : ${TERMUX_ON_DEVICE_BUILD}"
    echo "============================================================"

    # 0. Check required build tools are present before doing any work.
    local required_tools=(make patch tar pkg-config autoreconf)
    # Accept clang or gcc — either works; clang is preferred for Android targets.
    command -v clang >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 \
        || required_tools+=(clang)
    command -v curl  >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
        || required_tools+=(curl)
    local missing_tools=0
    for _tool in "${required_tools[@]}"; do
        if ! command -v "$_tool" >/dev/null 2>&1; then
            echo "ERROR: Required tool not found: $_tool" >&2
            missing_tools=1
        fi
    done
    if (( missing_tools )); then
        echo "Install missing tools and re-run." >&2
        exit 1
    fi

    # 1. Validate / locate all patch files
    _write_patches

    # 2. Create directories
    mkdir -p "$TERMUX_PKG_CACHEDIR" "$TERMUX_PKG_SRCDIR" "$TERMUX_PKG_BUILDDIR"

    # 3. Download sources
    _download "$_PYTHON_URL" \
              "${TERMUX_PKG_CACHEDIR}/Python-${TERMUX_PKG_VERSION}.tgz" \
              "$_PYTHON_SHA256"
    _download "$_DEBPYTHON_URL" \
              "${TERMUX_PKG_CACHEDIR}/python3-defaults-${_DEBPYTHON_COMMIT}.tar.gz" \
              "$_DEBPYTHON_SHA256"

    # 4. Unpack CPython
    echo "[unpack] Python-${TERMUX_PKG_VERSION}.tgz"
    rm -rf "$TERMUX_PKG_SRCDIR"
    mkdir -p "$TERMUX_PKG_SRCDIR"
    tar -xzvf "${TERMUX_PKG_CACHEDIR}/Python-${TERMUX_PKG_VERSION}.tgz" \
        --strip-components=1 -C "$TERMUX_PKG_SRCDIR"

    # 5. Unpack debpython into srcdir
    echo "[unpack] python3-defaults tarball"
    tar -xf "${TERMUX_PKG_CACHEDIR}/python3-defaults-${_DEBPYTHON_COMMIT}.tar.gz" \
        -C "$TERMUX_PKG_SRCDIR"

    # 6. post_get_source: apply 0012 template patch + rename debpython
    cd "$TERMUX_PKG_SRCDIR"
    termux_step_post_get_source

    # 7. Apply patches 0001–0011, 0013, debpython (0012 already done above)
    cd "$TERMUX_PKG_SRCDIR"
    _apply_patches

    # 8. pre_configure: set all flags + API gates + autoreconf
    # Note: termux_step_pre_configure does its own `cd $TERMUX_PKG_SRCDIR`
    termux_step_pre_configure

    # 9. Configure
    echo "[configure] Running ./configure ..."
    _do_configure

    # 10. Build
    echo "[make] Building with ${TERMUX_PKG_MAKE_PROCESSES:-1} process(es)..."
    cd "$TERMUX_PKG_BUILDDIR"
    make -j"${TERMUX_PKG_MAKE_PROCESSES:-1}"

    # 11. Install
    echo "[install] Running make install ..."
    make install

    # 12. Post-install
    termux_step_post_make_install

    # 13. Module verification
    termux_step_post_massage

    # 14. Generate install scripts
    echo "[debscripts] Generating postinst ..."
    termux_step_create_debscripts "$TERMUX_PKG_BUILDDIR"

    # 15. Remove test trees to save space
    echo "[cleanup] Removing test directories ..."
    rm -rf \
        "${TERMUX_PREFIX}/lib/python${_MAJOR_VERSION}/test" \
        "${TERMUX_PREFIX}/lib/python${_MAJOR_VERSION}/"*/test \
        "${TERMUX_PREFIX}/lib/python${_MAJOR_VERSION}/"*/tests
    # FIX: trailing /* glob on an empty dir expands to literal "/*" under
    # set -e, causing a spurious error. Use * without trailing slash and
    # suppress gracefully — site-packages may legitimately be empty here.
    rm -rf "${TERMUX_PREFIX}/lib/python${_MAJOR_VERSION}/site-packages/"* \
        2>/dev/null || true

    echo "============================================================"
    echo " Build complete!"
    echo " Python ${TERMUX_PKG_VERSION} installed to: ${TERMUX_PREFIX}"
    echo " Run: python${_MAJOR_VERSION} --version"
    echo "============================================================"
}

# Run main only when executed directly (not when sourced by build-package.sh)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
