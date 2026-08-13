#!/bin/sh
set -eu

LOG_DIR="/var/log/clamav"
HISTORY_DIR="$LOG_DIR/history"

CLAMD_LOG="$LOG_DIR/clamd.log"
SCAN_LOG="$LOG_DIR/log.log"
SUMMARY_LOG="$LOG_DIR/scan_summary.txt"

echo "========================================"
echo " ClamAV filesystem/configuration check"
echo "========================================"

echo "Creating required directories..."

mkdir -p \
    /var/lib/clamav \
    "$LOG_DIR" \
    "$HISTORY_DIR" \
    /run/clamav

echo
echo "Checking required configuration files..."

for file in \
    /etc/clamav/clamd.conf \
    /etc/clamav/freshclam.conf
do
    if [ ! -f "$file" ]; then
        echo "ERROR: Required file is missing: $file"
        exit 1
    fi

    echo "Found: $file"
done

echo
echo "Checking for logs from a previous run..."

PREVIOUS_RUN=0

for file in \
    "$CLAMD_LOG" \
    "$SCAN_LOG" \
    "$SUMMARY_LOG"
do
    if [ -s "$file" ]; then
        PREVIOUS_RUN=1
    fi
done

if [ "$PREVIOUS_RUN" -eq 1 ]; then

    RUN_STAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
    ARCHIVE_DIR="$HISTORY_DIR/$RUN_STAMP"

    echo "Previous scan data found."
    echo "Archiving previous run to:"
    echo "  $ARCHIVE_DIR"

    mkdir -p "$ARCHIVE_DIR"

    for file in \
        "$CLAMD_LOG" \
        "$SCAN_LOG" \
        "$SUMMARY_LOG"
    do
        if [ -e "$file" ]; then
            cp -a "$file" "$ARCHIVE_DIR/"
        fi
    done

    {
        echo "ClamAV previous-run archive"
        echo "Archived: $(date)"
        echo
        echo "This directory contains the logs that existed"
        echo "before the next one-shot scan was started."
        echo
        echo "This may represent:"
        echo "  - a completed previous scan"
        echo "  - an interrupted scan"
        echo "  - a manually restarted scan"
    } > "$ARCHIVE_DIR/run-info.txt"

    echo "Previous run preserved."

else

    echo "No previous scan logs need archiving."

fi

echo
echo "Preparing clean active log files..."

: > "$CLAMD_LOG"
: > "$SCAN_LOG"
: > "$SUMMARY_LOG"

echo
echo "Setting permissions for required directories..."

chown -R clamav:clamav /var/lib/clamav
chown -R clamav:clamav "$LOG_DIR"
chown -R clamav:clamav /run/clamav

chmod 0755 /var/lib/clamav
chmod 0755 "$LOG_DIR"
chmod 0755 "$HISTORY_DIR"
chmod 0755 /run/clamav

rm -f \
    /run/clamav/clamd.sock \
    /run/clamav/clamd.pid \
    /run/clamav/freshclam.pid

echo
echo "ClamAV engine:"
clamscan --version || true

echo
echo "Configuration check complete."
