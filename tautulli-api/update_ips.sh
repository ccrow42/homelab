#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
APIKEY="55b98340c04f4c10a2b66528e27b72e1"
TAUTULLI_URL="https://tautulli.ccrow.org/api/v2"

CIDR_FILE="$HOME/personal/homelab/tautulli-api/cidrs.txt"
FIREWALL_DIR="$HOME/personal/firewall"

# Static CIDRs
STATIC_CIDRS=(
  "136.226.0.0/16"
  "10.0.0.0/8"
)

# Usernames to query
USERS=(
  "TonyFlyingSquirrel"
  "dotayotte"
  "raecrow"
  "ThePusherRobot"
  "slyboots"
  "rlcrow"
)

# GitOps repo base directory
BASEDIR="$HOME/personal/gitops-cd"
INGRESS_FILES=(
  "$BASEDIR/manifests/externalsvc/synology.yaml"
  "$BASEDIR/manifests/kiwix/kiwix.yaml"
)

# --- Build CIDR file ---

# Start fresh
> "$CIDR_FILE"

# Add static CIDRs
for cidr in "${STATIC_CIDRS[@]}"; do
  echo "$cidr" >> "$CIDR_FILE"
done

# Loop over users and fetch most recent IP
for user in "${USERS[@]}"; do
  ip=$(curl -s "${TAUTULLI_URL}?apikey=${APIKEY}&cmd=get_history&user=${user}&length=1" \
    | jq -r '.response.data.data[0].ip_address // empty')

  if [[ -n "$ip" ]]; then
    echo "${ip}/32" >> "$CIDR_FILE"
  else
    echo "⚠️  No IP found for $user" >&2
  fi
done

# Deduplicate and sort
sort -u "$CIDR_FILE" -o "$CIDR_FILE"

echo "✅ CIDR list built at $CIDR_FILE"

# --- Update ingress files ---

# Create a comma-separated string of CIDRs
CIDR_LIST=$(paste -sd, "$CIDR_FILE")

for file in "${INGRESS_FILES[@]}"; do
  if [[ -f "$file" ]]; then
    sed -i "s#nginx.ingress.kubernetes.io/whitelist-source-range:.*#nginx.ingress.kubernetes.io/whitelist-source-range: \"$CIDR_LIST\"#" "$file"
    echo "✅ Updated whitelist-source-range in $file"
  else
    echo "⚠️  File not found: $file"
  fi
done

echo "updating git in 10 sec"
sleep 10

# --- Git commit changes ---
cd "$BASEDIR"
#git pull || echo "ERROR: can't pull"; exit 1
if [[ -n "$(git status --porcelain)" ]]; then
  git add .
  git commit -m "automated whitelist update"
  echo "✅ Changes committed in $BASEDIR"
else
  echo "ℹ️  No changes to commit in $BASEDIR"
fi

git push

echo "updating firewall in 10 sec"
sleep 10
cd $FIREWALL_DIR
./install_fw2.sh