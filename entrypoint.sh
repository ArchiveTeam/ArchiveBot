#!/usr/bin/env bash
set -ex
# lets try to catch and relay signals...
function sig_handler {
    echo "Caught signal, forwarding to child process..."
    kill -s TERM $child
    wait $child
    exit $?
}
trap sig_handler SIGTERM SIGINT

ACTION=$1
COUCHDB_URL=${ARCHIVEBOT_COUCHDB_URL:-http://couchdb:5984/archivebot}
COUCHDB_URL_NO_USER_PASS=$(echo $COUCHDB_URL | sed -E 's#(https?://)([^:]+:[^@]+@)(.*)#\1\3#')
COUCHDB_USER_PASS=$(echo $COUCHDB_URL | sed -E 's#https?://([^:]+):([^@]+)@.*#\1:\2#' || '')
IRC_URL=${ARCHIVEBOT_IRC_URL:-ircs://irc.hackint.org:6697}
REDIS_URL=${ARCHIVEBOT_REDIS_URL:-redis://redis:6379/0}
ZEROMQ_URL=${ARCHIVEBOT_ZEROMQ_URL:-tcp://updates-listener:12345}
ZEROMQ_BIND_URL=${ARCHIVEBOT_ZEROMQ_BIND_URL:-tcp://0.0.0.0:12345}
DASHBOARD_URL=${ARCHIVEBOT_DASHBOARD_URL:-http://0.0.0.0:4567}

IRC_CHANNEL=${ARCHIVEBOT_IRC_CHANNEL:-#notarchivebot}
IRC_NICK=${ARCHIVEBOT_IRC_NICK:-NotArchiveBot7}

# Sleep while CouchDB is starting up
function wait_for_couchdb {
    while true; do
        echo $COUCHDB_URL
        RET_CODE=$(curl -s -o /dev/null -w "%{http_code}" $COUCHDB_URL || true)
        if [ $? -eq 0 ] && [ $RET_CODE -eq 200 ]; then
            break
        fi
        echo "Waiting for CouchDB to start..."
        sleep 10
    done
}

# - [ ] ```(cd /home/archivebot/ArchiveBot/bot && bundle exec ruby bot.rb -s "ircs://irc.hackint.org:6697" -r "redis://127.0.0.1:6379/0" -c "#notarchivebot" -n Puppeteer)```
# - [ ] ```(cd /home/archivebot/ArchiveBot && export REDIS_URL=redis://127.0.0.1:6379/0 UPDATES_CHANNEL=updates FIREHOSE_SOCKET_URL=tcp://127.0.0.1:12345 && plumbing/updates-listener | plumbing/log-firehose) &```
# - [ ] ```(cd /home/archivebot/ArchiveBot && bundle exec ruby dashboard/app.rb -u http://0.0.0.0:4567) &```
# - [ ] ```(cd /home/archivebot/ArchiveBot && FIREHOSE_SOCKET_URL=tcp://127.0.0.1:12345 plumbing/firehose-client | python3 dashboard/websocket.py) &
# - [ ] ```(cd /home/archivebot/ArchiveBot/cogs && bundle exec ruby start.rb) &```
# - [ ] ```(cd /home/archivebot/ArchiveBot/plumbing && REDIS_URL=redis://127.0.0.1:6379/0 UPDATES_CHANNEL=updates ./analyzer) ```
# - [ ] ```(cd /home/archivebot/ArchiveBot/plumbing && REDIS_URL=redis://127.0.0.1:6379/0 UPDATES_CHANNEL=updates ./trimmer >/dev/null) &```

function switcher {
    case $ACTION in
    ircbot)
        cd /home/archivebot/ArchiveBot/bot
        REDIS_URL=$REDIS_URL COUCHDB_URL=$COUCHDB_URL \
        sudo -E -u archivebot \
        bundle exec ruby bot.rb \
        -s "$IRC_URL" \
        -r "$REDIS_URL" \
        -c "$IRC_CHANNEL" \
        -n "$IRC_NICK" \
        --db-credentials="$COUCHDB_USER_PASS"
        ;;
    updates-listener)
        cd /home/archivebot/ArchiveBot
        REDIS_URL=$REDIS_URL UPDATES_CHANNEL=updates \
        sudo -E -u archivebot plumbing/updates-listener | \
        FIREHOSE_SOCKET_URL=$ZEROMQ_BIND_URL REDIS_URL=$REDIS_URL \
        sudo -E -u archivebot plumbing/log-firehose
        ;;
    dashboard)
        cd /home/archivebot/ArchiveBot
        COUCHDB_URL=$COUCHDB_URL REDIS_URL=$REDIS_URL \
        sudo -E -u archivebot \
        bundle exec ruby dashboard/app.rb -u $DASHBOARD_URL
        ;;
    websocket)
        cd /home/archivebot/ArchiveBot
        COUCHDB_URL=$COUCHDB_URL FIREHOSE_SOCKET_URL=$ZEROMQ_URL REDIS_URL=$REDIS_URL \
        sudo -E -u archivebot plumbing/firehose-client | \
        sudo -E -u archivebot \
        python3 dashboard/websocket.py
        ;;
    cogs)
        cd /home/archivebot/ArchiveBot/cogs
        COUCHDB_URL=$COUCHDB_URL REDIS_URL=$REDIS_URL \
        sudo -E -u archivebot \
        bundle exec ruby start.rb \
        --db "$COUCHDB_URL_NO_USER_PASS" \
        --db-credentials "$COUCHDB_USER_PASS" \
        --log-db "${COUCHDB_URL_NO_USER_PASS}_logs" \
        --log-db-credentials "$COUCHDB_USER_PASS"
        ;;
    analyzer)
        cd /home/archivebot/ArchiveBot/plumbing
        COUCHDB_URL=$COUCHDB_URL UPDATES_CHANNEL=updates REDIS_URL=$REDIS_URL \
        sudo -E -u archivebot ./analyzer
        ;;
    trimmer)
        cd /home/archivebot/ArchiveBot/plumbing
        COUCHDB_URL=$COUCHDB_URL UPDATES_CHANNEL=updates REDIS_URL=$REDIS_URL \
        sudo -E -u archivebot ./trimmer >/dev/null
        ;;
    help)
        echo "Available actions: ircbot, updates-listener, dashboard, websocket, cogs, analyzer, trimmer"
        ;;
    *)
        echo "Invalid action: $ACTION"
        exit 1
        ;;
    esac
}


function main {
    wait_for_couchdb
    switcher
}

main
