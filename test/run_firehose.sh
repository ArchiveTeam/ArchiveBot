#!/bin/bash

export REDIS_URL=redis://localhost:6379/0
export UPDATES_CHANNEL=updates
export FIREHOSE_SOCKET_URL=tcp://127.0.0.1:12345
plumbing/updates-listener | plumbing/log-firehose
