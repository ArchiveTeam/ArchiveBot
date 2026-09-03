#!/usr/bin/env bash
set -ex

# Remove any requirepass
sed -i '/requirepass/d' /etc/valkey.conf

# Add requirepass
echo "requirepass $VALKEY_PASSWORD" >> /etc/valkey.conf

exec $@
