#!/bin/bash

# Copyright (C) 2021 Embecosm Limited
# Contributor Jeremy Bennett <jeremy.bennett@embecosm.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# This file is a script to run a single test from the GCC testsuite on NIOSV
# using a configurable target board and tool chain.

TOPDIR="$(dirname $(cd $(dirname $0) && echo $PWD))"

export PATH=${TOPDIR}/install/bin:$PATH
export NIOSV_TIMEOUT=30
export NIOSV_TRIPLE=riscv32-unknown-elf
export DEJAGNU=${TOPDIR}/toolchain/site.exp

# Sort out arguments
commname=$0
testdir=gcc.c-torture
board=cyclone
expfile=execute.exp
testname=
verbosity=

while (( "$#" ))
do
    case "$1"
    in
	--testdir)
	    testdir=$2
	    shift 2
	    ;;
	--baseboard)
	    board=$2
	    shift 2
	    ;;
	--expfile)
	    expfile=$2
	    shift 2
	    ;;
	--testname)
	    testname=$2
	    shift 2
	    ;;
	--timeout)
	    NIOSV_TIMEOUT=$2
	    shift 2
	    ;;
	-v)
	    verbosity="-v ${verbosity}"
	    shift
	    ;;
	--help)
	    echo "Usage: ${commname} [--testdir <testdir>] [--baseboard <baseboard>"
	    echo "           [--expfile <expect file>] [--testname <string>]"
	    echo "           [--timeout <seconds>] [--help]"
	    exit 0
	    ;;
	*)
	    echo "Unknown argument $1: ignored"
	    shift
	    ;;
    esac
done

if [ "x${testname}" != "x" ]
then
    testname="=${testname}"
fi

runtest ${verbosity} --tool=gcc --tool_exec=riscv32-unknown-elf-gcc  --tool_opts= \
	--directory=${TOPDIR}/gcc/gcc/testsuite/${testdir} \
	--srcdir=${TOPDIR}/gcc/gcc/testsuite \
	--target_board=${board} --target=riscv32-unknown-elf "${expfile}${testname}"
