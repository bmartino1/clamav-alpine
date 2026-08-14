#!/bin/sh
set -eu

CLAMD_CONFIG="/etc/clamav/clamd.conf"
EXCLUDE_PATHS="${EXCLUDE_PATHS:-}"

BEGIN_MARKER="# BEGIN CLAMAV-ALPINE MANAGED EXCLUDES"
END_MARKER="# END CLAMAV-ALPINE MANAGED EXCLUDES"

if [ ! -f "$CLAMD_CONFIG" ]; then
    echo "ERROR: Required configuration file is missing: $CLAMD_CONFIG"
    exit 1
fi

TMP_FILE="${CLAMD_CONFIG}.managed-excludes.$$"
trap 'rm -f "$TMP_FILE"' EXIT HUP INT TERM

BEGIN_COUNT="$(awk -v marker="$BEGIN_MARKER" '$0 == marker { count++ } END { print count + 0 }' "$CLAMD_CONFIG")"
END_COUNT="$(awk -v marker="$END_MARKER" '$0 == marker { count++ } END { print count + 0 }' "$CLAMD_CONFIG")"

if [ "$BEGIN_COUNT" -ne "$END_COUNT" ] || [ "$BEGIN_COUNT" -gt 1 ]; then
    echo "ERROR: Invalid managed exclusion block markers in $CLAMD_CONFIG"
    echo "Found begin markers: $BEGIN_COUNT"
    echo "Found end markers:   $END_COUNT"
    echo "Refusing to modify the configuration."
    exit 1
fi

# Remove only the block previously managed by this script.
# Every other line in clamd.conf remains untouched, including manually added
# ExcludePath directives and all other end-user customizations.
awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { managed = 1; next }
    $0 == end   { managed = 0; next }
    !managed    { print }
' "$CLAMD_CONFIG" > "$TMP_FILE"

if [ -n "$EXCLUDE_PATHS" ]; then
    {
        echo "$BEGIN_MARKER"
        echo "# Generated from the EXCLUDE_PATHS Docker environment variable."
        echo "# Change EXCLUDE_PATHS instead of editing inside this block."
        echo "# Manual clamd.conf edits outside this block are preserved."

        for path in $EXCLUDE_PATHS
        do
            case "$path" in
                /*)
                    ;;
                *)
                    echo "ERROR: EXCLUDE_PATHS entry must be an absolute container path: $path" >&2
                    exit 1
                    ;;
            esac

            # Excluding / would effectively disable a normal filesystem scan.
            if [ "$path" = "/" ]; then
                echo "ERROR: Refusing EXCLUDE_PATHS entry '/'." >&2
                exit 1
            fi

            # Normalize trailing slashes so /scan/path and /scan/path/ create
            # the same anchored exclusion.
            while [ "$path" != "/" ] && [ "${path%/}" != "$path" ]
            do
                path="${path%/}"
            done

            # ExcludePath is a regular expression. Escape regex metacharacters
            # in the user-provided path, then anchor the rule so it matches the
            # directory itself and anything below it, but not similarly named
            # sibling paths.
            escaped_path="$(printf '%s\n' "$path" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"
            printf 'ExcludePath ^%s(/|$)\n' "$escaped_path"
        done

        echo "$END_MARKER"
    } >> "$TMP_FILE"
fi

if cmp -s "$TMP_FILE" "$CLAMD_CONFIG"; then
    echo "Managed ClamAV exclusions already match EXCLUDE_PATHS."
else
    # Write back through the existing file so bind-mounted file ownership and
    # permissions are preserved.
    cat "$TMP_FILE" > "$CLAMD_CONFIG"
    echo "Updated managed ClamAV exclusion block."
fi

echo
echo "Managed exclusion paths:"
if [ -n "$EXCLUDE_PATHS" ]; then
    for path in $EXCLUDE_PATHS
    do
        echo "  $path"
    done
else
    echo "  (none)"
fi
