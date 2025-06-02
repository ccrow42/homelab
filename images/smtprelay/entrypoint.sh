#!/bin/bash
set -e

# Copy postfix config
cp /config/main.cf /etc/postfix/main.cf

# Start Postfix in foreground
exec /usr/sbin/postfix -c /etc/postfix start-fg
