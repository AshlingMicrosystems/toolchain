#!/bin/bash -u
# Script for building a RISC-V GNU Toolchain from checked out sources
# (specialised for Ashling)

# Copyright (C) 2020-2021 Embecosm Limited

# Extended by Embecosm and Ashling

# Contributor: Simon Cook <simon.cook@embecosm.com>

# SPDX-License-Identifier: GPL-3.0-or-later

# Variables used in this script
SRCPREFIX="$(dirname $(dirname $(readlink -f $0)))"
INSTALLPREFIX=${SRCPREFIX}/install
BUILDPREFIX=${SRCPREFIX}/build
LIBINSTPREFIX=${BUILDPREFIX}/libinst
LOGDIR="${SRCPREFIX}/logs/$(date +%Y%m%d-%H%M)"
PARALLEL_JOBS=$(nproc)

# Default values which can be overriden options specified in this script:
DEFAULTARCH=rv32ima
DEFAULTABI=ilp32
BUGURL=
PKGVERS=
OPT_DEBUG_CFLAGS_DEBUG="-O0 -g3"
OPT_DEBUG_CFLAGS_RELEASE="-O2"
OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS_RELEASE}"
CUSTOM_CFLAGS=1

for opt in ${@}; do
  valid_arg=1
  case ${opt} in
  "--clean")
    echo "Erasing ${BUILDPREFIX}..."
    rm -rf "${BUILDPREFIX}"
    ;;
  "--default-arch="*)
    DEFAULTARCH=${opt#--default-arch=}
    ;;
  "--default-abi="*)
    DEFAULTABI=${opt#--default-abi=}
    ;;
  "--bug-report-url="*)
    BUG_URL=${opt#--bug-report-url=}
    ;;
  "--release-version="*)
    BUILD_ID=${opt#--release-version=}
    ;;
  "--mode=debug")
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS_DEBUG}"
    ;;
  "--mode=release")
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS_RELEASE}"
    ;;
  "--no-custom-cflags")
    CUSTOM_CFLAGS=0
    ;;
  "--no-staticlibs")
    STATIC_GDBFLAGS=""
    ;;
  "--help")
    valid_arg=0
    ;;& # Fallthrough (requires Bash 4+)
  *)
    echo "Usage for $0:"
    echo "  --bug-report-url=   Set bug reporting URL."
    echo "  --clean             Erase build directory before building."
    echo "  --default-abi=      Set default ABI."
    echo "  --default-arch=     Set default architecture."
    echo "  --no-custom-cflags  Disable expanded tool CFLAGS/CXXFLAGS."
    echo "  --no-staticlibs     Do not force static libexpat/libgmp."
    echo "  --mode=debug        Build toolchain with debug enabled."
    echo "  --mode=release      Build toolchain with debug disabled. [Default]"
    echo "  --release-version=  Set release number."
    echo "  --help              Print this message."
    echo ""
    echo "The current default architecture/ABI is ${DEFAULTARCH}/${DEFAULTABI}."
    exit $valid_arg
    ;;
  esac
done

# Add extra opt flags supported for the given operating system
if [ ${CUSTOM_CFLAGS} -eq 1 ]; then
  if [ "$(uname -o)" == "Msys" ]; then
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -Wformat -Wformat-security -Werror=format-security"
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -fPIE -fpie"
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -fPIC"
  else
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -Wformat -Wformat-security -Werror=format-security"
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -D_FORTIFY_SOURCE=2"
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -fstack-protector-strong"
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -fPIE -fpie"
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -fPIC"
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -Wl,-z,relro"
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -Wl,-z,now"
    OPT_DEBUG_CFLAGS="${OPT_DEBUG_CFLAGS} -Wl,-z,noexecstack"
  fi
fi

# Create log directory
mkdir -p ${LOGDIR}

# If a BUGURL and PKGVERS has been provided, add these as arguments
EXTRA_OPTS=""
if [ "x${BUGURL}" != "x" ]; then
  EXTRA_OPTS="${EXTRA_OPTS} --with-bugurl='${BUGURL}'"
fi
if [ "x${PKGVERS}" != "x" ]; then
  EXTRA_OPTS="${EXTRA_OPTS} --with-pkgversion='${PKGVERS}'"
fi

# Log build environment (commits being built)
LOGFILE="${LOGDIR}/environment.log"
echo "Logging build environment... logging to ${LOGFILE}"
(
  set -e
  cd ${SRCPREFIX}
  env
  echo "======"
  ${SRCPREFIX}/toolchain/describe-build.sh
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error logging environment, check log file!" > /dev/stderr
  exit 1
fi

# Build dependencies if they are there
LOGFILE="${LOGDIR}/libexpat.log"
echo "Building libexpat... logging to ${LOGFILE}"
(
  set -e
  mkdir -p ${BUILDPREFIX}/libexpat
  cd ${BUILDPREFIX}/libexpat
  cmake ../../libexpat/expat \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=${LIBINSTPREFIX}/libexpat \
      -DEXPAT_ENABLE_INSTALL=ON \
      -DEXPAT_SHARED_LIBS=OFF \
      -DCMAKE_C_FLAGS="${OPT_DEBUG_CFLAGS}" \
      -DCMAKE_CXX_FLAGS="${OPT_DEBUG_CFLAGS}"
  cmake --build .
  cmake --build . --target install
  # Alias lib64 -> lib so GDB can pick up this library if it exists
  if [ -e ${LIBINSTPREFIX}/libexpat/lib64 ]; then
    ln -s ${LIBINSTPREFIX}/libexpat/lib64 ${LIBINSTPREFIX}/libexpat/lib
  fi
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building libexpat, check log file!" > /dev/stderr
  exit 1
fi

LOGFILE="${LOGDIR}/libgmp.log"
echo "Building libgmp... logging to ${LOGFILE}"
(
  set -xe
  # Apply CVE if not specified
  cd ${SRCPREFIX}/gmp-6.2.1
  if ! grep 'if (UNLIKELY (abs_csize > ~(mp_bitcnt_t) 0 / 8))' mpz/inp_raw.c; then
    echo "Applying PATCH gmp-cve-2021-43618.patch..."
    patch -p1 < ${SRCPREFIX}/toolchain/patches/gmp-cve-2021-43618.patch
  fi
  mkdir -p ${BUILDPREFIX}/libgmp
  cd ${BUILDPREFIX}/libgmp
  CFLAGS="${OPT_DEBUG_CFLAGS}" \
  CXXFLAGS="${OPT_DEBUG_CFLAGS}" \
  ../../gmp-6.2.1/configure \
    --prefix=${LIBINSTPREFIX}/libgmp \
    --enable-shared=no
  make
  make install
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building libgmp, check log file!" > /dev/stderr
  exit 1
fi

LOGFILE="${LOGDIR}/openssl.log"
echo "Building openssl... logging to ${LOGFILE}"
(
  set -xe
  mkdir -p ${BUILDPREFIX}/openssl
  cd ${BUILDPREFIX}/openssl
  perl ../../openssl/Configure \
      --prefix=${LIBINSTPREFIX}/openssl \
      linux-x86_64 no-shared ${OPT_DEBUG_CFLAGS}
  make -j${PARALLEL_JOBS}
  make install
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building openssl, check log file!" > /dev/stderr
  exit 1
fi

LOGFILE="${LOGDIR}/libffi.log"
echo "Building libffi... logging to ${LOGFILE}"
(
  set -xe
  mkdir -p ${BUILDPREFIX}/libffi
  cd ${BUILDPREFIX}/libffi
  CFLAGS="${OPT_DEBUG_CFLAGS}" \
  CXXFLAGS="${OPT_DEBUG_CFLAGS}" \
  ../../libffi/configure \
    --prefix=${LIBINSTPREFIX}/libffi \
    --enable-shared=no
  make
  make install
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building libffi, check log file!" > /dev/stderr
  exit 1
fi

LOGFILE="${LOGDIR}/zlib.log"
echo "Building zlib... logging to ${LOGFILE}"
(
  set -xe
  mkdir -p ${BUILDPREFIX}/zlib
  cd ${BUILDPREFIX}/zlib
  CFLAGS="${OPT_DEBUG_CFLAGS}" \
  CXXFLAGS="${OPT_DEBUG_CFLAGS}" \
  ../../zlib/configure \
    --prefix=${LIBINSTPREFIX}/zlib \
    --static
  make
  make install
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building zlib, check log file!" > /dev/stderr
  exit 1
fi

LOGFILE="${LOGDIR}/sqlite.log"
echo "Building sqlite... logging to ${LOGFILE}"
(
  set -xe
  mkdir -p ${BUILDPREFIX}/sqlite
  cd ${BUILDPREFIX}/sqlite
  CFLAGS="${OPT_DEBUG_CFLAGS}" \
  CXXFLAGS="${OPT_DEBUG_CFLAGS}" \
  ../../sqlite/configure \
    --prefix=${LIBINSTPREFIX}/sqlite \
    --enable-shared=no \
    --enable-all \
    --disable-tcl
  make
  make install
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building sqlite, check log file!" > /dev/stderr
  exit 1
fi

LOGFILE="${LOGDIR}/python.log"
echo "Building python... logging to ${LOGFILE}"
(
  set -xe
  export PKG_CONFIG_PATH=$(ls -d ${LIBINSTPREFIX}/*/lib/pkgconfig | tr '\n' ':' | sed 's/.$//')
  mkdir -p ${BUILDPREFIX}/python
  cd ${BUILDPREFIX}/python
  CPPFLAGS="$(pkg-config --cflags-only-I libffi zlib sqlite3)" \
  LDFLAGS="$(pkg-config --libs-only-L libffi zlib sqlite3)" \
  LIBS="$(pkg-config --libs-only-l libffi zlib sqlite3)" \
  CFLAGS="${OPT_DEBUG_CFLAGS}" \
  CXXFLAGS="${OPT_DEBUG_CFLAGS}" \
  ../../cpython/configure \
    --enable-shared \
    --prefix=${INSTALLPREFIX}
  make
  make install

  # We need to patch the rpath for python for GDB to successfully use it
  patchelf --set-rpath '$ORIGIN/../lib' ${INSTALLPREFIX}/bin/python3.9
  patchelf --set-rpath '$ORIGIN' ${INSTALLPREFIX}/lib/libpython3.so
  patchelf --set-rpath '$ORIGIN' ${INSTALLPREFIX}/lib/libpython3.9.so.1.0

  # Additionally need to strip debug information from these files
  strip -g ${INSTALLPREFIX}/bin/python3.9 \
    ${INSTALLPREFIX}/lib/libpython3.so \
    ${INSTALLPREFIX}/lib/libpython3.9.so.1.0
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building python, check log file!" > /dev/stderr
  exit 1
fi

# Binutils
LOGFILE="${LOGDIR}/binutils.log"
echo "Building Binutils... logging to ${LOGFILE}"
(
  set -e
  mkdir -p ${BUILDPREFIX}/binutils
  cd ${BUILDPREFIX}/binutils
  CFLAGS="${OPT_DEBUG_CFLAGS}" \
  CXXFLAGS="${OPT_DEBUG_CFLAGS}" \
  ../../binutils/configure            \
      --target=riscv32-unknown-elf    \
      --prefix=${INSTALLPREFIX}       \
      --disable-werror                \
      --disable-gdb                   \
      --with-debuginfod=no            \
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS}
  make install-strip
  make install-pdf
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building Binutils, check log file!" > /dev/stderr
  exit 1
fi

# GDB
LOGFILE="${LOGDIR}/gdb.log"
echo "Building GDB... logging to ${LOGFILE}"
(
  set -e
  export PKG_CONFIG_PATH=$(ls -d ${LIBINSTPREFIX}/*/lib/pkgconfig | tr '\n' ':' | sed 's/.$//')
  mkdir -p ${BUILDPREFIX}/gdb
  cd ${BUILDPREFIX}/gdb
  CFLAGS="${OPT_DEBUG_CFLAGS}" \
  CXXFLAGS="${OPT_DEBUG_CFLAGS}" \
  LDFLAGS="$(pkg-config --libs-only-L libffi zlib sqlite3 expat) -L${INSTALLPREFIX}/lib" \
  ../../gdb/configure                 \
      --target=riscv32-unknown-elf    \
      --prefix=${INSTALLPREFIX}       \
      --with-expat                    \
      --with-libexpat-prefix=${LIBINSTPREFIX}/libexpat \
      --with-debuginfod=no            \
      --disable-werror                \
      --enable-tui=no                 \
      --with-python=${INSTALLPREFIX}/bin/python3 \
      --with-libgmp-prefix=${LIBINSTPREFIX}/libgmp \
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS} all-gdb V=1
  make install-strip-gdb
  make install-pdf

  # Patch the rpath for GDB
  patchelf --set-rpath '$ORIGIN/../lib' ${INSTALLPREFIX}/bin/riscv32-unknown-elf-gdb
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building GDB, check log file!" > /dev/stderr
  exit 1
fi

# GCC (Stage 1)
LOGFILE="${LOGDIR}/gcc-stage1.log"
echo "Building GCC (Stage 1)... logging to ${LOGFILE}"
(
  set -e
  cd ${SRCPREFIX}/gcc
  ./contrib/download_prerequisites
  # Apply a local patch to work around CVE-2021-43618
  cd gmp-6.1.0
  if ! grep 'if (UNLIKELY (abs_csize > ~(mp_bitcnt_t) 0 / 8))' mpz/inp_raw.c; then
    echo "Applying PATCH gmp-cve-2021-43618.patch..."
    patch -p1 < ${SRCPREFIX}/toolchain/patches/gmp-cve-2021-43618.patch
  fi

  mkdir -p ${BUILDPREFIX}/gcc-stage1
  cd ${BUILDPREFIX}/gcc-stage1
  CFLAGS="${OPT_DEBUG_CFLAGS}" \
  CXXFLAGS="${OPT_DEBUG_CFLAGS}" \
  ../../gcc/configure                                     \
      --target=riscv32-unknown-elf                        \
      --prefix=${INSTALLPREFIX}                           \
      --with-sysroot=${INSTALLPREFIX}/riscv32-unknown-elf \
      --with-newlib                                       \
      --without-headers                                   \
      --disable-shared                                    \
      --enable-languages=c                                \
      --disable-werror                                    \
      --disable-libatomic                                 \
      --disable-libmudflap                                \
      --disable-libssp                                    \
      --disable-quadmath                                  \
      --disable-libgomp                                   \
      --disable-nls                                       \
      --disable-bootstrap                                 \
      --enable-multilib                                   \
      --with-multilib-generator="rv32ia-ilp32-- rv32ima-ilp32-- rv64ima-lp64-- rv64imaf-lp64-- rv64imaf-lp64f--" \
      --with-arch=${DEFAULTARCH}                          \
      --with-abi=${DEFAULTABI}                            \
      --with-zstd=no                                      \
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS}
  make install-strip
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building GCC, check log file!" > /dev/stderr
  exit 1
fi

# Newlib
# NOTE: This configuration is taken from the config.logs of a
# "riscv-gnu-toolchain" build
LOGFILE="${LOGDIR}/newlib.log"
echo "Building newlib... logging to ${LOGFILE}"
(
  set -e
  PATH=${INSTALLPREFIX}/bin:${PATH}
  mkdir -p ${BUILDPREFIX}/newlib
  cd ${BUILDPREFIX}/newlib
  CFLAGS_FOR_TARGET="-O2 -mcmodel=medany"            \
  ../../newlib/configure                             \
      --target=riscv32-unknown-elf                   \
      --prefix=${INSTALLPREFIX}                      \
      --with-arch=${DEFAULTARCH}                     \
      --with-abi=${DEFAULTABI}                       \
      --enable-multilib                              \
      --enable-newlib-io-long-double                 \
      --enable-newlib-io-long-long                   \
      --enable-newlib-io-c99-formats                 \
      --enable-newlib-register-fini                  \
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS}
  make install
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building newlib, check log file!" > /dev/stderr
  exit 1
fi

# Nano-newlib
# NOTE: This configuration is taken from the config.logs of a
# "riscv-gnu-toolchain" build
LOGFILE="${LOGDIR}/newlib-nano.log"
echo "Building newlib-nano... logging to ${LOGFILE}"
(
  set -e
  PATH=${INSTALLPREFIX}/bin:${PATH}
  mkdir -p ${BUILDPREFIX}/newlib-nano
  cd ${BUILDPREFIX}/newlib-nano
  CFLAGS_FOR_TARGET="-Os -mcmodel=medany -ffunction-sections -fdata-sections" \
  ../../newlib/configure                             \
      --target=riscv32-unknown-elf                   \
      --prefix=${BUILDPREFIX}/newlib-nano-inst       \
      --with-arch=${DEFAULTARCH}                     \
      --with-abi=${DEFAULTABI}                       \
      --enable-multilib                              \
      --enable-newlib-reent-small                    \
      --disable-newlib-fvwrite-in-streamio           \
      --disable-newlib-fseek-optimization            \
      --disable-newlib-wide-orient                   \
      --enable-newlib-nano-malloc                    \
      --disable-newlib-unbuf-stream-opt              \
      --enable-lite-exit                             \
      --enable-newlib-global-atexit                  \
      --enable-newlib-nano-formatted-io              \
      --disable-newlib-supplied-syscalls             \
      --disable-nls                                  \
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS}
  make install

  # Manualy copy the nano variant to the expected location
  # Information obtained from "riscv-gnu-toolchain"
  for multilib in $(${INSTALLPREFIX}/bin/riscv32-unknown-elf-gcc --print-multi-lib); do
    multilibdir=$(echo ${multilib} | sed 's/;.*//')
    for file in libc.a libm.a libg.a libgloss.a; do
      cp ${BUILDPREFIX}/newlib-nano-inst/riscv32-unknown-elf/lib/${multilibdir}/${file} \
         ${INSTALLPREFIX}/riscv32-unknown-elf/lib/${multilibdir}/${file%.*}_nano.${file##*.}
    done
    cp ${BUILDPREFIX}/newlib-nano-inst/riscv32-unknown-elf/lib/${multilibdir}/crt0.o \
       ${INSTALLPREFIX}/riscv32-unknown-elf/lib/${multilibdir}/crt0.o
  done
  mkdir -p ${INSTALLPREFIX}/riscv32-unknown-elf/include/newlib-nano
  cp ${BUILDPREFIX}/newlib-nano-inst/riscv32-unknown-elf/include/newlib.h \
     ${INSTALLPREFIX}/riscv32-unknown-elf/include/newlib-nano/newlib.h
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building newlib-nano, check log file!" > /dev/stderr
  exit 1
fi

# Picolibc
# TODO: Make any required configuration changes for pico-libc
LOGFILE="${LOGDIR}/picolibc.log"
echo "Building picolibc... logging to ${LOGFILE}"
(
  set -e
  PATH=${INSTALLPREFIX}/bin:${PATH}
  mkdir -p ${BUILDPREFIX}/picolibc
  cd ${BUILDPREFIX}/picolibc
  meson ${SRCPREFIX}/picolibc \
      -Dincludedir=picolibc/riscv32-unknown-elf/include \
      -Dlibdir=picolibc/riscv32-unknown-elf/lib \
      -Dnewlib-global-errno=true \
      --cross-file ${SRCPREFIX}/picolibc/scripts/cross-riscv32-unknown-elf.txt \
      --prefix=${INSTALLPREFIX}
  ninja
  ninja install
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building picolibc, check log file!" > /dev/stderr
  exit 1
fi

# GCC (stage 2)
LOGFILE="${LOGDIR}/gcc-stage2.log"
echo "Building GCC (Stage 2)... logging to ${LOGFILE}"
(
  set -e
  cd ${SRCPREFIX}/gcc
  mkdir -p ${BUILDPREFIX}/gcc-stage2
  cd ${BUILDPREFIX}/gcc-stage2
  CFLAGS="${OPT_DEBUG_CFLAGS}" \
  CXXFLAGS="${OPT_DEBUG_CFLAGS}" \
  ../../gcc/configure                                     \
      --target=riscv32-unknown-elf                        \
      --prefix=${INSTALLPREFIX}                           \
      --with-sysroot=${INSTALLPREFIX}/riscv32-unknown-elf \
      --with-native-system-header-dir=/include            \
      --with-newlib                                       \
      --disable-shared                                    \
      --enable-languages=c,c++                            \
      --enable-tls                                        \
      --disable-werror                                    \
      --disable-libmudflap                                \
      --disable-libssp                                    \
      --disable-quadmath                                  \
      --disable-libgomp                                   \
      --disable-nls                                       \
      --enable-multilib                                   \
      --with-multilib-generator="rv32ia-ilp32-- rv32ima-ilp32-- rv64ima-lp64-- rv64imaf-lp64-- rv64imaf-lp64f--" \
      --with-arch=${DEFAULTARCH}                          \
      --with-abi=${DEFAULTABI}                            \
      --with-zstd=no                                      \
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS}
  make install-strip
  make install-pdf
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building GCC, check log file!" > /dev/stderr
  exit 1
fi

# Finally strip all the libraries
LOGFILE="${LOGDIR}/strip-libraries.log"
echo "Stripping target libraries... logging to ${LOGFILE}"
(
  set -e
  cd ${INSTALLPREFIX}/riscv32-unknown-elf
  find . -\( -name '*.a' -o -name '*.o' -\) -print -exec \
    ../bin/riscv32-unknown-elf-strip -g {} \;
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error stripping target libraries, check log file!" > /dev/stderr
  exit 1
fi

echo "Build completed successfully."
