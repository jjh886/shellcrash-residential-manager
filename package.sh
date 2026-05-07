#!/bin/sh
# 作用：生成一个可分享的恢复包，不包含任何真实订阅或代理账号。

set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
OUT="$ROOT/../shellcrash-manager-restore.tar.gz"

tar -czf "$OUT" \
  -C "$ROOT/.." \
  --exclude 'shellcrash-residential-manager/backups' \
  --exclude 'shellcrash-residential-manager/*.tar.gz' \
  shellcrash-residential-manager

echo "$OUT"
