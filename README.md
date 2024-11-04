# WIP reuse previouis or rebuild to use clamdscan

Rebuilding Image for Unraid clamdscan... Users should have a file to edit in db folder clamdscan.sh?
https://github.com/bmartino1/ClamAV

# ClamAV scanning Docker container based on Alpine
 
<!-- TOC -->
- [ClamAV scanning Docker container based on Alpine](#clamav-scanning-docker-container-based-on-alpine)
  - [How-To](#how-to)
    - [Usage](#usage)
      - [Post-Args](#post-args)
      - [Volumes](#volumes)
    - [Examples](#examples)
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
docker run -it \
  -v /path/to/scan:/scan:ro \
  tquinnelly/clamav-alpine
```
Use `-d` instead of `-it` if you want to detach and move along.

#### Post-Args
I took the liberty to include `-i` by default. You can, however, add any you desire.

* `-i` - Only print infected files
* `--log=FILE` - save scan report to FILE
* `--database=FILE/DIR` - load virus database from FILE or load all supported db files from DIR
* `--official-db-only[=yes/no(*)]` - only load official signatures
* `--max-filesize=#n` - files larger than this will be skipped and assumed clean
* `--max-scansize=#n` - the maximum amount of data to scan for each container file
* `--leave-temps[=yes/no(*)]`- do not remove temporary files
* `--file-list=FILE` - scan files from FILE
* `--quiet` - only output error messages
* `--bell` - sound bell on virus detection
* `--cross-fs[=yes(*)/no]` - scan files and directories on other filesystems
* `--move=DIRECTORY` - move infected files into DIRECTORY
* `--copy=DIRECTORY` - copy infected files into DIRECTORY
* `--bytecode-timeout=N` - set bytecode timeout (in milliseconds)
* `--heuristic-alerts[=yes(*)/no]` - toggles heuristic alerts
* `--alert-encrypted[=yes/no(*)]` - alert on encrypted archives and documents
* `--nocerts` - disable authenticode certificate chain verification in PE files
* `--disable-cache` - disable caching and cache checks for hash sums of scanned files

#### Volumes
I only have the `/scan` directory noted above. You can add others in conjunction with the post-args as well.

**Save AV Signatures**

* `-v /path/to/sig:/var/lib/clamav`

**Infected Dir**

* `-v /path/to/infected:/infected`
* Then  you can use either the `--move` or `--copy` post-arg above.

### Examples
Here are some examples of various configurations.

This is the one **I** run. I target 2 cores of my CPU as to not cripple my host. I also log to the DB directory and limit 2G file size scan.

```
docker run -d --name=ClamAV \
  --cpuset-cpus='0,1' \
  -v /path/to/scan:/scan:ro \
  -v /path/to/sig:/var/lib/clamav:rw \
  tquinnelly/clamav-alpine -i --log=/var/lib/clamav/log.log --max-filesize=2048M
```

## Expected Output

```
# docker run -it -v /path:/scan:ro tquinnelly/clamav-alpine -i

2022-07-10T13:05:10+00:00 ClamAV process starting

Updating ClamAV scan DB
ClamAV update process started at Sun Jul 10 13:05:10 2022
daily database available for download (remote version: 26597)
Testing database: '/var/lib/clamav/tmp.c94c177031/clamav-5960cb40f091d042fdbe87b6656dc482.tmp-daily.cvd' ...
Database test passed.
daily.cvd updated (version: 26597, sigs: 1989376, f-level: 90, builder: raynman)
main database available for download (remote version: 62)
Testing database: '/var/lib/clamav/tmp.c94c177031/clamav-f97772d5bbd6c13c61c4ea14c3ebeb86.tmp-main.cvd' ...
Database test passed.
main.cvd updated (version: 62, sigs: 6647427, f-level: 90, builder: sigmgr)
bytecode database available for download (remote version: 333)
Testing database: '/var/lib/clamav/tmp.c94c177031/clamav-5ce3fe7b3dd82e9d6f61c4d68dde2ab0.tmp-bytecode.cvd' ...
Database test passed.
bytecode.cvd updated (version: 333, sigs: 92, f-level: 63, builder: awillia2)

Freshclam updated the DB

ClamAV 0.104.3/26597/Sun Jul 10 07:56:43 2022

Scanning /scan

----------- SCAN SUMMARY -----------
Known viruses: 8621438
Engine version: 0.104.3
Scanned directories: 3171
Scanned files: 16683
Infected files: 0
Data scanned: 3131.81 MB
Data read: 3120.78 MB (ratio 1.00:1)
Time: 375.514 sec (6 m 15 s)
Start Date: 2022:07:10 13:05:53
End Date:   2022:07:10 13:12:08

2022-07-10T13:12:08+00:00 ClamAV scanning finished
```

