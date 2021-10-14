TOPDIR="$(dirname $(cd $(dirname $0) && echo $PWD))"

export PATH=${TOPDIR}/install/bin:$PATH
export DEJAGNU=${TOPDIR}/toolchain/site.exp
runtest  --tool=gcc --target_board='cyclone' 2>&1 | tee testinggcc.log
