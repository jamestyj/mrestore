# mrestore

Bash script that uses the MongoDB Management Service ([MMS]
(http://mms.mongodb.com)) Backup [REST API]
(http://mms.mongodb.com/help-hosted/current/reference/api/) to trigger a
restore of the latest snapshot and downloads the resulting tarballs (for both
replica sets and sharded clusters). Supports MMS Cloud and On-Prem/OpsManager.

It is intended to have as few dependencies as possible and thus should work on
most Linux and Mac OS environments without the need to install any additional
software.

Currently tested only on MMS On-Prem 1.5. Your mileage may vary. Please report
bugs via Github Issues or better yet, send fixes and patches via pull requests.


### Prerequisites

In the MMS web UI:

  1. Enable Public API for the MMS group to restore from
  2. Generate an API key
  3. Whitelist the IP address from which `mrestore` is run
  4. Go to the URL of the replica set or cluster that you want to restore,
     which should be in the following form:
     `https://mms.mongodb.com/host/detail/XXXXXXX/YYYYYYY`
     - The group ID is `XXXXXXX`
     - The cluster ID is `YYYYYYY`

For details, refer to the MMS [API docs]
(https://docs.mms.mongodb.com/tutorial/use-mms-public-api/).


### Usage

    $ ./mrestore.sh
    Usage: mrestore.sh PARAMS [OPTIONS]

    Required parameters:
      --server-url MMS_URL     MMS server URL (eg. https://mms.mongodb.com)
      --user MMS_USER          MMS username, usually an email
      --api-key API_KEY        MMS API key (eg. xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
      --group-id GROUP_ID      MMS group ID   (eg. 54c64146ae9fbe3d7f32c726)
      --cluster-id CLUSTER_ID  MMS cluster ID (eg. 54c641560cf294969781b5c3)

    Options:
      --out-dir DIRECTORY      Download directory. Default: '.'
      --timeout TIMEOUT_SECS   Connection timeout. Default: 5

    Miscellaneous:
      --help                   Show this help message


### Sample output (replica set)

    $ ./mrestore.sh --server-url https://mms.mongodb.com \
                    --user admin@localhost.com \
                    --api-key 9d2fb094-108a-4c63-9ce6-5f79bbd8bd50 \
                    --group-id 54c64146ae9fbe3d7f32c726 \
                    --cluster-id 54c641560cf294969781b5c3

    Cluster type    : REPLICA_SET
    Replica set name: mms-app

    Latest snapshot ID: 54cc87420cf25152251c0353
    Created on        : 2015-01-31T07:40:23Z
    Complete?         : true

    MongoDB version   : 2.6.7
    Data size         : 1.4 MB
    Storage size      : 4.41 GB
    File size         : 7.49 GB (uncompressed)

    Restore job ID: 54ccbe6e0cf2d19b280496b2
    Waiting for restore job....
    Status: FINISHED

    Downloading restore tarball(s) to ./...
      % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                     Dload  Upload   Total   Spent    Left  Speed
    100 12.3M    0 12.3M    0     0   400k      0 --:--:--  0:00:31 --:--:--  526k
    Wrote to './54cc85f3504d16cb0bf4085d-mms-app-1422690023.tar.gz' (12.3 MB)

Note that any existing files with the same name will be overwritten.

### Sample output (sharded cluster)

    $ ./mrestore.sh --server-url https://mms.mongodb.com \
                    --user admin@localhost.com \
                    --api-key 9d2fb094-108a-4c63-9ce6-5f79bbd8bd50 \
                    --group-id 54c64146ae9fbe3d7f32c726 \
                    --cluster-id 54c641560cf29493312346aa

    Cluster type: SHARDED_REPLICA_SET
    Cluster name: Cluster 3

    Latest snapshot ID: 54cc9bc70cf2c0b4053c592b
    Created on        : 2015-01-31T09:08:56Z
    Complete?         : true

    Part              : 0
    Type name         : REPLICA_SET
    Replica set name  : shard01
    MongoDB version   : 2.6.7
    Data size         : 109.2 MB
    Storage size      : 126.1 MB
    File size         : 256.0 MB (uncompressed)

    Part              : 1
    Type name         : REPLICA_SET
    Replica set name  : shard02
    MongoDB version   : 2.6.7
    Data size         : 64.0 MB
    Storage size      : 92.3 MB
    File size         : 256.0 MB (uncompressed)

    Part              : 2
    Type name         : CONFIG_SERVER
    MongoDB version   : 2.6.7
    Data size         : 20 KB
    Storage size      : 20.1 MB
    File size         : 128.0 MB (uncompressed)

    Batch ID: 54ccbed20cf2d19b280496cc
    Waiting for restore job....
    Status: FINISHED

    Downloading restore tarball(s) to ./...
      % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                     Dload  Upload   Total   Spent    Left  Speed
    100  130k    0  130k    0     0   208k      0 --:--:-- --:--:-- --:--:--  208k
    Wrote to './54cc85f3504d16cb0bf4085d-config-4f2e12eeb9c155a8c7118d78115134c2-1422695336.tar.gz' (132 KB)

      % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                     Dload  Upload   Total   Spent    Left  Speed
    100 13.1M    0 13.1M    0     0  3416k      0 --:--:--  0:00:03 --:--:-- 3416k
    Wrote to './54cc85f3504d16cb0bf4085d-shard02-1422695336.tar.gz' (13.1 MB)

      % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                     Dload  Upload   Total   Spent    Left  Speed
    100 21.9M    0 21.9M    0     0  3338k      0 --:--:--  0:00:06 --:--:-- 3795k
    Wrote to './54cc85f3504d16cb0bf4085d-shard01-1422695336.tar.gz' (21.9 MB)

Note that any existing files with the same name will be overwritten.
