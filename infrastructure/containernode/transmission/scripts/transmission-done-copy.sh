#!/bin/sh
set -eu

if [ -w /proc/1/fd/1 ] && [ -w /proc/1/fd/2 ]; then
  exec >/proc/1/fd/1 2>/proc/1/fd/2
fi

dest_root="${TR_COPY_DEST_ROOT:-/incoming}"
staging_root="${dest_root%/}/.transmission-staging"
source_dir="${TR_TORRENT_DIR:?missing TR_TORRENT_DIR}"
source_name="${TR_TORRENT_NAME:?missing TR_TORRENT_NAME}"
torrent_hash="${TR_TORRENT_HASH:-$(date +%s)}"
source_path="${source_dir%/}/$source_name"

if [ ! -e "$source_path" ]; then
  printf '[transmission-done-copy] missing source path %s\n' "$source_path" >&2
  exit 1
fi

mkdir -p "$staging_root"

final_name="$source_name"
final_path="${dest_root%/}/$final_name"
if [ -e "$final_path" ]; then
  final_name="${source_name}.${torrent_hash}"
  final_path="${dest_root%/}/$final_name"
fi

stage_path="${staging_root%/}/${final_name}.${torrent_hash}.partial"
rm -rf "$stage_path"

printf '[transmission-done-copy] copying %s to %s\n' "$source_path" "$final_path"

if [ -d "$source_path" ]; then
  mkdir -p "$stage_path"
  cp -a "$source_path"/. "$stage_path"/
else
  cp -a "$source_path" "$stage_path"
fi

mv "$stage_path" "$final_path"
printf '[transmission-done-copy] completed copy to %s\n' "$final_path"
