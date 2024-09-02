#!/usr/bin/env bash
set -ex
BOOT=$(date -u +"%Y-%m-%dT%H-%M-%SZ")

CONCURRENCY=${ARCHIVEBOT_PIPE_CONCURRENCY:-2}
NAME=${ARCHIVEBOT_PIPE_NAME:-pipeline}
ARCHIVEBOT_PIPE_LOGS_DIR=${ARCHIVEBOT_PIPE_LOGS_DIR:-/pipeline/logs}
ARCHIVEBOT_PIPE_AO_ONLY=${ARCHIVEBOT_PIPE_AO_ONLY:-0}
ARCHIVEBOT_PIPE_LARGE=${ARCHIVEBOT_PIPE_LARGE:-0}
# set AO_ONLY only if ARCHIVEBOT_PIPE_AO_ONLY is different than 0
if [ "$ARCHIVEBOT_PIPE_AO_ONLY" -ne 0 ]; then
    AO_ONLY=1
fi
# set LARGE only if ARCHIVEBOT_PIPE_LARGE is different than 0
if [ "$ARCHIVEBOT_PIPE_LARGE" -ne 0 ]; then
    LARGE=1
fi

chown -R archivebot:archivebot /pipeline &
chown -R archivebot:archivebot /home/archivebot/ArchiveBot/pipeline/ &
wait
cd /home/archivebot/ArchiveBot/pipeline/
export OPENSSL_CONF=${ARCHIVEBOT_PIPE_OPENSSL_CONF:-/home/archivebot/ArchiveBot/ops/openssl-less-secure.cnf}
export REDIS_URL=${ARCHIVEBOT_PIPE_REDIS_URL:-redis://autossh:6379/0}
export NO_SCREEN=1
exec sudo -E -u archivebot \
    run-pipeline3 pipeline.py \
    --disable-web-server \
    --concurrent $CONCURRENCY \
    $NAME \
    | tee $ARCHIVEBOT_PIPE_LOGS_DIR/$BOOT.log.zst
