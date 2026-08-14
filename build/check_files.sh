#!/bin/sh
set -eu

# ============================================================
# Paths / runtime settings
# ============================================================

BUILD_DIR="/build"

CONFIG_DIR="/etc/clamav"
DB_DIR="/var/lib/clamav"

LOG_DIR="/var/log/clamav"
HISTORY_DIR="$LOG_DIR/history"

RUN_DIR="/run/clamav"

CLAMD_CONFIG="$CONFIG_DIR/clamd.conf"
FRESHCLAM_CONFIG="$CONFIG_DIR/freshclam.conf"

DEFAULT_CLAMD_CONFIG="$BUILD_DIR/clamd.conf"
DEFAULT_FRESHCLAM_CONFIG="$BUILD_DIR/freshclam.conf"
DEFAULT_DB_DIR="$BUILD_DIR/clamav-db"

CLAMD_LOG="$LOG_DIR/clamd.log"
SCAN_LOG="$LOG_DIR/log.log"
SUMMARY_LOG="$LOG_DIR/scan_summary.txt"

# Number of previous scan runs to retain under /var/log/clamav/history.
#
#   3 = keep the newest three archived runs (default)
#   1 = keep only the immediately previous run
#   0 = disable archived-run retention and remove managed history archives
#
# Current-run logs are separate and are always kept in LOG_DIR.
LOG_HISTORY_LIMIT="${LOG_HISTORY_LIMIT:-3}"


# ============================================================
# Validation helpers
# ============================================================

validate_log_history_limit()
{
    case "$LOG_HISTORY_LIMIT" in
        ''|*[!0-9]*)
            echo "ERROR: LOG_HISTORY_LIMIT must be a non-negative integer."
            echo "Received: $LOG_HISTORY_LIMIT"
            echo "Examples: 0, 1, 3, 10"
            exit 1
            ;;
    esac
}


# ============================================================
# Configuration bootstrap
# ============================================================
#
# Restore a maintainer-provided configuration file ONLY when the
# runtime file is missing.
#
# Existing files belong to the end user.
#
# NEVER:
#   - overwrite them
#   - append to them
#   - chmod them
#   - chown them
#   - replace them
#
# This allows persistent /etc/clamav bind mounts to contain custom
# settings such as ExcludePath without the container destroying them.
#

ensure_config_file()
{
    target="$1"
    default_file="$2"
    label="$3"

    if [ -f "$target" ]; then
        echo "Found existing $label:"
        echo "  $target"
        echo "Preserving existing $label unchanged."
        return 0
    fi

    # Something exists here, but it is not a normal file.
    # Never destroy or replace an unexpected user object.
    if [ -e "$target" ] || [ -L "$target" ]; then
        echo "ERROR: Configuration path exists but is not a regular file:"
        echo "  $target"
        echo
        echo "Refusing to replace or modify it."
        exit 1
    fi

    if [ ! -f "$default_file" ]; then
        echo "ERROR: Maintainer default is missing from the image:"
        echo "  $default_file"
        exit 1
    fi

    echo "Missing $label:"
    echo "  $target"
    echo
    echo "Seeding maintainer default from:"
    echo "  $default_file"

    cp "$default_file" "$target"
    chmod 0644 "$target"

    echo "Created:"
    echo "  $target"
}


# ============================================================
# Signature database helpers
# ============================================================

database_file_exists()
{
    directory="$1"

    for file in \
        "$directory"/*.cvd \
        "$directory"/*.cld
    do
        if [ -f "$file" ]; then
            return 0
        fi
    done

    return 1
}


required_database_present()
{
    directory="$1"

    MAIN_FOUND=0
    DAILY_FOUND=0

    if [ -f "$directory/main.cvd" ] || \
       [ -f "$directory/main.cld" ]; then
        MAIN_FOUND=1
    fi

    if [ -f "$directory/daily.cvd" ] || \
       [ -f "$directory/daily.cld" ]; then
        DAILY_FOUND=1
    fi

    if [ "$MAIN_FOUND" -eq 1 ] && \
       [ "$DAILY_FOUND" -eq 1 ]; then
        return 0
    fi

    return 1
}


# ============================================================
# Signature database bootstrap
# ============================================================
#
# /var/lib/clamav is normally a persistent host bind mount.
#
# The image contains a build-time signature snapshot under:
#
#   /build/clamav-db
#
# If the persistent database is empty or incomplete, copy ONLY
# missing signature files from the image seed.
#
# Existing runtime database files are NEVER overwritten here.
#
# freshclam runs later and remains responsible for normal updates.
#

ensure_signature_database()
{
    echo
    echo "========================================"
    echo " Checking ClamAV signature database"
    echo "========================================"

    if required_database_present "$DB_DIR"; then
        echo "Usable persistent signature database found:"
        echo "  $DB_DIR"
        echo
        echo "Existing database will be preserved."
        return 0
    fi

    echo "Persistent signature database is empty or incomplete:"
    echo "  $DB_DIR"
    echo
    echo "Checking image-provided database seed:"
    echo "  $DEFAULT_DB_DIR"

    if [ ! -d "$DEFAULT_DB_DIR" ]; then
        echo
        echo "ERROR: Bundled ClamAV database directory is missing:"
        echo "  $DEFAULT_DB_DIR"
        exit 1
    fi

    if ! database_file_exists "$DEFAULT_DB_DIR"; then
        echo
        echo "ERROR: No bundled ClamAV signature databases were found in:"
        echo "  $DEFAULT_DB_DIR"
        exit 1
    fi

    if ! required_database_present "$DEFAULT_DB_DIR"; then
        echo
        echo "ERROR: Bundled database seed is incomplete."
        echo
        echo "Expected at minimum:"
        echo "  main.cvd or main.cld"
        echo "  daily.cvd or daily.cld"
        echo
        echo "Found:"
        ls -lah "$DEFAULT_DB_DIR" || true
        exit 1
    fi

    echo
    echo "Seeding missing signature database files..."

    COPIED_FILES=0

    for source in \
        "$DEFAULT_DB_DIR"/*.cvd \
        "$DEFAULT_DB_DIR"/*.cld
    do
        [ -f "$source" ] || continue

        filename="$(basename "$source")"
        target="$DB_DIR/$filename"

        if [ -e "$target" ]; then
            echo "Preserving existing database file:"
            echo "  $target"
            continue
        fi

        echo "Installing bundled database file:"
        echo "  $filename"

        cp -p "$source" "$target"
        COPIED_FILES=$((COPIED_FILES + 1))
    done

    echo

    if [ "$COPIED_FILES" -gt 0 ]; then
        echo "Installed $COPIED_FILES bundled database file(s)."
    else
        echo "No bundled database files needed to be copied."
    fi

    echo
    echo "Validating runtime signature database..."

    if ! required_database_present "$DB_DIR"; then
        echo
        echo "ERROR: Runtime signature database is still incomplete."
        echo
        echo "Current contents:"
        ls -lah "$DB_DIR" || true
        exit 1
    fi

    echo "Runtime signature database is ready."
}


# ============================================================
# Previous-run log history helpers
# ============================================================
#
# Archive directories created by this script use names such as:
#
#   YYYY-MM-DD_HH-MM-SS
#   YYYY-MM-DD_HH-MM-SS-001
#
# The numeric suffix is only used if multiple archive operations happen
# within the same second. Lexicographic sorting therefore keeps archive
# order deterministic for pruning.
#

list_history_archives()
{
    for archive_dir in "$HISTORY_DIR"/????-??-??_??-??-??*
    do
        [ -d "$archive_dir" ] || continue
        [ -f "$archive_dir/run-info.txt" ] || continue
        printf '%s\n' "$archive_dir"
    done | sort
}


history_archive_count()
{
    list_history_archives | wc -l | tr -d '[:space:]'
}


next_archive_directory()
{
    run_stamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    candidate="$HISTORY_DIR/$run_stamp"

    if [ ! -e "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    archive_index=1

    while :
    do
        suffix="$(printf '%03d' "$archive_index")"
        candidate="$HISTORY_DIR/$run_stamp-$suffix"

        if [ ! -e "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi

        archive_index=$((archive_index + 1))
    done
}


prune_log_history()
{
    current_count="$(history_archive_count)"

    echo
    echo "Log history retention:"
    echo "  LOG_HISTORY_LIMIT=$LOG_HISTORY_LIMIT"
    echo "  Current archived runs: $current_count"

    if [ "$current_count" -le "$LOG_HISTORY_LIMIT" ]; then
        echo "  No history pruning required."
        return 0
    fi

    echo "  Pruning oldest archived runs..."

    while [ "$current_count" -gt "$LOG_HISTORY_LIMIT" ]
    do
        oldest_archive="$(list_history_archives | sed -n '1p')"

        if [ -z "$oldest_archive" ]; then
            echo "ERROR: History count is nonzero but no archive directory could be selected."
            exit 1
        fi

        echo "  Removing: $oldest_archive"
        rm -rf "$oldest_archive"

        current_count=$((current_count - 1))
    done

    echo "  Archived runs retained: $current_count"
}


# ============================================================
# Main startup checks
# ============================================================

validate_log_history_limit

echo "========================================"
echo " ClamAV filesystem/configuration check"
echo "========================================"

echo
echo "Creating required runtime directories..."

mkdir -p \
    "$CONFIG_DIR" \
    "$DB_DIR" \
    "$LOG_DIR" \
    "$HISTORY_DIR" \
    "$RUN_DIR"


# ============================================================
# Configuration files
# ============================================================

echo
echo "========================================"
echo " Checking configuration files"
echo "========================================"

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


# ============================================================
# Signature database
# ============================================================

ensure_signature_database


# ============================================================
# Previous-run logs
# ============================================================

echo
echo "========================================"
echo " Checking previous scan logs"
echo "========================================"

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
    echo "Previous scan data found."

    if [ "$LOG_HISTORY_LIMIT" -eq 0 ]; then
        echo
        echo "LOG_HISTORY_LIMIT=0."
        echo "Previous active logs will not be archived."
        echo "Existing managed history archives will be removed."
    else
        ARCHIVE_DIR="$(next_archive_directory)"

        echo
        echo "Archiving previous run to:"
        echo "  $ARCHIVE_DIR"

        mkdir -p "$ARCHIVE_DIR"

        # Create the archive marker first. History pruning only removes
        # timestamped directories containing this file, so unrelated user
        # directories under history/ are never selected for automatic removal.
        {
            echo "ClamAV previous-run archive"
            echo "Archived: $(date)"
            echo "Retention limit at archive time: $LOG_HISTORY_LIMIT"
            echo
            echo "This directory contains the logs that existed"
            echo "before the next one-shot scan was started."
            echo
            echo "This may represent:"
            echo "  - a completed previous scan"
            echo "  - an interrupted scan"
            echo "  - a manually restarted scan"
        } > "$ARCHIVE_DIR/run-info.txt"

        for file in \
            "$CLAMD_LOG" \
            "$SCAN_LOG" \
            "$SUMMARY_LOG"
        do
            if [ -e "$file" ]; then
                cp -a "$file" "$ARCHIVE_DIR/"
            fi
        done

        echo
        echo "Previous run preserved."
    fi
else
    echo "No previous scan logs need archiving."
fi

# Enforce the configured limit every run. This also handles lowering the
# limit when there are no current logs to archive, and removes all managed
# history when LOG_HISTORY_LIMIT=0.
prune_log_history


# ============================================================
# Active logs
# ============================================================

echo
echo "========================================"
echo " Preparing active log files"
echo "========================================"

: > "$CLAMD_LOG"
: > "$SCAN_LOG"
: > "$SUMMARY_LOG"

echo "Active log files are ready."


# ============================================================
# Runtime ownership / permissions
# ============================================================
#
# Config files are intentionally NOT included here.
#
# Existing /etc/clamav files belong to the end user and must not
# have their ownership or permissions rewritten by check_files.sh.
#

echo
echo "========================================"
echo " Setting runtime permissions"
echo "========================================"

chown -R clamav:clamav "$DB_DIR"
chown -R clamav:clamav "$LOG_DIR"
chown -R clamav:clamav "$RUN_DIR"

chmod 0755 "$DB_DIR"
chmod 0755 "$LOG_DIR"
chmod 0755 "$HISTORY_DIR"
chmod 0755 "$RUN_DIR"


# ============================================================
# Remove stale runtime state
# ============================================================

echo
echo "Removing stale runtime files..."

rm -f \
    "$RUN_DIR/clamd.sock" \
    "$RUN_DIR/clamd.pid" \
    "$RUN_DIR/freshclam.pid"


# ============================================================
# Diagnostics
# ============================================================

echo
echo "========================================"
echo " ClamAV engine"
echo "========================================"

clamscan --version || true

echo
echo "Runtime signature database:"

for file in \
    "$DB_DIR"/*.cvd \
    "$DB_DIR"/*.cld
do
    [ -f "$file" ] || continue
    ls -lh "$file"
done

echo
echo "========================================"
echo " Configuration/filesystem check complete"
echo "========================================"
