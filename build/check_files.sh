#!/bin/sh
set -eu

BUILD_DIR="/build"
CONFIG_DIR="/etc/clamav"
LOG_DIR="/var/log/clamav"
HISTORY_DIR="$LOG_DIR/history"

CLAMD_CONFIG="$CONFIG_DIR/clamd.conf"
FRESHCLAM_CONFIG="$CONFIG_DIR/freshclam.conf"

DEFAULT_CLAMD_CONFIG="$BUILD_DIR/clamd.conf"
DEFAULT_FRESHCLAM_CONFIG="$BUILD_DIR/freshclam.conf"

CLAMD_LOG="$LOG_DIR/clamd.log"
SCAN_LOG="$LOG_DIR/log.log"
SUMMARY_LOG="$LOG_DIR/scan_summary.txt"

# Restore one maintainer-provided config file ONLY when the runtime file is
# missing. Existing files belong to the end user and must not be replaced,
# appended to, chmod'd, chown'd, or otherwise modified here.
ensure_config_file()
{
    target="$1"
    default_file="$2"
    label="$3"

    if [ -f "$target" ]; then
        echo "Found existing $label: $target"
        echo "Preserving existing $label unchanged."
        return 0
    fi

    # If something exists at the requested path but it is not a regular file,
    # do not destroy or replace it. Stop and make the problem visible.
    if [ -e "$target" ] || [ -L "$target" ]; then
        echo "ERROR: $target exists but is not a regular file."
        echo "Refusing to replace or modify it."
        exit 1
    fi

    if [ ! -f "$default_file" ]; then
        echo "ERROR: Maintainer default is missing from the image: $default_file"
        exit 1
    fi

    echo "Missing $label: $target"
    echo "Seeding maintainer default from: $default_file"

    cp "$default_file" "$target"
    chmod 0644 "$target"

    echo "Created: $target"
}

echo "========================================"
echo " ClamAV filesystem/configuration check"
echo "========================================"

echo "Creating required directories..."

mkdir -p \
    "$CONFIG_DIR" \
    /var/lib/clamav \
    "$LOG_DIR" \
    "$HISTORY_DIR" \
    /run/clamav

echo
echo "Checking required configuration files..."

ensure_config_file \
    "$CLAMD_CONFIG" \
    "$DEFAULT_CLAMD_CONFIG" \
    "clamd.conf"

echo

ensure_config_file \
    "$FRESHCLAM_CONFIG" \
    "$DEFAULT_FRESHCLAM_CONFIG" \
    "freshclam.conf"

echo
echo "Configuration files are ready."
echo "Existing end-user configuration was not modified."

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
echo "Setting permissions for required runtime directories..."

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
echo "Configuration/filesystem check complete."
