# clamav-alpine

One-shot ClamAV `clamdscan` filesystem scanner for Docker, Docker Compose, Dockge, Unraid, and Linux storage hosts.

> **Project name note:** `clamav-alpine` is the historical repository/image name. The current implementation uses the maintained official ClamAV Docker base image instead of manually installing an old ClamAV package into `alpine:latest`.

Docker Hub image:

```text
bmmbmm01/clamav-alpine
```

## What this container does

Each container start performs one complete scan workflow:

1. Creates/checks required ClamAV runtime directories and configuration.
2. Archives logs from the previous run, including interrupted runs.
3. Clears the active log files for the new run.
4. Updates the persistent signature database with `freshclam`.
5. Starts `clamd`.
6. Waits for `clamd` to answer `PONG` before scanning.
7. Runs `clamdscan` against `/scan` using a local Unix socket, `--fdpass`, and `--multiscan`.
8. Streams file-by-file scan activity from `clamd.log` into Docker stdout.
9. Saves the full logs and infection summary under `/var/log/clamav`.
10. Exits when the scan finishes.

This is intentionally **not** a permanently running ClamAV daemon container. A completed one-shot scan leaves the container stopped.

## Current design

The current image is built from an official ClamAV base:

```dockerfile
ARG CLAMAV_TAG=1.4_base
FROM clamav/clamav:${CLAMAV_TAG}
```

The scanner scripts and configuration are copied into the image at build time. Normal container startup does **not** curl/download this project's scripts from GitHub.

The default `1.4_base` value tracks patch releases in the ClamAV 1.4 line. For a reproducible release build, use an exact upstream tag such as `1.4.6_base`.

## Repository layout

```text
clamav-alpine/
├── Dockerfile
├── compose.yaml
├── compose.dockerhub.yaml
├── .env.example
├── .dockerignore
├── .gitignore
├── LICENSE
├── README.md
├── build/
│   ├── Build_Freshclam_ClamD.sh
│   ├── check_files.sh
│   ├── clamd.conf
│   ├── clamdscan.sh
│   └── freshclam.conf
├── examples/
│   └── compose.pve.yaml
└── img/
    └── clamav.png
```

The `db/`, `log/`, `scan/`, `etc/`, and `scan-mask/` directories are runtime/local data and are intentionally not committed.

## Build from a Git checkout

```bash
git clone https://github.com/bmartino1/clamav-alpine.git
cd clamav-alpine
```

Build against the current patch in the 1.4 line:

```bash
docker build \
  --pull \
  --build-arg CLAMAV_TAG=1.4_base \
  -t bmmbmm01/clamav-alpine:local \
  .
```

For an exact reproducible engine release:

```bash
docker build \
  --pull \
  --build-arg CLAMAV_TAG=1.4.6_base \
  -t bmmbmm01/clamav-alpine:1.4.6 \
  .
```

Verify the engine in the built image:

```bash
docker run --rm \
  --entrypoint clamscan \
  bmmbmm01/clamav-alpine:1.4.6 \
  --version
```

## Build and run with Compose

The included `compose.yaml` builds from the current source checkout.

Create local runtime directories and an environment file:

```bash
cp .env.example .env
mkdir -p scan db log
```

Edit `.env` and set `SCAN_PATH` to the host directory that should be scanned.

Then:

```bash
docker compose build --pull
docker compose up --force-recreate
```

When the scan completes, the container stops.

## Run the Docker Hub image

After published images are available, use:

```bash
docker compose -f compose.dockerhub.yaml up --force-recreate
```

Or run directly:

```bash
docker run --rm \
  --name clamav \
  -e TZ="America/Chicago" \
  -e SCAN_FOLDERS="/scan" \
  -v /path/to/scan:/scan:ro \
  -v /path/to/clamav-db:/var/lib/clamav:rw \
  -v /path/to/clamav-log:/var/log/clamav:rw \
  --pids-limit 2048 \
  bmmbmm01/clamav-alpine:latest
```

Host networking and privileged mode are not required for this one-shot local-socket scanner.

## Volumes

### `/scan`

The data to scan. This should normally be mounted **read-only**:

```text
/path/to/data:/scan:ro
```

### `/var/lib/clamav`

Persistent ClamAV signature database:

```text
/path/to/db:/var/lib/clamav:rw
```

Persisting the database avoids downloading the entire signature set on every run. `freshclam` still checks for updates before each scan.

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

## Live scan progress

The configuration intentionally uses:

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

Because this can create a large amount of stdout, the Compose examples use Docker's `local` logging driver with rotation:

```yaml
logging:
  driver: local
  options:
    max-size: "50m"
    max-file: "3"
```

The Docker stdout rotation is separate from the persistent ClamAV logs mounted at `/var/log/clamav`.

## Scan results and exit behavior

`scan_summary.txt` is the quick infection result file. `log.log` contains the `clamdscan` summary, and `clamd.log` contains detailed daemon/file activity.

The wrapper intentionally treats a ClamAV malware detection as a completed scan and records the detection in the summary rather than marking the container itself as failed.

If `clamdscan` returns a scan/error condition (for example inaccessible or unsupported filesystem objects), the wrapper returns that error code after saving the logs.

A large host tree may contain special objects that ClamAV cannot scan, for example:

```text
/proc/.../fdinfo/...
Docker overlay/runtime files
backing block-device entries
special device or pseudo-filesystem nodes
```

A summary such as:

```text
Infected files: 0
Total errors: 1788
```

means no infection was reported among successfully scanned objects, but some requested objects could not be scanned. For normal deployments, point `/scan` at the actual user/storage data you care about instead of Docker's internal root filesystem or pseudo-filesystems when possible.

## PVE / Dockge example

`examples/compose.pve.yaml` documents the layout used to validate this rebuild on PVE/Dockge.

That host scans `/data`, while its own ClamAV working directory is also inside `/data`. The example therefore overlays an empty `scan-mask` directory over the ClamAV working path inside `/scan` so the scanner does not scan its own signature database and logs.

## Updating the ClamAV engine

Virus signatures update every container start through `freshclam`.

Updating the **engine** requires rebuilding the image against a newer official ClamAV base tag:

```bash
docker build --pull --build-arg CLAMAV_TAG=1.4_base -t bmmbmm01/clamav-alpine:local .
```

Before publishing a release, prefer an exact tested upstream tag so the published image can be reproduced.

## Publishing to Docker Hub

After testing an exact build, tag the **same tested image** rather than rebuilding separately for every tag. Example for ClamAV 1.4.6:

```bash
docker build \
  --pull \
  --build-arg CLAMAV_TAG=1.4.6_base \
  -t bmmbmm01/clamav-alpine:1.4.6 \
  .

docker tag bmmbmm01/clamav-alpine:1.4.6 bmmbmm01/clamav-alpine:1.4
docker tag bmmbmm01/clamav-alpine:1.4.6 bmmbmm01/clamav-alpine:latest

docker push bmmbmm01/clamav-alpine:1.4.6
docker push bmmbmm01/clamav-alpine:1.4
docker push bmmbmm01/clamav-alpine:latest
```

## Project history

This project continues the earlier `clamav-alpine` work and retains the applicable MIT license and original attribution. The 2026 rebuild keeps the original one-shot `freshclam` + `clamd` + `clamdscan` goal while replacing outdated build/runtime download behavior with a maintained official ClamAV base and self-contained project files.

## License

MIT. See [LICENSE](LICENSE).
