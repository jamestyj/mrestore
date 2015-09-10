#!/usr/bin/env bash
#
# Bash script that uses the MongoDB Cloud/Ops Manager REST API to trigger a
# restore of the latest snapshot and downloads the resulting tarball(s).
#
# See https://github.com/jamestyj/mrestore for details.
#
# Version: 1.2.1
# Author : James Tan <james.tan@mongodb.com>

set -e

MMS_API_VERSION=1.0
OUT_DIR=.
TIMEOUT=5

# -------------------------------------------------------------------------
# <JSON.sh>
# Adapted from https://github.com/dominictarr/JSON.sh/blob/master/JSON.sh

throw() {
  echo "$*" >&2
  exit 1
}

JSON_tokenize () {
  local GREP
  local ESCAPE
  local CHAR

  if echo "test string" | egrep -ao --color=never "test" &>/dev/null; then
    GREP='egrep -ao --color=never'
  else
    GREP='egrep -ao'
  fi

  if echo "test string" | egrep -o "test" &>/dev/null; then
    ESCAPE='(\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})'
    CHAR='[^[:cntrl:]"\\]'
  else
    GREP=awk_egrep
    ESCAPE='(\\\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})'
    CHAR='[^[:cntrl:]"\\\\]'
  fi

  local STRING="\"$CHAR*($ESCAPE$CHAR*)*\""
  local NUMBER='-?(0|[1-9][0-9]*)([.][0-9]*)?([eE][+-]?[0-9]*)?'
  local KEYWORD='null|false|true'
  local SPACE='[[:space:]]+'

  $GREP "$STRING|$NUMBER|$KEYWORD|$SPACE|." | egrep -v "^$SPACE$"
}

JSON_parse () {
  read -r token
  JSON_parse_value
  read -r token
  case "$token" in
    '') ;;
    *) throw "EXPECTED EOF GOT $token" ;;
  esac
}

JSON_parse_value () {
  local jpath="${1:+$1,}$2" isleaf=0 isempty=0
  case "$token" in
    '{') JSON_parse_object "$jpath" ;;
    '[') JSON_parse_array  "$jpath" ;;
    # At this point, the only valid single-character tokens are digits.
    ''|[!0-9]) throw "EXPECTED value GOT ${token:-EOF}" ;;
    *) value=$token
       isleaf=1
       [ "$value" = '""' ] && isempty=1
       ;;
  esac
  [ "$value" = '' ] && return
  [ "$isleaf" -eq 1 ] && [ $isempty -eq 0 ] && printf "[%s]\t%s\n" "$jpath" "$value"
  :
}

JSON_parse_array () {
  local index=0 ary=''
  read -r token
  case "$token" in
    ']') ;;
    *)
      while :; do
        JSON_parse_value "$1" "$index"
        index=$((index+1))
        ary="$ary""$value"
        read -r token
        case "$token" in
          ']') break ;;
          ',') ary="$ary," ;;
          *) throw "EXPECTED , or ] GOT ${token:-EOF}" ;;
        esac
        read -r token
      done
      ;;
  esac
}

JSON_parse_object () {
  local key
  local obj=''
  read -r token
  case "$token" in
    '}') ;;
    *)
      while :; do
        case "$token" in
          '"'*'"') key=$token ;;
          *) throw "EXPECTED string GOT ${token:-EOF}" ;;
        esac
        read -r token
        case "$token" in
          ':') ;;
          *) throw "EXPECTED : GOT ${token:-EOF}" ;;
        esac
        read -r token
        JSON_parse_value "$1" "$key"
        obj="$obj$key:$value"
        read -r token
        case "$token" in
          '}') break ;;
          ',') obj="$obj," ;;
          *) throw "EXPECTED , or } GOT ${token:-EOF}" ;;
        esac
        read -r token
      done
    ;;
  esac
}

# </JSON.sh>
# -------------------------------------------------------------------------

usage() {
  local self=`basename $0`
  echo "Usage: $self PARAMS [OPTIONS]"
  echo
  echo "Required parameters:"
  echo "  --server-url URL         Cloud/Ops Manager server URL (eg. https://cloud.mongodb.com)"
  echo "  --user USER              Cloud/Ops Manager username, usually an email"
  echo "  --api-key API_KEY        Cloud/Ops Manager API key (eg. xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
  echo "  --group-id GROUP_ID      Cloud/Ops Manager group ID   (eg. 54c64146ae9fbe3d7f32c726)"
  echo "  --cluster-id CLUSTER_ID  Cloud/Ops Manager cluster ID (eg. 54c641560cf294969781b5c3)"
  echo
  echo "Options:"
  echo "  --out-dir DIRECTORY      Download directory. Default: '$OUT_DIR'"
  echo "  --timeout TIMEOUT_SECS   Connection timeout. Default: $TIMEOUT"
  echo
  echo "Miscellaneous:"
  echo "  --help                   Show this help message"
}

parse_options() {
  [ $# -eq 0 ] && usage && exit 1
  while [ $# -gt 0 ]; do
    case "$1" in
      --server-url) shift; MMS_SERVER_URL=$1;;
      --user      ) shift; MMS_USER=$1;;
      --api-key   ) shift; MMS_API_KEY=$1;;
      --group-id  ) shift; GROUP_ID=$1;;
      --cluster-id) shift; CLUSTER_ID=$1;;
      --out-dir   ) shift; OUT_DIR=$1;;
      --timeout   ) shift; TIMEOUT=$1;;
      -h|--help   ) usage; exit 0;;
      *           ) echo "Unknown option(s): $*"; exit 1;;
    esac
    shift || true
  done
  [ "$MMS_USER"       = "" ] && echo "--user is not specified"       && exit 1;
  [ "$MMS_API_KEY"    = "" ] && echo "--api-key is not specified"    && exit 1;
  [ "$MMS_SERVER_URL" = "" ] && echo "--server-url is not specified" && exit 1;
  [ "$GROUP_ID"       = "" ] && echo "--group-id is not specified"   && exit 1;
  [ "$CLUSTER_ID"     = "" ] && echo "--cluster-id is not specified" && exit 1;

  CURL_OPTS="--connect-timeout $TIMEOUT --max-time $TIMEOUT --fail --silent --show-error --digest"
}

api_get() {
  local url="groups/$GROUP_ID/clusters/$CLUSTER_ID$1"
  curl $CURL_OPTS -u "$MMS_USER:$MMS_API_KEY" \
       "$MMS_SERVER_URL/api/public/v$MMS_API_VERSION/$url" 2>&1
}

api_post() {
  local url="groups/$GROUP_ID/clusters/$CLUSTER_ID$1"
  local data=$2
  curl  $CURL_OPTS -u "$MMS_USER:$MMS_API_KEY" \
       -X POST -H "Content-Type: application/json" --data "$data" \
       "$MMS_SERVER_URL/api/public/v$MMS_API_VERSION/$url" 2>&1
}

get_val() {
  local json=$1
  local grep_field=$2
  shift 2
  local cut_args=$*
  echo $json | JSON_tokenize | JSON_parse | grep "\[$grep_field\]" | cut $cut_args
}

get_cluster_info() {
  local res=$(api_get)
  if echo "$res" | grep -q "curl: ("; then
    echo "$res"
    if echo "$res" | grep -q ": 404"; then
      echo "ERROR: Ensure that the group and cluster IDs are correct"
    elif echo "$res" | grep -q ": 401"; then
      echo "ERROR: Ensure that the user and API key are correct"
    else
      echo "ERROR: Can't reach Cloud/Ops Manager at $MMS_SERVER_URL"
    fi
    exit 1
  fi

  TYPE_NAME=$(get_val "$res" '"typeName"' -f4 -d'"')
  case "$TYPE_NAME" in
    "REPLICA_SET")
      local rs_name=$(get_val "$res" '"replicaSetName"' -f4 -d'"')
      echo "Cluster type    : $TYPE_NAME"
      echo "Replica set name: $rs_name";;
    "SHARDED_REPLICA_SET")
      local cluster_name=$(get_val "$res" '"clusterName"' -f4 -d'"')
      echo "Cluster type: $TYPE_NAME"
      echo "Cluster name: $cluster_name";;
    *)
      echo "ERROR: Unknown cluster type"
      exit 1;;
  esac
  echo
}

get_latest_snapshot() {
  local res=$(api_get '/snapshots')
  if echo "$res" | grep -q "curl: ("; then
    echo "$res"
    echo "ERROR: Can't reach Cloud/Ops Manager at $MMS_SERVER_URL"
    exit 1
  fi

  SNAPSHOT_ID=$(       get_val "$res" '"results",0,"id"'                         -f6 -d'"')
  local created_date=$(get_val "$res" '"results",0,"created","date"'             -f8 -d'"')
  local is_complete=$( get_val "$res" '"results",0,"complete"'                   -f2)

  [ "$SNAPSHOT_ID" = "" ] && echo "No snapshots found" && exit 1
  echo "Latest snapshot ID: $SNAPSHOT_ID"
  echo "Created on        : $created_date"
  echo "Complete?         : $is_complete"

  local part=0
  while :; do
    local type_name=$(   get_val "$res" "\"results\",0,\"parts\",$part,\"typeName\""         -f8 -d'"')
    local rs_name=$(     get_val "$res" "\"results\",0,\"parts\",$part,\"replicaSetName\""   -f8 -d'"')
    local mongodb_ver=$( get_val "$res" "\"results\",0,\"parts\",$part,\"mongodVersion\""    -f8 -d'"')
    local data_size=$(   get_val "$res" "\"results\",0,\"parts\",$part,\"dataSizeBytes\""    -f2)
    local storage_size=$(get_val "$res" "\"results\",0,\"parts\",$part,\"storageSizeBytes\"" -f2)
    local file_size=$(   get_val "$res" "\"results\",0,\"parts\",$part,\"fileSizeBytes\""    -f2)

    [ ! "$type_name" ] && break

    echo
    if [ "$TYPE_NAME" = "SHARDED_REPLICA_SET" ]; then
      echo "Part              : $part"
      echo "Type name         : $type_name"
      [ "$rs_name" ] && \
      echo "Replica set name  : $rs_name"
    fi
    echo "MongoDB version   : $mongodb_ver"
    echo "Data size         : $(format_size $data_size)"
    echo "Storage size      : $(format_size $storage_size)"
    echo "File size         : $(format_size $file_size) (uncompressed)"
    ((part++)) || true
  done
}

restore_snapshot() {
  echo
  local res=$(api_post '/restoreJobs' "{\"snapshotId\": \"$SNAPSHOT_ID\"}")
  if echo "$res" | grep -q "curl: ("; then
    echo "$res"
    if echo "$res" | grep -q ": 403"; then
      echo "ERROR: Ensure that this IP address is whitelisted in Cloud/Ops Manager"
    else
      echo "ERROR: Can't reach Cloud/Ops Manager at $MMS_SERVER_URL"
    fi
    exit 1
  fi
  case "$TYPE_NAME" in
    "REPLICA_SET")
      RESTORE_ID=$(get_val "$res" '"results",0,"id"' -f6 -d'"')
      echo "Restore job ID: $RESTORE_ID";;
    "SHARDED_REPLICA_SET")
      BATCH_ID=$(get_val "$res" '"results",0,"batchId"' -f6 -d'"')
      echo "Batch ID: $BATCH_ID";;
  esac
}

wait_for_restore() {
  echo -n "Waiting for restore job..."

  # Possible status values are: FINISHED IN_PROGRESS BROKEN KILLED
  local part=0
  while :; do
    case "$TYPE_NAME" in
      "REPLICA_SET")
        local res=$(api_get "/restoreJobs/$RESTORE_ID")
        local status=$(get_val "$res" '"statusName"' -f4 -d'"')
        if [ "$status" != "IN_PROGRESS" ]; then
          echo
          echo "Status: $status"
          [ "$status" != "FINISHED" ] && exit 1
          DOWNLOAD_URLS=$(get_val "$res" '"delivery","url"' -f6 -d'"')
          break
        fi
        ;;
      "SHARDED_REPLICA_SET")
        # Wait for all parts in the batch to finish
        local res=$(api_get "/restoreJobs?batchId=$BATCH_ID")
        local status="IN_PROGRESS"
        while :; do
          local part_status=$(get_val "$res" "\"results\",$part,\"statusName\"" -f6 -d'"')
          [ ! "$part_status" ] && status="FINISHED" && break
          [ "$part_status" = "IN_PROGRESS" ] && break
          ((part++)) || true
        done

        if [ "$status" != "IN_PROGRESS" ]; then
          echo
          echo "Status: $status"
          local part=0
          while :; do
            local url=$(get_val "$res" "\"results\",$part,\"delivery\",\"url\"" -f8 -d'"')
            [ ! "$url" ] && break
            DOWNLOAD_URLS+=($url)
            ((part++)) || true
          done
          break
        fi
        ;;
    esac
    sleep 1; echo -n '.'
  done
}

download() {
  echo
  echo "Downloading restore tarball(s) to $OUT_DIR/..."
  mkdir -p "$OUT_DIR"
  for url in "${DOWNLOAD_URLS[@]}"; do
    cd "$OUT_DIR"
    curl -OL $url
    cd - >/dev/null
    local file="$OUT_DIR/$(basename $url)"
    local size=$((`du -k "$file" | cut -f1` * 1024))
    echo "Wrote to '$file' ($(format_size $size))"
    echo
  done
}

format_size() {
  !(echo "1" | bc &>/dev/null) && echo "$1 bytes" && return
  [ $1 -gt $((1024**4)) ] && echo "$(bc <<< "scale=3; $1/1024^4") TB" && return
  [ $1 -gt $((1024**3)) ] && echo "$(bc <<< "scale=2; $1/1024^3") GB" && return
  [ $1 -gt $((1024**2)) ] && echo "$(bc <<< "scale=1; $1/1024^2") MB" && return
  [ $1 -gt $((1024**1)) ] && echo "$(bc <<< "scale=0; $1/1024^1") KB" && return
}

parse_options $*
get_cluster_info
get_latest_snapshot
restore_snapshot
wait_for_restore
download
