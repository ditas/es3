#!/bin/bash
if [ -n "${1}" ]
then
    PROFILE=${1}
else
    echo "Usage: test.sh <profile>"
    exit 1
fi

#./rebar3 upgrade
./rebar3 as $PROFILE release

./_build/$PROFILE/rel/es3/bin/es3 start
./rebar3 ct --suite=test/es3_SUITE --config ./config/test/ct.args
./_build/$PROFILE/rel/es3/bin/es3 stop
