#!/usr/bin/env bash
# support 2 modes: openssh, autossh
# openssh: just run sshd
# autossh: run autossh, create ssh key if not exist,
# then create a sshd config snippet / users / groups
# to allow to forward redis:6379 ONLY

set -ex
MODE=$1
mkdir -p /home/pipeline/.ssh/ /autossh/
touch /home/pipeline/.ssh/authorized_keys

# Try getting my IP from /etc/ssh/sshd_config.d/.my_ip
if [ -f /etc/ssh/sshd_config.d/.my_ip ]; then
    IP=$(cat /etc/ssh/sshd_config.d/.my_ip)
    # try /autossh/.my_ip
elif [ -f /autossh/.my_ip ]; then
    IP=$(cat /autossh/.my_ip)
else
    IP=$(curl -fsL https://ipv4.icanhazip.com)
    echo $IP >/etc/ssh/sshd_config.d/.my_ip
    echo $IP >/autossh/.my_ip
fi
IP_DASHES=$(echo $IP | tr . -)
AUTOSSH_TARGET=${ARCHIVEBOT_PIPE_AUTOSSH_TARGET:-archivebot.backend.example.com}
function reconcile {
    chown -R pipeline:pipeline /home/pipeline/.ssh
    chmod 700 /home/pipeline/.ssh
    chmod 600 /home/pipeline/.ssh/authorized_keys
}
case $MODE in
openssh)
    ssh-keygen -A
    mkdir -p /home/pipeline/.ssh
    reconcile
    # listen for changes in /etc/ssh, then sighup sshd if found.
    exec /usr/sbin/sshd -D -e &
    # wait for changes in any folder or file in /etc/ssh OR /home/pipeline/.ssh, then reconcile and sighup sshd
    inotifywait -m -r -e modify,create,delete,move /etc/ssh /home/pipeline/.ssh | while read path action file; do
        reconcile
        pkill -HUP sshd
    done
    wait
    ;;
autossh)
    # Check if SSH key exists, if not, generate one
    if [ ! -f /autossh/id_ed25519 ]; then
        ssh-keygen -t ed25519 -f /autossh/id_ed25519 -C "pipeline@$IP"
        set +e
        # Give a tutorial on what to do on the server end
        echo "echo $(cat /autossh/id_ed25519.pub) >> /home/pipeline/.ssh/authorized_keys"
        set -e
        sleep 10
        echo "Giving you 10 seconds to do the above..."
    fi
    # Now try connecting!
    echo "Please ensure key: $(cat /autossh/id_ed25519.pub) is in /home/pipeline/.ssh/authorized_keys on $AUTOSSH_TARGET"
    autossh \
        -M 0 \
        -N \
        -o "ServerAliveInterval 60" \
        -o "ServerAliveCountMax 3" \
        -o "ExitOnForwardFailure yes" \
        -o "StrictHostKeyChecking no" \
        -o "UserKnownHostsFile /dev/null" \
        -L 0.0.0.0:6379:valkey:6379 \
        -i /autossh/id_ed25519 \
        $AUTOSSH_TARGET
    ;;
*)
    echo "Invalid mode specified."
    exit 1
    ;;
esac
