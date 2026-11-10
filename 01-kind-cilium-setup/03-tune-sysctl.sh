#!/usr/bin/env bash
# Raise inotify limits for multi-node kind clusters.
# Source: https://kind.sigs.k8s.io/docs/user/known-issues/
set -euo pipefail

CONF=/etc/sysctl.d/99-kind.conf

sudo tee "$CONF" >/dev/null <<EOF
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF

sudo sysctl --system >/dev/null
grep . /proc/sys/fs/inotify/max_user_*
