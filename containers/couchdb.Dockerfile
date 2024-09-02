FROM couchdb
EXPOSE 5984

# we init it: start it in bg, wait for it to be ready, then create the db, and some items.
COPY db/design_docs /design_docs
# start couchdb in the background
RUN set -ex && \
    echo """#!/usr/bin/env bash \n\
set -ex \n\
COUCHDB=http://\$COUCHDB_USER:\$COUCHDB_PASSWORD@127.0.0.1:5984 \n\
/docker-entrypoint.sh \$@ & \n\
sleep 5 \n\
while [ \$(curl -s -o /dev/null -w \"%{http_code}\" \$COUCHDB/_all_dbs) -ne 200 ]; do \n\
    sleep 1 \n\
done \n\
# check if database exists, if not create it \n\

if [ \$(curl -s -o /dev/null -w \"%{http_code}\" \$COUCHDB/archivebot) -ne 200 ]; then \n\
    cd /design_docs \n\
    grep -v _rev archive_urls.json > /tmp/archive_urls.json \n\
    grep -v _rev ignore_patterns.json > /tmp/ignore_patterns.json \n\
    grep -v _rev jobs.json > /tmp/jobs.json \n\
    grep -v _rev user_agents.json > /tmp/user_agents.json \n\
    curl -X PUT \$COUCHDB/_users \n\
    curl -X PUT \$COUCHDB/_replicator \n\
    curl -X PUT \$COUCHDB/_global_changes \n\
    curl -X PUT \$COUCHDB/archivebot \n\
    curl -X PUT \$COUCHDB/archivebot_logs \n\
    curl -X PUT \$COUCHDB/archivebot/_design/archive_urls -d @/tmp/archive_urls.json \n\
    curl -X PUT \$COUCHDB/archivebot/_design/ignore_patterns -d @/tmp/ignore_patterns.json \n\
    curl -X PUT \$COUCHDB/archivebot/_design/jobs -d @/tmp/jobs.json \n\
    curl -X PUT \$COUCHDB/archivebot/_design/user_agents -d @/tmp/user_agents.json\n\
    touch /_archivebot_done_db \n\
fi \n\
sync \n\
wait \n\
    """ > /_after_entrypoint.sh && \
    chmod +x /_after_entrypoint.sh && \
    cat /_after_entrypoint.sh && \
    [ -f /docker-entrypoint.sh ] && [ -f /_after_entrypoint.sh ] || exit 1

# RUN COUCHDB_USER=admin COUCHDB_PASSWORD=password /docker-entrypoint.sh /_after_entrypoint.sh "/opt/couchdb/bin/couchdb" & \
#     # when /_archivebot_done_db exists, we know the db is ready, kill ir
#     while [ ! -f /_archivebot_done_db ]; do sleep 1; done && \
#     kill $(pgrep -f "/opt/couchdb/bin/couchdb") && \
#     rm /_archivebot_done_db

ENTRYPOINT ["/usr/bin/tini", "--", "/docker-entrypoint.sh", "/_after_entrypoint.sh"]
CMD ["/opt/couchdb/bin/couchdb"]
