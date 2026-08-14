# clamav-alpine

One-shot ClamAV `clamdscan` filesystem scanner for Docker, Docker Compose, Dockge, Unraid, and Linux storage hosts.

> **Project name note:** `clamav-alpine` is the historical repository/image name. The current implementation uses the maintained official ClamAV Docker base image instead of manually installing an old ClamAV package into `alpine:latest`.

Docker Hub image:

https://hub.docker.com/r/bmmbmm01/clamav-alpine

```text
docker run -d \
  --name='ClamAV-clamdscan' \
  --net='bridge' \
  --restart=no \
  --pids-limit 2048 \
  -e TZ='America/Chicago' \
  -e SCAN_FOLDERS='/scan' \
  -e EXCLUDE_PATHS='/scan/appdata/CAVclamdscan' \
  -e LOG_HISTORY_LIMIT='3' \
  -e SKIP_FRESHCLAM='false' \
  --log-driver=local \
  --log-opt max-size=50m \
  --log-opt max-file=3 \
  -v '/mnt/remotes/addons/':'/scan':'ro' \
  -v '/mnt/user/appdata/CAVclamdscan/db/':'/var/lib/clamav':'rw' \
  -v '/mnt/user/appdata/CAVclamdscan/log/':'/var/log/clamav':'rw' \
  -v '/mnt/user/appdata/CAVclamdscan/etc/':'/etc/clamav':'rw' \
  'bmmbmm01/clamav-alpine:latest'
```

## What this container does

Each container start performs one complete scan workflow:

1. Creates/checks the required runtime directories.
2. Checks `/etc/clamav/clamd.conf` and `/etc/clamav/freshclam.conf`.
   - If a config is missing, the image copies the maintainer default from `/build` into `/etc/clamav`.
   - If a config already exists, it is left unchanged so end-user edits survive image updates and restarts.
3. Checks `/var/lib/clamav`.
   - If the persistent database is empty or incomplete, missing signature files are seeded from the image-local `/build/clamav-db` snapshot created at image build time.
   - Existing persistent database files are not overwritten by the bootstrap check.
4. Archives logs from the previous run when log history is enabled, then enforces `LOG_HISTORY_LIMIT`.
5. Clears the active log files for the new run.
6. Rebuilds only the Docker-managed `ExcludePath` block from `EXCLUDE_PATHS`, while preserving manual `clamd.conf` edits outside that block.
7. Runs `freshclam` unless `SKIP_FRESHCLAM` is enabled.
   - If the update fails but a usable database already exists, the scan continues using the existing signatures.
8. Starts `clamd` and waits for it to become ready.
9. Runs `clamdscan` against the configured scan folders using the local Unix socket, `--fdpass`, and `--multiscan`.
10. Prints the configured scan folders and active exclusions before scanning.
11. Streams file-by-file scan activity from `clamd.log` into Docker stdout.
12. Saves persistent scan results and exits when the scan finishes.

This is intentionally **not** a permanently running ClamAV daemon container. A completed one-shot scan leaves the container stopped. Host networking and privileged mode are not required for this one-shot local-socket scanner.

## Why `/build` exists inside the image

The repository `build/` directory is copied into the image at `/build`.

That is intentional because runtime bind mounts hide the original image contents at the mounted destination.

For configuration, an empty bind mount such as:

```text
/path/to/etc:/etc/clamav:rw
```

would otherwise hide the image's `/etc/clamav/clamd.conf` and `/etc/clamav/freshclam.conf`.

`check_files.sh` therefore uses the image-local copies:

```text
/build/clamd.conf
/build/freshclam.conf
```

and copies a file into `/etc/clamav` **only when that file is missing**.

After the first run, the host gets editable copies:

```text
/path/to/etc/clamd.conf
/path/to/etc/freshclam.conf
```

Those files belong to the deployment. Future container starts and image updates do **not** replace them.

The same design is used for offline-capable signatures. During image build, `freshclam` downloads a current database snapshot and the image stores it under:

```text
/build/clamav-db/
```

If a new host bind-mounts an empty `/var/lib/clamav`, `check_files.sh` seeds the missing signature files from that image-local snapshot before the normal update/start workflow continues.

## Volumes

### `/scan`

The data to scan. This should normally be mounted read-only:

```text
/path/to/data:/scan:ro
```

### `/var/lib/clamav`

Persistent ClamAV signature database:

```text
/path/to/db:/var/lib/clamav:rw
```

The project uses an official ClamAV `_base` image and downloads signatures during the custom image build. A copy of that build-time database is retained under `/build/clamav-db` so a new empty persistent database can be initialized without Internet access.

For normal online operation, `freshclam` still checks for newer signatures before each scan.

### `/var/log/clamav`

Persistent current-run logs and previous-run history:

```text
/path/to/log:/var/log/clamav:rw
```

Current run:

```text
/var/log/clamav/clamd.log
/var/log/clamav/log.log
/var/log/clamav/scan_summary.txt
```

Previous run data is archived before a new scan starts when history retention is enabled:

```text
/var/log/clamav/history/YYYY-MM-DD_HH-MM-SS/
```

If two archive operations happen within the same second, a numeric suffix is added rather than reusing an existing directory.

### `/etc/clamav`

Persistent, end-user-editable ClamAV configuration:

```text
/path/to/etc:/etc/clamav:rw
```

On an empty first-run bind mount, the container creates only the missing files from its `/build` defaults. Existing files are never replaced by `check_files.sh`.

This is where deployment-specific settings belong, including manual scan exclusions.

For example, paths in `ExcludePath` are **container paths**, so a host directory mounted below `/scan` should be excluded using its `/scan/...` path:

```text
ExcludePath ^/scan/path/to/exclude(/|$)
```

The directive may be repeated for multiple exclusions.

## Environment variables

### `SCAN_FOLDERS`

Space-separated container paths to scan. Default:

```text
SCAN_FOLDERS=/scan
```

Example:

```text
SCAN_FOLDERS=/scan /scan2
```

### `EXCLUDE_PATHS`

Provides a Docker environment-variable interface for common directory exclusions. It uses the same space-separated style as `SCAN_FOLDERS`:

```text
EXCLUDE_PATHS=/scan/Dockers/PVE/Dockers /scan/Dockers/docker-root /scan/PBS
```

Paths must be absolute **container-visible** paths. A host path below the directory mounted at `/scan` must therefore be written using its `/scan/...` path.

At startup, `apply_exclude_paths.sh` removes only its previous managed block and regenerates it from the current environment value:

```text
# BEGIN CLAMAV-ALPINE MANAGED EXCLUDES
# Generated from the EXCLUDE_PATHS Docker environment variable.
# Change EXCLUDE_PATHS instead of editing inside this block.
# Manual clamd.conf edits outside this block are preserved.
ExcludePath ^/scan/Dockers/PVE/Dockers(/|$)
ExcludePath ^/scan/Dockers/docker-root(/|$)
ExcludePath ^/scan/PBS(/|$)
# END CLAMAV-ALPINE MANAGED EXCLUDES
```

The script escapes regular-expression metacharacters in each path and adds an anchored `(/|$)` suffix. Manual `ExcludePath` lines outside the managed block are left untouched and may be used alongside environment-managed entries.

If `EXCLUDE_PATHS` changes, the managed block is replaced on the next container start. If `EXCLUDE_PATHS` is cleared, the managed block is removed.

Because the value is space-separated, directory names containing spaces are not supported by this environment-variable interface. Such paths can still be configured manually in `clamd.conf`.

### `LOG_HISTORY_LIMIT`

Controls how many **previous-run archive directories** are retained under `/var/log/clamav/history`.

Default:

```text
LOG_HISTORY_LIMIT=3
```

Examples:

```text
LOG_HISTORY_LIMIT=10   # keep the newest 10 archived runs
LOG_HISTORY_LIMIT=1    # keep only the immediately previous run
LOG_HISTORY_LIMIT=0    # disable archive retention and remove managed history archives
```

The value must be a non-negative integer. The limit is enforced every container start, so lowering the value prunes the oldest timestamped archive directories on the next run.

`LOG_HISTORY_LIMIT` limits **archived runs**, not the size of the currently active scan log. With `LogClean yes`, a large active scan may still generate a large `clamd.log` until that run finishes.

### `SKIP_FRESHCLAM`

Default:

```text
SKIP_FRESHCLAM=false
```

Normal operation attempts to update signatures before scanning. If the update fails and a usable signature database already exists, the container warns and continues with those existing signatures.

For a deliberately isolated/offline environment, set:

```text
SKIP_FRESHCLAM=true
```

This skips the network update attempt entirely and uses the persistent or image-seeded database. The container still refuses to start `clamd` if the required `main` and `daily` databases are unavailable.

Accepted true values are `1`, `true`, `yes`, and `on`. Accepted false values are `0`, `false`, `no`, and `off`.

## Docker Compose

The included `compose.dockerhub.yaml` persists all ClamAV data/config areas:

```yaml
volumes:
  - ${SCAN_PATH:-./scan}:/scan:ro
  - ${CLAMAV_DB_PATH:-./db}:/var/lib/clamav:rw
  - ${CLAMAV_LOG_PATH:-./log}:/var/log/clamav:rw
  - ${CLAMAV_ETC_PATH:-./etc}:/etc/clamav:rw
```

The Compose environment supports:

```yaml
environment:
  TZ: ${TZ:-America/Chicago}
  SCAN_FOLDERS: ${SCAN_FOLDERS:-/scan}
  EXCLUDE_PATHS: "${EXCLUDE_PATHS:-}"
  LOG_HISTORY_LIMIT: "${LOG_HISTORY_LIMIT:-3}"
  SKIP_FRESHCLAM: "${SKIP_FRESHCLAM:-false}"
```

A fresh local deployment can therefore start with directories such as:

```text
clamav/
├── compose.dockerhub.yaml
├── db/
├── etc/
├── log/
└── scan/
```

After the first container run, `etc/` contains the maintained defaults and can be edited on the host. An empty `db/` is populated from the image-local build-time database before an online update is attempted.

## Live scan progress and exclusion reporting

The maintained `clamd.conf` intentionally uses:

```text
LogClean yes
LogVerbose yes
```

and `clamdscan.sh` follows `clamd.log` with `tail -F`.

That produces visible file-by-file activity in Docker/Dockge/Unraid logs during scans that may run for many hours:

```text
/scan/path/file1.reg: OK
/scan/path/file2.ps1: OK
/scan/path/file3.exe: OK
```

Before scanning, the wrapper also prints:

- the configured `SCAN_FOLDERS`;
- Docker-managed `EXCLUDE_PATHS` and whether each path currently exists inside the container;
- every active `ExcludePath` directive in the effective `clamd.conf`, including manual rules.

The scan configuration is appended to the persistent `log.log` so the saved report remains self-describing after Docker stdout has rotated.

Because file-by-file output can create a large amount of Docker stdout, the Compose example uses Docker's `local` logging driver with rotation:

```yaml
logging:
  driver: local
  options:
    max-size: "50m"
    max-file: "3"
```

Docker stdout rotation is separate from the persistent ClamAV logs mounted at `/var/log/clamav`.

## Scan results and exit behavior

`scan_summary.txt` is the quick infection-result file. `log.log` contains the `clamdscan` output plus the scan configuration, and `clamd.log` contains detailed daemon/file activity.

The wrapper treats a ClamAV malware detection as a completed scan and records the detection in the summary rather than marking the container itself as failed.

A true `clamdscan` scan/error condition is returned after the logs are saved.

For multiple `SCAN_FOLDERS`, the wrapper records only `FOUND` lines added while each individual folder was being scanned so a detection from one folder is not incorrectly repeated under later folders.

A large host tree may contain special objects that ClamAV cannot scan, for example Docker runtime files, backing block-device entries, or pseudo-filesystems. Use `EXCLUDE_PATHS` or manual `ExcludePath` rules for storage that should not be traversed.

## Updating ClamAV

The ClamAV engine comes from the official image selected by `CLAMAV_TAG` in the Dockerfile. Rebuild and publish this image when moving to a newer supported ClamAV base image/tag.

The custom image build runs `freshclam` and saves the downloaded signature databases under `/build/clamav-db`. For a release intended to carry current signatures, ensure the Docker build step is not satisfied by an old cached layer.

At runtime, signatures are updated with `freshclam` unless `SKIP_FRESHCLAM` is enabled. If runtime updating is unavailable, the existing persistent or image-seeded signatures allow the scanner to continue offline.

## Suggested tests before publishing

### Shell syntax

```text
for file in build/*.sh; do
  /bin/sh -n "$file" || exit 1
done
```

### Normal build

```text
docker build --pull --no-cache -t bmmbmm01/clamav-alpine:test .
```

### Offline first-run test

Use empty `db`, `etc`, and `log` directories and disable networking:

```text
docker run --rm \
  --network none \
  -e SKIP_FRESHCLAM=true \
  -e SCAN_FOLDERS=/scan \
  -e LOG_HISTORY_LIMIT=3 \
  -v /tmp/clamav-test/db:/var/lib/clamav:rw \
  -v /tmp/clamav-test/etc:/etc/clamav:rw \
  -v /tmp/clamav-test/log:/var/log/clamav:rw \
  -v /tmp/clamav-test/scan:/scan:ro \
  bmmbmm01/clamav-alpine:test
```

A successful offline first run proves that the image can seed both configuration and signatures without Internet access.

### History retention test

Run several short scans with:

```text
LOG_HISTORY_LIMIT=3
```

After enough runs, verify that `/var/log/clamav/history` contains no more than three timestamped archive directories. Then test `LOG_HISTORY_LIMIT=0` and verify that archived history is removed while the current active log files still exist.

## License

MIT. See [LICENSE](LICENSE).
