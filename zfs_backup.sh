#!/bin/bash

NOW=$(date +%Y%m%d)
SNAPSHOT_NAME="auto-$NOW"
DATASET="vmail"
REMOTE_HOST=""
REMOTE_USER=""
REMOTE_PASS=""

echo "[$(date)] Preparing target side..."
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} \
  "sudo zfs list -H -t snapshot -o name | grep '^${DATASET}@auto-' | xargs -r -n1 sudo zfs destroy -r 2>/dev/null || echo>

echo "[$(date)] Preparing source side..."
sudo zfs destroy -r ${DATASET}@${SNAPSHOT_NAME} 2>/dev/null || true

echo "[$(date)] Creating snapshot ${DATASET}@${SNAPSHOT_NAME}"
sudo zfs snapshot ${DATASET}@${SNAPSHOT_NAME}

echo "[$(date)] Sending snapshot to ${REMOTE_USER}@${REMOTE_HOST}"
sudo zfs send ${DATASET}@${SNAPSHOT_NAME} | \
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no ${REMOTE_USER}@${REMOTE_HOST} \
  "sudo zfs receive -F ${DATASET}"

echo "[$(date)] Cleaning up old snapshots on source..."
sudo zfs list -H -t snapshot -o name -s creation | grep "^${DATASET}@auto-" | head -n -5 | xargs -r -n1 sudo zfs destroy

echo "[$(date)] Backup completed successfully."
