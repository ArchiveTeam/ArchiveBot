FROM alpine:3.20
RUN apk add --no-cache --virtual=.run-deps \
    valkey tini bash sed
COPY containers/valkey.conf /etc/valkey.conf
COPY containers/valkey.entrypoint.sh /valkey.entrypoint.sh
ENTRYPOINT ["/sbin/tini", "--", "/valkey.entrypoint.sh", "valkey-server", "/etc/valkey.conf"]
VOLUME /data
EXPOSE 6379
