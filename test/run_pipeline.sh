#!/bin/bash

mkdir -p /tmp/rsync/
mkdir -p /tmp/warc/

REDIS_URL='redis://localhost:6379/0' \
  RSYNC_URL='/tmp/rsync/' LOG_CHANNEL='updates' \
  NO_SCREEN=1 FINISHED_WARCS_DIR=/tmp/warc/ \
  ~/.local/bin/run-pipeline3 --disable-web-server --concurrent 1 \
    pipeline/pipeline.py TestUser
