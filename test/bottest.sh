#!/bin/bash
./run_bot.sh &
botpid=$!
sleep 30
kill $botpid
