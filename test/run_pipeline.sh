#!/bin/bash

export PATH="/tmp/bin/:$PATH"
export REDIS_URL='redis://localhost:6379/0'
export RSYNC_URL='rsync://localhost/tmp/' LOG_CHANNEL='updates'
export NO_SCREEN=1 FINISHED_WARCS_DIR=/tmp/warc/

mkdir -p /tmp/rsync/
chmod o+rwx /tmp/rsync/
mkdir -p /tmp/warc/

# This will affect the wpull exe wrapper
mkdir -p /tmp/bin/
ln -s /usr/bin/python3.4 /tmp/bin/python3

echo -n 'Using '
which python3

~/.local/bin/run-pipeline3 --disable-web-server --concurrent 1 \
    pipeline/pipeline.py TestUser
