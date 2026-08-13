#!/bin/sh
set -eu

CLAMD_CONFIG="/etc/clamav/clamd.conf"
FRESHCLAM_CONFIG="/etc/clamav/freshclam.conf"
CLAMD_LOG="/var/log/clamav/clamd.log"

echo
echo "========================================"
echo " Updating ClamAV signatures"
echo "========================================"

if ! freshclam --config-file="$FRESHCLAM_CONFIG"; then
    echo
    echo "Initial FreshClam update failed."
    echo "Retrying with verbose output..."
    echo

    if ! freshclam \
        --config-file="$FRESHCLAM_CONFIG" \
        --verbose
    then
        echo "ERROR: FreshClam update failed."
        exit 1
    fi
fi

echo
echo "========================================"
echo " Starting clamd"
echo "========================================"

mkdir -p /run/clamav /var/log/clamav

chown clamav:clamav /run/clamav
chown clamav:clamav /var/log/clamav

rm -f \
    /run/clamav/clamd.sock \
    /run/clamav/clamd.pid

: > "$CLAMD_LOG"
chown clamav:clamav "$CLAMD_LOG"

echo "Starting clamd daemon..."

clamd --config-file="$CLAMD_CONFIG"

echo
echo "Waiting for clamd to load the signature databases..."

if ! clamdscan \
    --config-file="$CLAMD_CONFIG" \
    --ping=120:2
then
    echo
    echo "ERROR: clamd did not become ready."
    echo
    echo "Last 100 lines of clamd.log:"
    tail -n 100 "$CLAMD_LOG" || true
    exit 1
fi

echo
echo "clamd is ready."

echo
echo "ClamAV version:"
clamdscan \
    --config-file="$CLAMD_CONFIG" \
    --version || true

echo
echo "Last clamd startup messages:"
tail -n 30 "$CLAMD_LOG" || true

echo
