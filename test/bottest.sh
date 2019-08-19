#!/bin/bash
"$(dirname "$(readlink -f "$0")")"/run_bot.sh &
botpid=$!
sleep 5
kill $botpid
