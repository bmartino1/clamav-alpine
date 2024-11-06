# ClamAV scanning Docker container based on Alpine

https://hub.docker.com/r/bmmbmm01/clamav-alpine
docker pull bmmbmm01/clamav-alpine
 
<!-- TOC -->
- [ClamAV scanning Docker container based on Alpine](#clamav-scanning-docker-container-based-on-alpine)
  - [How-To](#how-to)
    - [Usage](#usage)
      - [Volumes](#volumes)
    - [Examples](#Examples docker run)
  - [Expected Output](#expected-output)
<!-- /TOC --> 

This container allows you a very simple way to scan a mounted directory using `clamdscan`.

It will always update the ClamAV Database, by using the standard `freshclam` before running `clamscan`.
If the local ClamAV Database is up-to-date, it will check and continue.

## How-To

### Usage
Using this image is fairly straightforward.

Pay attention to `-v /path/to/scan` as this is the mounted directory that this docker image will scan.

```
docker run -d \
  --name='testClamAV' \
  --net='host' \
  --privileged=true \
  -e TZ="America/Chicago" \
  -e 'USER_ID'='0' \
  -e 'GROUP_ID'='0' \
  -v '/path/to/scan':'/scan':'ro' \
  -v '/path/to/db/':'/var/lib/clamav':'rw' \
  -v '/path/to/log/':'/var/log/clamav':'rw' \
  -v '/path/to/etc/':'/etc/clamav':'rw' \
  --health-start-period=120s \
  --health-interval=60s \
  --health-retries=3 \
  bmmbmm01/clamav-alpine

```
Use `-d` instead of `-it` if you want to detach and move along.


#### Volumes

There are 3 Main volumes in the image that should have there own volume mounts...
- /mnt/user/appdata/ClamAV/log:/var/log/clamav  # Log storage but will function with out it mounted
- /mnt/user/appdata/ClamAV/db:/var/lib/clamav  # ClamAV database but will function with out it mounted recomend for access to what is scaned
- /mnt/user/appdata/ClamAV/etc:/etc/clamav  # ClamAV configuration but will function with out it mounted recomend to edite exclude files to bottom of clamd
- /mnt/user:/scan  # The directory to scan (Defulat /mnt/user) MUST HAVE!

### Examples docker run

```
docker run -d \
  --name='ClamAV clamdscan' \
  --net='host' \
  --pids-limit 2048 \
  --privileged=true \
  -e TZ="America/Chicago" \
  -e HOST_OS="Unraid" \
  -e HOST_CONTAINERNAME="ClamAV" \
  -e 'USER_ID'='0' \
  -e 'GROUP_ID'='0' \
  -l net.unraid.docker.managed=dockerman \
  -l net.unraid.docker.icon='https://github.com/tquizzle/clamav-alpine/blob/master/img/clamav.png?raw=1' \
  -v '/mnt/user/':'/scan':'ro' \
  -v '/mnt/user/appdata/test/db/':'/var/lib/clamav':'rw' \
  -v '/mnt/user/appdata/test/log/':'/var/log/clamav':'rw' \
  -v '/mnt/user/appdata/test/etc/':'/etc/clamav':'rw' \
  --health-start-period=120s \
  --health-interval=60s \
  --health-retries=3 \
  bmmbmm01/clamav-alpine
```
Docker compose versioon exisit in this repo:
https://github.com/bmartino1/ClamAV

## Expected Output

**Start of ClamD**
```
Tue Oct 29 04:22:16 2024 -> +++ Started at Tue Oct 29 04:22:16 2024
Tue Oct 29 04:22:16 2024 -> Received 0 file descriptor(s) from systemd.
Tue Oct 29 04:22:16 2024 -> clamd daemon 0.104.3 (OS: Linux, ARCH: x86_64, CPU: x86_64)
Tue Oct 29 04:22:16 2024 -> Log file size limited to 4294967295 bytes.
Tue Oct 29 04:22:16 2024 -> Reading databases from /var/lib/clamav
Tue Oct 29 04:22:16 2024 -> Not loading PUA signatures.
Tue Oct 29 04:22:16 2024 -> Bytecode: Security mode set to "TrustSigned".
Tue Oct 29 04:22:33 2024 -> Loaded 8698887 signatures.
Tue Oct 29 04:22:37 2024 -> LOCAL: Removing stale socket file /var/run/clamav/clamd.sock
Tue Oct 29 04:22:37 2024 -> LOCAL: Unix socket file /var/run/clamav/clamd.sock
Tue Oct 29 04:22:37 2024 -> LOCAL: Setting connection queue length to 200
Tue Oct 29 04:22:37 2024 -> Limits: Global time limit set to 120000 milliseconds.
Tue Oct 29 04:22:37 2024 -> Limits: Global size limit set to 104857600 bytes.
Tue Oct 29 04:22:37 2024 -> Limits: File size limit set to 26214400 bytes.
Tue Oct 29 04:22:37 2024 -> Limits: Recursion level limit set to 17.
Tue Oct 29 04:22:37 2024 -> Limits: Files limit set to 10000.
Tue Oct 29 04:22:37 2024 -> Limits: Core-dump limit is 0.
Tue Oct 29 04:22:37 2024 -> Limits: MaxEmbeddedPE limit set to 10485760 bytes.
Tue Oct 29 04:22:37 2024 -> Limits: MaxHTMLNormalize limit set to 10485760 bytes.
Tue Oct 29 04:22:37 2024 -> Limits: MaxHTMLNoTags limit set to 2097152 bytes.
Tue Oct 29 04:22:37 2024 -> Limits: MaxScriptNormalize limit set to 5242880 bytes.
Tue Oct 29 04:22:37 2024 -> Limits: MaxZipTypeRcg limit set to 1048576 bytes.
Tue Oct 29 04:22:37 2024 -> Limits: MaxPartitions limit set to 50.
Tue Oct 29 04:22:37 2024 -> Limits: MaxIconsPE limit set to 100.
Tue Oct 29 04:22:37 2024 -> Limits: MaxRecHWP3 limit set to 16.
Tue Oct 29 04:22:37 2024 -> Limits: PCREMatchLimit limit set to 100000.
Tue Oct 29 04:22:37 2024 -> Limits: PCRERecMatchLimit limit set to 2000.
Tue Oct 29 04:22:37 2024 -> Limits: PCREMaxFileSize limit set to 26214400.
Tue Oct 29 04:22:37 2024 -> Archive support enabled.
Tue Oct 29 04:22:37 2024 -> AlertExceedsMax heuristic detection disabled.
Tue Oct 29 04:22:37 2024 -> Heuristic alerts enabled.
Tue Oct 29 04:22:37 2024 -> Portable Executable support enabled.
Tue Oct 29 04:22:37 2024 -> ELF support enabled.
Tue Oct 29 04:22:37 2024 -> Mail files support enabled.
Tue Oct 29 04:22:37 2024 -> OLE2 support enabled.
Tue Oct 29 04:22:37 2024 -> PDF support enabled.
Tue Oct 29 04:22:37 2024 -> SWF support enabled.
Tue Oct 29 04:22:37 2024 -> HTML support enabled.
Tue Oct 29 04:22:37 2024 -> XMLDOCS support enabled.
Tue Oct 29 04:22:37 2024 -> HWP3 support enabled.
Tue Oct 29 04:22:37 2024 -> Self checking every 600 seconds.
Tue Oct 29 04:22:37 2024 -> Listening daemon: PID: 14
Tue Oct 29 04:22:37 2024 -> MaxQueue set to: 100
Tue Oct 29 04:22:37 2024 -> Set stacksize to 1048576
```

**End of a scan in docker log**

```
Tue Oct 29 10:17:56 2024 -> /scan/Dockers/PhotoPrism/storage/sidecar/brandon/Google Pixel 7 Pro/Messages/7594cab4-9333-4e31-874c-887741083bc0.yml: OK

----------- SCAN SUMMARY -----------
Infected files: 0
Time: 391.872 sec (6 m 31 s)
Start Date: 2024:10:29 10:11:25
End Date:   2024:10:29 10:17:57
Displaying any 'Found' infected files:
```

**You can then check your log files in the log folder
example log.log when you have mutiple folder setup to scan...**

```
--------------------------------------

----------- SCAN SUMMARY -----------
Infected files: 0
Time: 0.006 sec (0 m 0 s)
Start Date: 2024:10:29 04:23:16
End Date:   2024:10:29 04:23:16
--------------------------------------

----------- SCAN SUMMARY -----------
Infected files: 0
Time: 3827.306 sec (63 m 47 s)
Start Date: 2024:10:29 04:23:16
End Date:   2024:10:29 05:27:04
--------------------------------------
```
