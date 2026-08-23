#!/usr/bin/env bash
# Deploy universal pipeline to neoag-100T (run from dev machine with SSH to 66/134).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="/mnt/neoag_100T/majiaxin/neoag-universal-pipeline"
HOST="${DEPLOY_HOST:-10.200.50.134}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_cross_server}"

echo "==> deploy ${SRC} -> root@${HOST}:${DEST}"
ssh -i "$KEY" -o BatchMode=yes "root@${HOST}" "mkdir -p '${DEST}'"
rsync -av --chmod=Du=rwx,Dgo=rx,Fu=rwX,Fgo=rX \
  -e "ssh -i $KEY -o BatchMode=yes" \
  "${SRC}/" "root@${HOST}:${DEST}/"
ssh -i "$KEY" -o BatchMode=yes "root@${HOST}" "chmod +x ${DEST}/scripts/*.sh ${DEST}/deploy_to_neoag_100T.sh 2>/dev/null; ls -la ${DEST}/scripts/"
echo "==> done: ${DEST}"
