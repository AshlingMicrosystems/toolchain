#!/bin/bash
# Script for describing all the sources that went into a build

# Copyright (C) 2020 Embecosm Limited

# Contributor: Simon Cook <simon.cook@embecosm.com>

# SPDX-License-Identifier: GPL-3.0-or-later

TOP=${PWD}

# Print header
cat << EOF
The following sources were used in this build:

EOF

REPOS=$(find . -type d -name .git)
for dir in $REPOS; do
  cd $(dirname $TOP/$dir)
  if [ $PWD == $TOP ]; then
    echo -n "build-scripts: "
  else
    echo -n "$(echo $PWD | sed "s#$TOP/##"): "
  fi

  # Extract git commit and URL
  # FIXME: Assumes remote name is origin
  GITREV=$(git rev-parse HEAD)
  GITURL=$(git remote get-url origin)

  echo "${GITREV} (${GITURL})"

done
