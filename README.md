# ClamAV clamdscan — One-Shot Docker Scanner

[![Docker Hub](https://img.shields.io/badge/Docker%20Hub-bmmbmm01%2Fclamav--alpine-blue?logo=docker)](https://hub.docker.com/r/bmmbmm01/clamav-alpine)
[![GitHub](https://img.shields.io/badge/Source-bmartino1%2Fclamav--alpine-181717?logo=github)](https://github.com/bmartino1/clamav-alpine)
[![ClamAV](https://img.shields.io/badge/Engine-ClamAV-3D9970)](https://www.clamav.net/)
[![Unraid](https://img.shields.io/badge/Platform-Unraid-F15A2C?logo=unraid)](https://unraid.net/)

**ClamAV clamdscan** is a Docker-based, one-shot malware scanner designed for **Unraid** and other Docker hosts. Point it at a folder, start the container, and let it scan. The results are saved to your persistent log directory when the scan is finished.

This project builds on earlier community ClamAV container approaches, adapted for a practical `clamdscan` workflow with persistent settings, live Docker log output, scan exclusions, and previous-scan history.

> **A scan runs once per container start.** The container updates signatures (when enabled), starts `clamd`, scans your selected folders, writes the results, and exits. A **stopped** container after a completed scan is expected. This is not a continuously running antivirus service, real-time protection tool, or web interface.

**About the name:** `clamav-alpine` is the historical image/repository name. The current Dockerfile uses the **official ClamAV base image**, not a custom installation of an older ClamAV package into `alpine:latest`.

## Project Links

- **Docker image:** [bmmbmm01/clamav-alpine](https://hub.docker.com/r/bmmbmm01/clamav-alpine)
- **Source code:** [bmartino1/clamav-alpine](https://github.com/bmartino1/clamav-alpine)
- **Unraid template:** [clamdscan.xml](https://github.com/bmartino1/unraid-docker-templates/blob/main/templates/clamdscan.xml)
- **Unraid support:** [bmartino1 CA Docker Repository](https://forums.unraid.net/topic/198948-support-bmartino1-ca-docker-repository/)
- **ClamAV project:** [ClamAV](https://www.clamav.net/) · [Documentation](https://docs.clamav.net/) · [Source](https://github.com/Cisco-Talos/clamav)

## Features

- **One-shot scans:** run on demand; the container exits when finished.
- **ClamAV daemon + clamdscan:** uses the local Unix socket, `--fdpass`, and `--multiscan`.
- **Read-only scan folders:** your files can be mounted as `/scan:ro`; the wrapper does not remove or quarantine detections.
- **Signature updates:** `freshclam` checks for newer signatures before a scan unless disabled.
- **Offline-friendly first start:** image-bundled build-time signatures can initialize an empty persistent database.
- **Persistent configuration:** keep custom `clamd.conf` and `freshclam.conf` files across restarts and image updates.
- **Flexible exclusions:** use an environment variable for ordinary directory exclusions or edit `clamd.conf` directly.
- **Live progress:** file-by-file scan output appears in Docker/Unraid logs.
- **Saved reports:** detection summary, detailed scan logs, and optional previous-run history.
- **No privileged mode or host networking required.**

## Install on Unraid

The Unraid template is the simplest way to get started. Install **clamdscan**, select the folder you want to scan, and click **Apply** to create/start the container.

The template uses bridge networking and a read-only mount for the selected scan folder. There is no WebUI; view progress in the container log while it runs and saved results in the mapped log directory afterward.

Typical Unraid paths:

| Host path | Container path | Purpose |
| --- | --- | --- |
| `/mnt/user` | `/scan:ro` | Files to scan, read-only |
| `/mnt/user/appdata/CAVclamdscan/db` | `/var/lib/clamav:rw` | Persistent virus signatures |
| `/mnt/user/appdata/CAVclamdscan/log` | `/var/log/clamav:rw` | Scan reports and history |
| `/mnt/user/appdata/CAVclamdscan/etc` | `/etc/clamav:rw` | Editable ClamAV configuration |

If scanning all of `/mnt/user`, consider excluding this scanner's own appdata path:

```text
EXCLUDE_PATHS=/scan/appdata/CAVclamdscan
```

The `/scan` path is the **path inside the container**, not the Unraid host path.

### Manual Docker Run

Adjust the folder mounted at `/scan` to match your Unraid storage location:

```bash
mkdir -p /mnt/user/appdata/CAVclamdscan/{db,log,etc}

docker run -d \
  --name ClamAV-clamdscan \
  --network bridge \
  --restart no \
  --pids-limit 2048 \
  -e SCAN_FOLDERS="/scan" \
  -e EXCLUDE_PATHS="/scan/appdata/CAVclamdscan" \
  -e LOG_HISTORY_LIMIT="3" \
  -e SKIP_FRESHCLAM="false" \
  --log-driver local \
  --log-opt max-size=50m \
  --log-opt max-file=3 \
  -v /mnt/user:/scan:ro \
  -v /mnt/user/appdata/CAVclamdscan/db:/var/lib/clamav:rw \
  -v /mnt/user/appdata/CAVclamdscan/log:/var/log/clamav:rw \
  -v /mnt/user/appdata/CAVclamdscan/etc:/etc/clamav:rw \
  bmmbmm01/clamav-alpine:latest
```

Follow progress with:

```bash
docker logs -f ClamAV-clamdscan
```

Run another scan later by starting the stopped container again:

```bash
docker start ClamAV-clamdscan
```

> Because this is an on-demand scanner, Docker restart policy `no` is intentional. It will not schedule future scans by itself.

## Docker Compose / Dockge

A Compose example is included in the repository: [compose.dockerhub.yaml](https://github.com/bmartino1/clamav-alpine/blob/main/compose.dockerhub.yaml).

It supports configurable host paths for the scan, signature database, logs, and ClamAV configuration:

```yaml
name: clamav

services:
  clamav:
    image: bmmbmm01/clamav-alpine:latest
    container_name: clamav
    restart: "no"
    environment:
      SCAN_FOLDERS: /scan
      EXCLUDE_PATHS: ""
      LOG_HISTORY_LIMIT: "3"
      SKIP_FRESHCLAM: "false"
    volumes:
      - ./scan:/scan:ro
      - ./db:/var/lib/clamav:rw
      - ./log:/var/log/clamav:rw
      - ./etc:/etc/clamav:rw
    pids_limit: 2048
    logging:
      driver: local
      options:
        max-size: "50m"
        max-file: "3"
```

Run it from the directory containing your Compose file:

```bash
docker compose up -d
docker compose logs -f
```

Update `./scan` to the host folder you actually want to scan. Docker Compose and Dockge also work with the supplied `compose.dockerhub.yaml`.

## Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `SCAN_FOLDERS` | `/scan` | Space-separated container folders to scan. |
| `EXCLUDE_PATHS` | empty | Space-separated **container paths** to exclude. |
| `LOG_HISTORY_LIMIT` | `3` | Number of previous-scan log archives to retain; `0` disables history. |
| `SKIP_FRESHCLAM` | `false` | Set to `true` to skip online signature updates before scanning. |
| `TZ` | supplied by deployment | Container time zone; for example, `America/Chicago`. |

### Scanning More Than One Folder

Mount each additional host directory into the container and include its container path:

```text
SCAN_FOLDERS=/scan /scan2
```

### Excluding Folders

For common exclusions, use:

```text
EXCLUDE_PATHS=/scan/appdata/CAVclamdscan /scan/other-folder
```

On startup, the container updates only its **managed exclusion block** in `clamd.conf`. Manually added `ExcludePath` entries outside that block are preserved.

Paths in `EXCLUDE_PATHS` are separated by spaces, so this setting is not suitable for directory names containing spaces. For those, add the relevant `ExcludePath` rule directly to the persistent `clamd.conf`.

### Keeping Previous Scan Logs

```text
LOG_HISTORY_LIMIT=3
```

Keeps up to three previous-run archives. Set it to `0` to disable archived history and remove existing managed history archives at the next start.

The current scan logs are separate from the archived history and are not capped by this setting.

### Offline Scanning

```text
SKIP_FRESHCLAM=true
```

Skips the signature update attempt. The container uses persistent signatures or the signature snapshot included when the image was built.

Offline operation is useful when needed, but signatures may be outdated. For routine scans, leave `SKIP_FRESHCLAM=false` so `freshclam` attempts an update before each scan. If updating fails and a usable database exists, the scanner continues with existing signatures.

## What Happens on Startup?

Each start runs a single scan workflow:

1. Check folders and prepare missing configuration files.
2. Seed a missing or incomplete signature database from the image's build-time copy.
3. Archive and rotate earlier scan logs according to `LOG_HISTORY_LIMIT`.
4. Apply the Docker-managed `EXCLUDE_PATHS` entries without overwriting manual configuration.
5. Update signatures with `freshclam` unless skipped.
6. Start `clamd` and wait for it to be ready.
7. Run `clamdscan` over the configured folders, show progress, and save results.
8. Exit after the scan completes.

The image keeps its default configuration and signature seed under `/build` because bind-mounting empty host folders over `/etc/clamav` or `/var/lib/clamav` would otherwise hide those files. Missing configuration files are copied on first start; existing host configuration files are left intact.

## Scan Results and Logs

Persistent scan results are written under `/var/log/clamav`, mapped to the log folder on your host:

| File | Contents |
| --- | --- |
| `scan_summary.txt` | Quick summary of detected threats |
| `log.log` | Scan output plus scan configuration |
| `clamd.log` | Detailed daemon and file-scan activity |
| `history/` | Archived logs from previous runs, when enabled |

The container prints the selected folders and effective exclusions before scanning. With verbose clean-file logging enabled, a large scan can generate significant log output. Docker stdout rotation helps control Docker logs, but it does not impose a size limit on your persistent `clamd.log`.

A malware detection is recorded as a completed scan with findings; it is not treated as a container infrastructure failure. Actual scanning errors can still produce a nonzero exit status.

**Detected files are reported, not automatically deleted, quarantined, or repaired.** Review findings before deciding what action to take.

## Editing ClamAV Settings

The container keeps editable copies of these files under your mapped `/etc/clamav` directory:

```text
clamd.conf
freshclam.conf
```

If either file is missing on first start, it is copied from the image defaults. Later image updates do not replace existing configuration files.

You can add manual `ExcludePath` rules, for example:

```text
ExcludePath ^/scan/path/to/exclude(/|$)
```

Remember that ClamAV sees **container paths**, not host paths.

## Troubleshooting

### The container stopped

That is normal after a completed scan. Check the saved results under `/var/log/clamav` or the container's logs. Start the container again when you want another scan.

### Files are not being scanned

Verify your host directory is mounted to `/scan` and `SCAN_FOLDERS` names the corresponding path inside the container. Review `EXCLUDE_PATHS` and any manual `ExcludePath` rules in `clamd.conf`.

### Signatures do not update

Inspect Docker logs for `freshclam` messages, and confirm the signature database directory is writable. Offline scans can use existing signatures, but they may be less up to date.

### Scan logs become large

Verbose file-by-file logging is enabled for visibility. Large folder trees can create large `clamd.log` files. You can adjust your persistent `clamd.conf` logging settings and exclude paths that do not need scanning. `LOG_HISTORY_LIMIT` applies to **archives**, not the active log.

### Scans are slow or take many hours

Scan duration depends on storage speed, number and size of files, and available CPU and memory. `clamdscan --multiscan` allows the daemon to process files in parallel. Excluding unnecessary runtime folders and other storage trees can help.

## Updating

Pull a newer image and recreate the container when you want to update the packaged ClamAV engine and wrapper scripts. The selected engine release is controlled by `CLAMAV_TAG` at image build time.

Signature definitions update separately through `freshclam` at scan time (unless disabled). Your mapped database, configuration, and log directories persist across container recreation.

## Project Background and License

This repository is an adaptation of earlier community ClamAV Docker/scanner work, maintained here as a one-shot `clamdscan` container with Unraid-friendly deployment options. The upstream antivirus engine is the [ClamAV project](https://github.com/Cisco-Talos/clamav); this image is not an official ClamAV release.

The repository's wrapper code is distributed under the [MIT License](https://github.com/bmartino1/clamav-alpine/blob/main/LICENSE). ClamAV and other bundled upstream software retain their own respective licenses.
