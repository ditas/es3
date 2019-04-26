#!/usr/bin/env bash

#export RELX_REPLACE_OS_VARS=true

if [ -n "${1}" ]
then
    PROFILE=${1}
else
    echo "Usage: test.sh <profile>"
    exit 1
fi

export NODE_NAME=node_1
export PORT=5551
export CHUNK_SIZE=1000000

#./rebar3 upgrade
./rebar3 as $PROFILE release

./_build/$PROFILE/rel/es3/bin/es3 console