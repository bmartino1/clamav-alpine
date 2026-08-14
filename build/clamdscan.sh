#!/bin/sh

# Do not use "set -e" here.
# clamdscan returns 1 when malware is found, and that is a completed scan
# condition that this wrapper must handle explicitly rather than abort on.
set -u

CLAMD_CONFIG="/etc/clamav/clamd.conf"

CLAMD_LOG="/var/log/clamav/clamd.log"
SCAN_LOG="/var/log/clamav/log.log"
SUMMARY_LOG="/var/log/clamav/scan_summary.txt"

# Multiple folders may be supplied as space-separated container paths.
SCAN_FOLDERS="${SCAN_FOLDERS:-/scan}"

# Managed exclusion paths are written into clamd.conf by
# apply_exclude_paths.sh before clamd starts.
EXCLUDE_PATHS="${EXCLUDE_PATHS:-}"

FOUND_TMP="/tmp/clamdscan-found.$$"
TAIL_PID=""

cleanup()
{
    if [ -n "$TAIL_PID" ]; then
        kill "$TAIL_PID" 2>/dev/null || true
        wait "$TAIL_PID" 2>/dev/null || true
    fi

    rm -f "$FOUND_TMP"
}

trap cleanup EXIT INT TERM

show_exclusion_report()
{
    echo "========================================"
    echo " ACTIVE SCAN EXCLUSIONS"
    echo "========================================"
    echo

    echo "Docker-managed paths (EXCLUDE_PATHS):"

    if [ -n "$EXCLUDE_PATHS" ]; then
        for path in $EXCLUDE_PATHS
        do
            if [ -e "$path" ]; then
                echo "  $path  [present]"
            else
                echo "  $path  [not present]"
            fi
        done
    else
        echo "  (none)"
    fi

    echo
    echo "Effective ExcludePath rules from $CLAMD_CONFIG:"

    if grep -Eq '^[[:space:]]*ExcludePath[[:space:]]+' "$CLAMD_CONFIG" 2>/dev/null; then
        awk '
            /^[[:space:]]*ExcludePath[[:space:]]+/ {
                line = $0
                sub(/^[[:space:]]*/, "", line)
                print "  " line
            }
        ' "$CLAMD_CONFIG"
    else
        echo "  (none)"
    fi

    echo
}

append_scan_configuration()
{
    {
        echo
        echo "========================================"
        echo " SCAN CONFIGURATION"
        echo "========================================"
        echo
        echo "Scan folders:"
        for folder in $SCAN_FOLDERS
        do
            echo "  $folder"
        done
        echo
        show_exclusion_report
    } >> "$SCAN_LOG"
}

echo
echo "========================================"
echo " Starting ClamAV clamdscan"
echo "========================================"
echo
echo "Scan folders:"
for folder in $SCAN_FOLDERS
do
    echo "  $folder"
done
echo
echo "Started: $(date)"
echo

# Show the exclusions immediately before scanning. This reports both the
# friendly Docker environment paths and every active ExcludePath directive,
# including manual end-user rules outside the managed block.
show_exclusion_report

# clamd.conf has LogClean yes, so clamd writes file-by-file scan activity to
# clamd.log. Follow only new lines and forward them to Docker/Dockge/Unraid
# stdout while the scan is running.
echo "Starting live clamd log monitor..."
echo "Every file processed by clamd should appear below."
echo

tail -n 0 -F "$CLAMD_LOG" &
TAIL_PID=$!

echo "Monitoring clamd.log with PID: $TAIL_PID"
echo
echo "----------------------------------------"
echo

SCAN_ERROR=0

for folder in $SCAN_FOLDERS
do
    echo
    echo "========================================"
    echo " Scanning: $folder"
    echo "========================================"
    echo

    # Remember where clamd.log was before this folder started. This prevents
    # FOUND records from an earlier scan folder from being reported again for
    # later folders.
    if [ -f "$CLAMD_LOG" ]; then
        CLAMD_START_LINE="$(wc -l < "$CLAMD_LOG" | tr -d ' ')"
    else
        CLAMD_START_LINE=0
    fi

    clamdscan \
        --config-file="$CLAMD_CONFIG" \
        --fdpass \
        --infected \
        --verbose \
        --multiscan \
        --log="$SCAN_LOG" \
        --stdout \
        "$folder"

    SCAN_RC=$?

    case "$SCAN_RC" in
        0)
            echo
            echo "Completed scan of $folder: CLEAN"
            ;;

        1)
            echo
            echo "Completed scan of $folder: INFECTED FILE(S) FOUND"
            ;;

        *)
            echo
            echo "ERROR: clamdscan returned $SCAN_RC while scanning $folder"
            SCAN_ERROR="$SCAN_RC"
            ;;
    esac

    # Collect only FOUND records written while THIS folder was being scanned.
    awk -v start="$CLAMD_START_LINE" '
        NR > start && / FOUND/ { print }
    ' "$CLAMD_LOG" > "$FOUND_TMP" 2>/dev/null || true

    if [ -s "$FOUND_TMP" ]; then
        echo
        echo "Infected file found in $folder."

        {
            echo "========================================"
            echo "Infected file(s) found in: $folder"
            echo "========================================"
            cat "$FOUND_TMP"
            echo
        } >> "$SUMMARY_LOG"
    fi

done

# Stop the live monitor before printing the final report.
cleanup
TAIL_PID=""

# Add scan inputs and the effective exclusion rules to the persistent
# clamdscan report. This makes the saved log self-describing even when the
# Docker stdout log is no longer available.
append_scan_configuration

echo
echo
echo "========================================"
echo " SCAN FINISHED"
echo "========================================"
echo
echo "Finished: $(date)"
echo
echo "========================================"
echo " CLAMDSCAN SUMMARY"
echo "========================================"
echo

cat "$SCAN_LOG"

echo
echo "========================================"
echo " INFECTED FILE SUMMARY"
echo "========================================"
echo

if [ -s "$SUMMARY_LOG" ]; then
    cat "$SUMMARY_LOG"
else
    echo "No infected files were found."
    echo "No infected files were found." > "$SUMMARY_LOG"
fi

echo
echo "========================================"
echo " SAVED LOG FILES"
echo "========================================"
echo
echo "Live daemon/file log:"
echo "  $CLAMD_LOG"
echo
echo "Clamdscan summary and scan configuration:"
echo "  $SCAN_LOG"
echo
echo "Detected-file summary:"
echo "  $SUMMARY_LOG"
echo

if [ "$SCAN_ERROR" -ne 0 ]; then
    echo "ClamAV scan completed with an error."
    exit "$SCAN_ERROR"
fi

echo "ClamAV scan completed."
exit 0
