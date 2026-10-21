#!/bin/sh
# Arguments are local paths prepared by UpdateInstaller, never shell fragments from release metadata.
set -eu
parent_pid=$1
target=$2
stage=$3
backup=$4
transaction=$5
pending=$6
error_file=$7
directory=$(dirname "$target")
case "$parent_pid" in ''|*[!0-9]*) exit 1 ;; esac
case "$stage" in "$directory"/.ChatGPTUsage-update-*.app) ;; *) exit 1 ;; esac
case "$backup" in "$directory"/.ChatGPTUsage-backup-*.app) ;; *) exit 1 ;; esac
[ -d "$target" ] && [ -d "$stage" ] && [ ! -e "$backup" ]
[ ! -L "$target" ] && [ ! -L "$stage" ] && [ -d "$transaction" ]

fail() {
    printf '%s\n' "$1" > "$error_file"
    if [ -d "$backup" ]; then
        if [ -e "$target" ]; then mv "$target" "$transaction/failed.app"; fi
        mv "$backup" "$target"
    fi
    rm -f "$pending"
    /usr/bin/open -n "$target" || true
    exit 1
}

touch "$transaction/ready"
count=0
while kill -0 "$parent_pid" 2>/dev/null; do
    count=$((count + 1))
    if [ "$count" -ge 60 ]; then
        printf '%s\n' 'The app did not close, so the update was not installed.' > "$error_file"
        rm -f "$pending"
        exit 1
    fi
    sleep 1
done

mv "$target" "$backup" || fail 'The previous app could not be moved. Nothing was installed.'
mv "$stage" "$target" || fail 'The update could not be installed. The previous version was restored.'
/usr/bin/open -n "$target" || fail 'The updated app could not be opened. The previous version was restored.'
count=0
while [ ! -f "$transaction/launched" ]; do
    count=$((count + 1))
    if [ "$count" -ge 30 ]; then
        fail 'The updated app did not start. The previous version was restored. macOS may require approval to open the new version.'
    fi
    sleep 1
done
rm -rf "$backup"
rm -f "$pending" "$error_file"
# Only this transaction's downloaded image and helper remain; the running app is outside it.
rm -rf "$transaction"
