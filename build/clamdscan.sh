#!/bin/sh

CLAMD_CONFIG="/etc/clamav/clamd.conf"

CLAMD_LOG="/var/log/clamav/clamd.log"
SCAN_LOG="/var/log/clamav/log.log"
SUMMARY_LOG="/var/log/clamav/scan_summary.txt"

# Define folders to scan.
#
# Multiple folders can be added later, for example:
#
# SCAN_FOLDERS="/scan/appdata /scan/system"
#
SCAN_FOLDERS="${SCAN_FOLDERS:-/scan}"

echo
echo "========================================"
echo " Starting ClamAV clamdscan"
echo "========================================"
echo
echo "Scan folders:"
echo "$SCAN_FOLDERS"
echo
echo "Started: $(date)"
echo

#
# Clear the previous scan output.
#
# clamd.log is truncated so the live monitor shows THIS scan,
# rather than previous runs/startup history.
#

#
# Make sure tail is always stopped if this script exits.
#
TAIL_PID=""

cleanup()
{
    if [ -n "$TAIL_PID" ]; then
        kill "$TAIL_PID" 2>/dev/null || true
        wait "$TAIL_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

#
# This is the important part of the original design.
#
# clamd.conf has:
#
#     LogClean yes
#
# so clamd writes each scanned file into clamd.log.
#
# tail then forwards those lines directly to Docker/Dockge stdout.
#
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

    #
    # clamdscan --infected keeps its own output small.
    #
    # The detailed live file activity comes from clamd.log because
    # LogClean=yes.
    #
    # clamd.log also contains FOUND records, so collect them.
    #
    if grep -q ' FOUND' "$CLAMD_LOG" 2>/dev/null
    then
        echo
        echo "Infected file found in $folder."

        {
            echo "========================================"
            echo "Infected file(s) found in: $folder"
            echo "========================================"

            grep ' FOUND' "$CLAMD_LOG"

            echo
        } >> "$SUMMARY_LOG"
    fi
done

#
# Stop live monitor before printing the final report.
#
cleanup
TAIL_PID=""

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

if [ -s "$SUMMARY_LOG" ]
then
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
echo "Clamdscan summary:"
echo "  $SCAN_LOG"
echo
echo "Detected-file summary:"
echo "  $SUMMARY_LOG"
echo

if [ "$SCAN_ERROR" -ne 0 ]
then
    echo "ClamAV scan completed with an error."
    exit "$SCAN_ERROR"
fi

echo "ClamAV scan completed."
exit 0
