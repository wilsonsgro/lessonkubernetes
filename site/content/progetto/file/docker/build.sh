#!/usr/bin/env bash
# Costruisce un'immagine da un contesto pulito (tar senza .env, node_modules, log) e stampa il tag basato sul contenuto.
set -euo pipefail
nome=$1; sorgente=$2; extra=${3:-}; shift $(( $# < 3 ? $# : 3 ))

contesto=$(mktemp -d /tmp/biodistretto-build-XXXXXX)
trap 'rm -rf "$contesto"' EXIT

tar -C "$sorgente" \
  --exclude='./.env' --exclude='./.env.*' --exclude='./node_modules' --exclude='./dist' \
  --exclude='./storage/logs/*' --exclude='./storage/framework/sessions/*' \
  --exclude='./storage/framework/cache/data/*' --exclude='./storage/framework/views/*' \
  -cf - . | tar -C "$contesto" -xf -
if [ -n "$extra" ]; then cp -a "$extra"/. "$contesto"/; fi

docker build -q -t "$nome:build" "$@" "$contesto" > /dev/null
id=$(docker image inspect --format '{{.Id}}' "$nome:build" | cut -d: -f2 | cut -c1-12)
docker tag "$nome:build" "$nome:$id"
echo "$nome:$id"
