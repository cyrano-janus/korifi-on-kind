#!/usr/bin/env bash
set -euo pipefail

# Startet Korifi auf einem lokalen kind-Cluster.
# Wrapper um das gefixte deploy-on-kind.sh aus cloudfoundry/korifi.
#
# Konfiguration über Env-Vars:
#   API_SERVER_FQDN   FQDN der CF API (Default: api.korifi.local)
#   CLUSTER_NAME      Name des kind-Clusters (Default: korifi)

API_SERVER_FQDN="${API_SERVER_FQDN:-api.korifi.local}"
CLUSTER_NAME="${CLUSTER_NAME:-korifi}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KORIFI_REPO="${KORIFI_REPO:-$SCRIPT_DIR/../cfDev/korifi-fixes}"

echo "=== Korifi on Kind: Deploy ==="
echo "  Cluster : $CLUSTER_NAME"
echo "  API-FQDN: $API_SERVER_FQDN"
echo ""

if [[ ! -x "$KORIFI_REPO/scripts/deploy-on-kind.sh" ]]; then
  echo "Fehler: korifi-Repo nicht gefunden unter $KORIFI_REPO" >&2
  echo "Clone es und wende patches/deploy-on-kind-fix-series.patch an:" >&2
  echo "  git clone https://github.com/cloudfoundry/korifi \"$KORIFI_REPO\"" >&2
  echo "  git -C \"$KORIFI_REPO\" am \"$SCRIPT_DIR/patches/\"*.patch" >&2
  exit 1
fi

SKIP_DOCKER_BUILD="${SKIP_DOCKER_BUILD:-1}" \
API_SERVER_FQDN="$API_SERVER_FQDN" \
"$KORIFI_REPO/scripts/deploy-on-kind.sh" "$CLUSTER_NAME"

echo ""
echo "=== Fertig ==="
echo "Verbinden mit:"
echo "  cf api https://$API_SERVER_FQDN:443 --skip-ssl-validation"
echo "  cf auth cf-admin admin"
