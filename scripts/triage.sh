#!/usr/bin/env bash
set -eu

log_file=${1:-sample/access.log}
if [ ! -r "$log_file" ]; then
    printf 'Cannot read log file: %s\n' "$log_file" >&2
    exit 1
fi

printf 'Top 5 endpoints (request count + path)\n'
awk '{ count[$3]++ } END { for (path in count) print count[path], path }' "$log_file" | sort -nr | head -5

printf '\n5xx responses per minute (YYYY-MM-DDTHH:MM + count)\n'
awk '$4 ~ /^5/ { minute = substr($1, 1, 16); count[minute]++ } END { for (minute in count) print minute, count[minute] }' "$log_file" | sort

printf '\nSlowest 10 requests (latency seconds + method + path + status + timestamp)\n'
awk '{ print $5, $2, $3, $4, $1 }' "$log_file" | sort -nr | head -10
