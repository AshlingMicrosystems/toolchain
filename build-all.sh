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
  "--help")
    valid_arg=0
    ;;& # Fallthrough (requires Bash 4+)
  *)
    echo "Usage for $0:"
    echo "  --bug-report-url=   Set bug reporting URL."
    echo "  --clean             Erase build directory before building."
    echo "  --default-abi=      Set default ABI."
    echo "  --default-arch=     Set default architecture."
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
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS}
  make install
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
  mkdir -p ${BUILDPREFIX}/gdb
  cd ${BUILDPREFIX}/gdb
  CFLAGS="${OPT_DEBUG_CFLAGS}" \
  CXXFLAGS="${OPT_DEBUG_CFLAGS}" \
  ../../gdb/configure                 \
      --target=riscv32-unknown-elf    \
      --prefix=${INSTALLPREFIX}       \
      --with-expat                    \
      --disable-werror                \
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS} all-gdb
  make install-gdb
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
      --with-multilib-generator="rv32e-ilp32e-- rv32ima-ilp32-- rv64ima-lp64-- rv64imaf-lp64-- rv64imaf-lp64f--" \
      --with-arch=${DEFAULTARCH}                          \
      --with-abi=${DEFAULTABI}                            \
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS}
  make install
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building GCC, check log file!" > /dev/stderr
  exit 1
fi

# Newlib
# TODO: Implement the newlib configuration required for this project
# (e.g. default full build and second "nano" build)?
# (Currently this is a nano-ish build)
LOGFILE="${LOGDIR}/newlib.log"
echo "Building newlib... logging to ${LOGFILE}"
(
  set -e
  PATH=${INSTALLPREFIX}/bin:${PATH}
  mkdir -p ${BUILDPREFIX}/newlib
  cd ${BUILDPREFIX}/newlib
  CFLAGS_FOR_TARGET="-DPREFER_SIZE_OVER_SPEED=1 -Os" \
  ../../newlib/configure                             \
      --target=riscv32-unknown-elf                   \
      --prefix=${INSTALLPREFIX}                      \
      --with-arch=${DEFAULTARCH}                     \
      --with-abi=${DEFAULTABI}                       \
      --enable-multilib                              \
      --disable-newlib-fvwrite-in-streamio           \
      --disable-newlib-fseek-optimization            \
      --enable-newlib-nano-malloc                    \
      --disable-newlib-unbuf-stream-opt              \
      --enable-target-optspace                       \
      --enable-newlib-reent-small                    \
      --disable-newlib-wide-orient                   \
      --disable-newlib-io-float                      \
      --enable-newlib-nano-formatted-io              \
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS}
  make install
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building newlib, check log file!" > /dev/stderr
  exit 1
fi

# Pico-libc
# TODO: Build and install picolibc in its various configurations

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
      --with-multilib-generator="rv32e-ilp32e-- rv32ima-ilp32-- rv64ima-lp64-- rv64imaf-lp64-- rv64imaf-lp64f--" \
      --with-arch=${DEFAULTARCH}                          \
      --with-abi=${DEFAULTABI}                            \
      ${EXTRA_OPTS}
  make -j${PARALLEL_JOBS}
  make install
) > ${LOGFILE} 2>&1
if [ $? -ne 0 ]; then
  echo "Error building GCC, check log file!" > /dev/stderr
  exit 1
fi

echo "Build completed successfully."
