#!/bin/bash

export REDIS_URL=redis://localhost:6379/0
export FIREHOSE_SOCKET_URL=tcp://127.0.0.1:12345
bundle exec ruby plumbing/firehose-client | bundle exec ruby dashboard/app.rb
