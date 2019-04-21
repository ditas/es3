#!/bin/bash
if [ -n "${1}" ]
then
    PROFILE=${1}
else
    echo "Usage: console.sh <profile>"
    exit 1
fi

./rebar3 as $PROFILE release

#./_build/$PROFILE/rel/es3/bin/es3 console #eval "erlang:set_cookie(node(), test)."
./_build/$PROFILE/rel/es3/bin/es3 console
