#!/bin/sh
set -eu

CLAMD_CONFIG="/etc/clamav/clamd.conf"
FRESHCLAM_CONFIG="/etc/clamav/freshclam.conf"

DB_DIR="/var/lib/clamav"
CLAMD_LOG="/var/log/clamav/clamd.log"

# Set true/1/yes/on to skip all network update attempts and use the
# persistent or image-seeded signature database exactly as it exists.
SKIP_FRESHCLAM="${SKIP_FRESHCLAM:-false}"


required_database_present()
{
    directory="$1"

    if { [ -f "$directory/main.cvd" ] || [ -f "$directory/main.cld" ]; } && \
       { [ -f "$directory/daily.cvd" ] || [ -f "$directory/daily.cld" ]; }; then
        return 0
    fi

    return 1
}


show_database_files()
{
    echo "Signature database files:"

    found=0

    for file in \
        "$DB_DIR"/*.cvd \
        "$DB_DIR"/*.cld
    do
        [ -f "$file" ] || continue
        ls -lh "$file"
        found=1
    done

    if [ "$found" -eq 0 ]; then
        echo "  (none)"
    fi
}


case "$SKIP_FRESHCLAM" in
    1|true|TRUE|yes|YES|on|ON)
        UPDATE_MODE="skip"
        ;;

    0|false|FALSE|no|NO|off|OFF|'')
        UPDATE_MODE="update"
        ;;

    *)
        echo "ERROR: SKIP_FRESHCLAM must be a boolean value."
        echo "Accepted true values: 1, true, yes, on"
        echo "Accepted false values: 0, false, no, off"
        echo "Received: $SKIP_FRESHCLAM"
        exit 1
        ;;
esac


echo
echo "========================================"
echo " ClamAV signature database"
echo "========================================"

if [ "$UPDATE_MODE" = "skip" ]; then
    echo "SKIP_FRESHCLAM is enabled."
    echo "Skipping network signature update."

    if ! required_database_present "$DB_DIR"; then
        echo
        echo "ERROR: FreshClam was skipped but no usable signature database exists."
        echo "Expected main.cvd/main.cld and daily.cvd/daily.cld under:"
        echo "  $DB_DIR"
        exit 1
    fi
else
    echo "Attempting FreshClam signature update..."

    if ! freshclam --config-file="$FRESHCLAM_CONFIG"; then
        echo
        echo "Initial FreshClam update failed."
        echo "Retrying once with verbose output..."
        echo

        if ! freshclam \
            --config-file="$FRESHCLAM_CONFIG" \
            --verbose
        then
            echo
            echo "WARNING: FreshClam could not update signatures."

            if required_database_present "$DB_DIR"; then
                echo "A usable persistent/image-seeded signature database is available."
                echo "Continuing in offline/fallback mode with the existing signatures."
            else
                echo
                echo "ERROR: FreshClam failed and no usable signature database exists."
                exit 1
            fi
        fi
    fi
fi

echo
show_database_files


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

# check_files.sh normally creates/truncates this file before this script.
# Use touch here instead of truncating it again so this startup helper does
# not unexpectedly destroy an existing daemon log if invoked manually.
touch "$CLAMD_LOG"
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
