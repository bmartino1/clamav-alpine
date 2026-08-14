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
  -e EXCLUDE_PATHS='/scan/appdata/CAVclamdscan' \
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
   - If a config already exists, it is left completely unchanged so end-user edits survive image updates and restarts.
3. Rebuilds only the Docker-managed `ExcludePath` block from `EXCLUDE_PATHS`, while preserving all manual `clamd.conf` edits outside that block.
4. Archives logs from the previous run, including interrupted runs.
5. Clears the active log files for the new run.
6. Updates the persistent signature database with `freshclam`.
7. Starts `clamd`.
8. Waits for `clamd` to answer before scanning.
9. Runs `clamdscan` against the configured scan folders using the local Unix socket, `--fdpass`, and `--multiscan`.
10. Streams file-by-file scan activity from `clamd.log` into Docker stdout.
11. Saves the full logs and infection summary under `/var/log/clamav`.
12. Exits when the scan finishes.

This is intentionally **not** a permanently running ClamAV daemon container. A completed one-shot scan leaves the container stopped.
Host networking and privileged mode are not required for this one-shot local-socket scanner.

## Why `/build` exists inside the image

The repository `build/` directory is copied into the image at `/build`.

That is intentional. A bind mount such as:

```text
/path/to/etc:/etc/clamav:rw
```

hides whatever files were baked into `/etc/clamav` inside the image. An empty host `etc` directory would therefore otherwise make `clamd.conf` and `freshclam.conf` disappear at runtime.

`check_files.sh` solves that first-run problem by using the image-local copies:

```text
/build/clamd.conf
/build/freshclam.conf
```

and copying a file into `/etc/clamav` **only when that file is missing**.

After the first run, the host gets editable copies:

```text
/path/to/etc/clamd.conf
/path/to/etc/freshclam.conf
```

Those files now belong to the deployment. Future container starts and image updates do **not** overwrite them.

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

The official ClamAV `_base` images do not include the signature database, so persisting `/var/lib/clamav` avoids downloading the entire signature set on every run. `freshclam` still checks for updates before each scan.

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

Previous run data is archived before a new scan starts:

```text
/var/log/clamav/history/YYYY-MM-DD_HH-MM-SS/
```

This preserves results from a completed scan and partial logs from an interrupted/restarted scan.

### `/etc/clamav`

Persistent, end-user-editable ClamAV configuration:

```text
/path/to/etc:/etc/clamav:rw
```

On an empty first-run bind mount, the container creates only the missing files from its `/build` defaults. Existing files are never replaced by `check_files.sh`.

This is where deployment-specific settings belong, including scan exclusions.

For example, paths in `ExcludePath` are **container paths**, so a host directory mounted below `/scan` should be excluded using its `/scan/...` path:

```text
ExcludePath ^/scan/path/to/exclude(/|$)
```

The directive may be repeated for multiple exclusions.

## Docker-managed exclusions with `EXCLUDE_PATHS`

`EXCLUDE_PATHS` provides a Docker environment-variable interface for common directory exclusions. It uses the same space-separated style as `SCAN_FOLDERS`:

```text
EXCLUDE_PATHS=/scan/Dockers/PVE/Dockers /scan/Dockers/docker-root /scan/PBS
```

Paths must be absolute **container-visible** paths. A host path under the directory mounted at `/scan` must therefore be written using its `/scan/...` path.

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

The script escapes regular-expression metacharacters in each path and adds an anchored `(/|$)` suffix. Manually maintained `ExcludePath` lines outside the managed block are left untouched and may be used alongside the environment-managed entries.

If `EXCLUDE_PATHS` is changed, the managed block is replaced on the next container start. If `EXCLUDE_PATHS` is cleared, the managed block is removed.

Because the value is space-separated, directory names containing spaces are not supported by this environment-variable interface. Such paths can still be configured manually in `clamd.conf`.

## Docker Compose

The included `compose.dockerhub.yaml` persists all three ClamAV data/config areas:

```yaml
volumes:
  - ${SCAN_PATH:-./scan}:/scan:ro
  - ${CLAMAV_DB_PATH:-./db}:/var/lib/clamav:rw
  - ${CLAMAV_LOG_PATH:-./log}:/var/log/clamav:rw
  - ${CLAMAV_ETC_PATH:-./etc}:/etc/clamav:rw
```

The Compose environment also supports:

```yaml
environment:
  SCAN_FOLDERS: ${SCAN_FOLDERS:-/scan}
  EXCLUDE_PATHS: "${EXCLUDE_PATHS:-}"
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

After the first container run, `etc/` will contain the maintained defaults and can be edited on the host.

## Live scan progress

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

Because this can create a large amount of stdout, the Compose example uses Docker's `local` logging driver with rotation:

```yaml
logging:
  driver: local
  options:
    max-size: "50m"
    max-file: "3"
```

Docker stdout rotation is separate from the persistent ClamAV logs mounted at `/var/log/clamav`.

## Scan results and exit behavior

`scan_summary.txt` is the quick infection-result file. `log.log` contains the `clamdscan` summary, and `clamd.log` contains detailed daemon/file activity.

The wrapper intentionally treats a ClamAV malware detection as a completed scan and records the detection in the summary rather than marking the container itself as failed.

If `clamdscan` returns a scan/error condition, the wrapper returns that error code after saving the logs.

A large host tree may contain special objects that ClamAV cannot scan, for example Docker runtime files, backing block-device entries, or pseudo-filesystems. For normal deployments, point `/scan` at the user/storage data you actually want to scan.

## Updating ClamAV

Virus signatures are checked and updated on every container start through `freshclam`.

The ClamAV engine itself comes from the official image selected by `CLAMAV_TAG` in the Dockerfile. Rebuild and publish the image when you want to move to a newer supported ClamAV base image/tag.

## License

MIT. See [LICENSE](LICENSE).
