FROM alpine:3.20
RUN apk add --no-cache --virtual=.run-deps \
    openssh tini autossh bash inotify-tools curl ca-certificates && \
    addgroup pipeline && \
    adduser -D -G pipeline pipeline -s /bin/false && \
    mkdir -p /home/pipeline/.ssh && \
    chown pipeline:pipeline /home/pipeline/.ssh && \
    passwd -u pipeline && \
    # Add matchgroup pipeline to /etc/ssh/sshd_config
    # Only allow port valkey:6379 to be forwarded
    cat <<EOF >>/etc/ssh/sshd_config
Match Group pipeline
    PasswordAuthentication no
    AllowTcpForwarding yes
    X11Forwarding no
    PermitTunnel no
    GatewayPorts no
    AllowStreamLocalForwarding no
    AllowAgentForwarding no
    PermitOpen valkey:6379
    ForceCommand echo 'This account can only be used for port forwarding'
    AuthorizedKeysFile /home/%u/.ssh/authorized_keys
EOF
COPY containers/openssh.entrypoint.sh /_ssh_entrypoint.sh
ENTRYPOINT ["/sbin/tini", "--", "/_ssh_entrypoint.sh"]
VOLUME /etc/ssh/sshd_config.d
EXPOSE 22
