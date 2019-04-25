#!/usr/bin/env bash

#export RELX_REPLACE_OS_VARS=true

for i in `seq 1 3`;
do
    ./rebar3 as test_$i release
    export NODE_NAME=node_$i
    export PORT=555$i
    export CHUNK_SIZE=500
    _build/test_$i/rel/es3/bin/es3 foreground &
    sleep 5
done

./rebar3 ct --suite=test/es3_SUITE --config ./config/test/ct.args

for i in `seq 1 3`;
do
    _build/test_$i/rel/es3/bin/es3 stop
done
