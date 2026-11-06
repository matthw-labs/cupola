#!/usr/bin/env bash

# Bootstrap the complete disposable macOS/OrbStack laboratory.
#
# The script deliberately keeps generated state and credentials outside Git.
# It copies tracked seeds into .ai/scratch before starting containers; vendor
# services are therefore free to rewrite their own config and databases.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(cd -- "$script_dir/../../.." && pwd)"
compose_file="$repo_root/docker-compose.testlab.yml"
project="${CUPOLA_TESTLAB_PROJECT:-cupola-testlab}"
state_dir="${CUPOLA_TESTLAB_STATE_DIR:-$repo_root/.ai/scratch/zz_testlab/state}"

if [[ "$state_dir" != /* ]]; then
  state_dir="$repo_root/$state_dir"
fi

safe_state_root="$repo_root/.ai/scratch/zz_testlab"
case "$state_dir" in
  "$safe_state_root"/*) ;;
  *)
    printf 'Refusing state directory outside %s: %s\n' "$safe_state_root" "$state_dir" >&2
    exit 2
    ;;
esac

reset=false
case "${1:-}" in
  "") ;;
  --reset) reset=true ;;
  --help|-h)
    printf 'Usage: %s [--reset]\n' "$0"
    printf '  --reset  stop this Compose project and remove only its disposable state\n'
    exit 0
    ;;
  *)
    printf 'Unknown option: %s\n' "$1" >&2
    exit 2
    ;;
esac

command -v docker >/dev/null || { printf 'docker is required\n' >&2; exit 1; }
command -v curl >/dev/null || { printf 'curl is required\n' >&2; exit 1; }
command -v python3 >/dev/null || { printf 'python3 is required\n' >&2; exit 1; }

cd "$repo_root"
if [[ "$(docker context show)" != "orbstack" ]]; then
  printf 'The macOS lab requires the OrbStack Docker context (current: %s).\n' "$(docker context show)" >&2
  exit 1
fi

compose=(docker compose -p "$project" -f "$compose_file")
profiles=(
  --profile core
  --profile downloads
  --profile media
  --profile infra
  --profile protocol-mocks
)

if [[ "$reset" == true ]]; then
  "${compose[@]}" "${profiles[@]}" down -v --remove-orphans || true
  rm -rf "$state_dir"
fi

mkdir -p "$state_dir"

install_seed() {
  local source="$1"
  local destination="$2"
  if [[ ! -e "$destination" ]]; then
    mkdir -p "$(dirname -- "$destination")"
    cp "$source" "$destination"
  fi
}

# These files are intentionally copied, never mounted from the tracked tree.
for service in radarr sonarr lidarr readarr prowlarr; do
  install_seed \
    "$script_dir/seed/$service/config.xml" \
    "$state_dir/$service/config.xml"
done
install_seed \
  "$script_dir/seed/bazarr/config/config.yaml" \
  "$state_dir/bazarr/config/config.yaml"
install_seed \
  "$script_dir/seed/qbittorrent/qBittorrent/qBittorrent.conf" \
  "$state_dir/qbittorrent/qBittorrent/qBittorrent.conf"
install_seed \
  "$script_dir/seed/qbittorrent-seed/qBittorrent/qBittorrent.conf" \
  "$state_dir/qbittorrent-seed/qBittorrent/qBittorrent.conf"
install_seed \
  "$repo_root/test/e2e/seed/sabnzbd/sabnzbd.ini" \
  "$state_dir/sabnzbd/sabnzbd.ini"
install_seed \
  "$script_dir/seed/stacks/immich/docker-compose.yml" \
  "$state_dir/stacks/immich/docker-compose.yml"
install_seed \
  "$script_dir/seed/downloads/cupola-test.nzb" \
  "$state_dir/cupola-test.nzb"

# The TrueNAS mock serves TLS, because the app refuses an address that is not
# https://. Its self-signed certificate is made once and kept in the state
# directory, so the container finds it at start; the app trusts it by the
# fingerprint written to the credentials below.
truenas_cert_fingerprint="$("$script_dir/truenas_cert.sh" --state-dir "$state_dir" fingerprint)"

printf 'Starting Compose project %s...\n' "$project"
"${compose[@]}" "${profiles[@]}" up -d --wait

curl_bin="$(command -v curl)"
python_bin="$(command -v python3)"

json_get() {
  local file="$1"
  shift
  "$python_bin" - "$file" "$@" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
for key in sys.argv[2:]:
    if isinstance(value, dict):
        value = value.get(key)
    elif isinstance(value, list):
        value = value[int(key)]
    else:
        value = None
    if value is None:
        raise SystemExit(1)
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, separators=(",", ":")))
else:
    print(value)
PY
}

wait_http() {
  local url="$1"
  local attempt
  for attempt in $(seq 1 60); do
    if "$curl_bin" -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  printf 'Timed out waiting for %s\n' "$url" >&2
  return 1
}

post_json() {
  local url="$1"
  local body="$2"
  shift 2
  "$curl_bin" -fsS --retry 3 -H 'Content-Type: application/json' "$@" \
    -X POST "$url" --data-binary "$body"
}

jellyfin_url="http://127.0.0.1:8096"
jellyfin_info="$state_dir/.jellyfin-info.json"
wait_http "$jellyfin_url/System/Info/Public"
"$curl_bin" -fsS "$jellyfin_url/System/Info/Public" >"$jellyfin_info"
if [[ "$(json_get "$jellyfin_info" StartupWizardCompleted 2>/dev/null || true)" != true ]]; then
  post_json "$jellyfin_url/Startup/Configuration" \
    '{"ServerName":"Cupola Lab","UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' \
    >/dev/null
  # Jellyfin 12.x exposes the first-user route lazily. Read it once before
  # posting the startup user, otherwise a fresh server can answer 404.
  "$curl_bin" -fsS "$jellyfin_url/Startup/User" >/dev/null
  post_json "$jellyfin_url/Startup/User" \
    '{"Name":"cupola-admin","Password":"cupola-pass"}' \
    >/dev/null
  post_json "$jellyfin_url/Startup/RemoteAccess" \
    '{"EnableRemoteAccess":false,"EnableAutomaticPortMapping":false}' \
    >/dev/null
  "$curl_bin" -fsS -X POST "$jellyfin_url/Startup/Complete" >/dev/null
fi

jellyfin_auth="$state_dir/.jellyfin-auth.json"
jellyfin_header='MediaBrowser Client="Cupola", Device="Cupola TestLab", DeviceId="cupola-testlab", Version="1.0"'
post_json "$jellyfin_url/Users/AuthenticateByName" \
  '{"Username":"cupola-admin","Pw":"cupola-pass","App":"Cupola","AppVersion":"1.0","DeviceId":"cupola-testlab","Device":"Cupola TestLab"}' \
  -H "Authorization: $jellyfin_header" >"$jellyfin_auth"
jellyfin_token="$(json_get "$jellyfin_auth" AccessToken)"
jellyfin_user_id="$(json_get "$jellyfin_auth" User Id)"

# Emby's first run is a module of its own, so the same code walks the wizard
# here and in the validation against a disposable container. It answers the
# administrator's id and the API key named Cupola, which the app is given the
# way it is given Jellyfin's token. Emby listens on 8096 inside; the lab
# publishes it on 8097.
emby_url="http://127.0.0.1:8097"
emby_first_run="$state_dir/.emby-first-run.json"
"$python_bin" "$script_dir/emby_first_run.py" --url "$emby_url" --output "$emby_first_run"
emby_token="$(json_get "$emby_first_run" token)"
emby_user_id="$(json_get "$emby_first_run" userId)"

seerr_url="http://127.0.0.1:5055"
seerr_public="$state_dir/.seerr-public.json"
seerr_cookie="$state_dir/.seerr-cookie"
seerr_response="$state_dir/.seerr-response.json"
wait_http "$seerr_url/api/v1/status"
"$curl_bin" -fsS "$seerr_url/api/v1/settings/public" >"$seerr_public"
if [[ "$(json_get "$seerr_public" initialized 2>/dev/null || true)" != true ]]; then
  rm -f "$seerr_cookie"
  post_json "$seerr_url/api/v1/auth/jellyfin" \
    '{"username":"cupola-admin","password":"cupola-pass","hostname":"jellyfin","port":8096,"useSsl":false,"urlBase":"","email":"cupola@example.test","serverType":2}' \
    -c "$seerr_cookie" -b "$seerr_cookie" >/dev/null
  post_json "$seerr_url/api/v1/settings/jellyfin" \
    "{\"ip\":\"jellyfin\",\"port\":8096,\"useSsl\":false,\"urlBase\":\"\",\"externalHostname\":\"$jellyfin_url\",\"jellyfinForgotPasswordUrl\":\"\",\"apiKey\":\"$jellyfin_token\"}" \
    -c "$seerr_cookie" -b "$seerr_cookie" >/dev/null
  post_json "$seerr_url/api/v1/settings/initialize" \
    '{}' -c "$seerr_cookie" -b "$seerr_cookie" >/dev/null
  post_json "$seerr_url/api/v1/settings/main" \
    '{"locale":"en"}' -c "$seerr_cookie" -b "$seerr_cookie" >"$seerr_response"
fi

# Seerr persists its generated API key in settings.json. Reading that local,
# disposable file also makes reruns recoverable after credentials.env is lost.
seerr_api_key=""
if [[ -f "$state_dir/seerr/settings.json" ]]; then
  seerr_api_key="$(json_get "$state_dir/seerr/settings.json" main apiKey 2>/dev/null || true)"
fi
if [[ -z "$seerr_api_key" && -f "$seerr_response" ]]; then
  seerr_api_key="$(json_get "$seerr_response" apiKey 2>/dev/null || true)"
fi
if [[ -z "$seerr_api_key" ]]; then
  printf 'Could not recover Seerr API key from disposable state.\n' >&2
  exit 1
fi
"$curl_bin" -fsS -H "X-Api-Key: $seerr_api_key" "$seerr_url/api/v1/auth/me" >/dev/null

# The requester accounts get new passwords on every run: the seed sets them
# again on the accounts, so the credentials file is always the truth. They
# exist only in that file, never on a command line.
new_password() {
  "$python_bin" -c 'import secrets; print(secrets.token_urlsafe(18))'
}
seerr_requester_password="$(new_password)"
jellyfin_requester_password="$(new_password)"
emby_requester_password="$(new_password)"
# The journeys run inside the app sandbox and cannot start processes. This
# token authorises the loopback control API that moves the lab for them.
control_token="$("$python_bin" -c 'import secrets; print(secrets.token_urlsafe(32))')"

# A Plex server nobody claimed runs with local authentication off and takes
# any token; once someone claims it, only the server's own token reads its
# libraries. That token lives in its Preferences.xml, never on a command line.
plex_token="$("$python_bin" - "$state_dir/plex" <<'PY'
import pathlib, re, sys
for prefs in pathlib.Path(sys.argv[1]).rglob('Preferences.xml'):
    found = re.search(r'PlexOnlineToken="([^"]+)"', prefs.read_text(errors='ignore'))
    if found:
        print(found.group(1))
        break
else:
    print('test-token')
PY
)"

credentials="$state_dir/credentials.env"
umask 077
{
  printf 'CUPOLA_TESTLAB_JELLYFIN_TOKEN=%s\n' "$jellyfin_token"
  printf 'CUPOLA_TESTLAB_JELLYFIN_USER_ID=%s\n' "$jellyfin_user_id"
  printf 'CUPOLA_TESTLAB_SEERR_API_KEY=%s\n' "$seerr_api_key"
  printf 'CUPOLA_TESTLAB_SEERR_REQUESTER_EMAIL=requester@example.com\n'
  printf 'CUPOLA_TESTLAB_SEERR_REQUESTER_PASSWORD=%s\n' "$seerr_requester_password"
  printf 'CUPOLA_TESTLAB_JELLYFIN_REQUESTER_USERNAME=cupola-viewer\n'
  printf 'CUPOLA_TESTLAB_JELLYFIN_REQUESTER_PASSWORD=%s\n' "$jellyfin_requester_password"
  printf 'CUPOLA_TESTLAB_JELLYFIN_PASSWORD=cupola-pass\n'
  printf 'CUPOLA_TESTLAB_EMBY_TOKEN=%s\n' "$emby_token"
  printf 'CUPOLA_TESTLAB_EMBY_USER_ID=%s\n' "$emby_user_id"
  printf 'CUPOLA_TESTLAB_EMBY_PASSWORD=cupola-pass\n'
  printf 'CUPOLA_TESTLAB_EMBY_REQUESTER_USERNAME=cupola-viewer\n'
  printf 'CUPOLA_TESTLAB_EMBY_REQUESTER_PASSWORD=%s\n' "$emby_requester_password"
  printf 'CUPOLA_TESTLAB_NPM_USERNAME=admin@example.com\n'
  printf 'CUPOLA_TESTLAB_NPM_PASSWORD=changeme\n'
  printf 'CUPOLA_TESTLAB_QBITTORRENT_USERNAME=admin\n'
  printf 'CUPOLA_TESTLAB_QBITTORRENT_PASSWORD=cupola-pass\n'
  printf 'CUPOLA_TESTLAB_NZBGET_USERNAME=nzbget\n'
  printf 'CUPOLA_TESTLAB_NZBGET_PASSWORD=tegbzn6789\n'
  printf 'CUPOLA_TESTLAB_TRANSMISSION_USERNAME=transmission\n'
  printf 'CUPOLA_TESTLAB_TRANSMISSION_PASSWORD=transmission\n'
  printf 'CUPOLA_TESTLAB_DOCKGE_USERNAME=cupola\n'
  printf 'CUPOLA_TESTLAB_DOCKGE_PASSWORD=cupola-pass\n'
  printf 'CUPOLA_TESTLAB_PLEX_TOKEN=%s\n' "$plex_token"
  printf 'CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT=%s\n' "$truenas_cert_fingerprint"
  printf 'CUPOLA_TESTLAB_CONTROL_TOKEN=%s\n' "$control_token"
  printf 'CUPOLA_TESTLAB_CONTROL_URL=http://127.0.0.1:8799\n'
  printf 'CUPOLA_TESTLAB_TOXIPROXY_URL=http://127.0.0.1:8474\n'
} >"$credentials"
chmod 600 "$credentials"

# Dockge has no REST setup endpoint; provision its first disposable account
# through the same Socket.IO setup event used by its web UI. The helper treats
# an existing account as success, so normal reruns remain idempotent.
DOCKGE_SETUP_USERNAME=cupola \
DOCKGE_SETUP_PASSWORD=cupola-pass \
  "${compose[@]}" exec -T dockge node - <"$script_dir/dockge_setup.js"

printf '\nExporting World A...\n'
dart run tool/testlab/export_world.dart --output "$state_dir/world.json"

printf '\nForging the synthetic release...\n'
"${compose[@]}" --profile forge run --rm testlab-forge

printf '\nSeeding deterministic media and queue specimens...\n'
python3 "$script_dir/seed_lab.py" --state-dir "$state_dir"

# Sara's Seerr (P9) is a server of its own: the same image, its own port and
# state. It needs the Jellyfin users the seed above made, so it comes after
# it. The script waits for the container, runs the first-setup routes and
# seeds the accounts and the operator's pending request, and writes the
# passwords it generates to seerr-sara.json inside the state directory.
printf '\nSetting up the second Seerr (Sara'"'"'s)...\n'
python3 "$script_dir/seerr_sara.py" --state-dir "$state_dir"

rm -f "$emby_first_run" "$jellyfin_info" "$jellyfin_auth" "$seerr_public" "$seerr_cookie" "$seerr_response"

printf '\nCupola macOS lab is ready.\n'
printf 'Credentials: %s (chmod 600; never commit or paste its contents)\n' "$credentials"
printf 'For a shell client probe: source %q\n' "$credentials"
printf '\nPublished endpoints:\n'
printf '  Seerr              http://127.0.0.1:5055\n'
printf '  Seerr (Sara)       http://127.0.0.1:5056\n'
printf '  Radarr             http://127.0.0.1:7878\n'
printf '  Sonarr             http://127.0.0.1:8989\n'
printf '  Lidarr             http://127.0.0.1:8686\n'
printf '  Readarr            http://127.0.0.1:8787\n'
printf '  Prowlarr           http://127.0.0.1:9696\n'
printf '  Bazarr             http://127.0.0.1:6767\n'
printf '  qBittorrent        http://127.0.0.1:8080\n'
printf '  Transmission        http://127.0.0.1:9091\n'
printf '  SABnzbd            http://127.0.0.1:8082\n'
printf '  NZBGet             http://127.0.0.1:6789\n'
printf '  Jellyfin           http://127.0.0.1:8096\n'
printf '  Emby               http://127.0.0.1:8097\n'
printf '  Plex               http://127.0.0.1:32400\n'
printf '  Dockge             http://127.0.0.1:5001\n'
printf '  Nginx Proxy Manager http://127.0.0.1:8181\n'
printf '  TrueNAS mock       wss://127.0.0.1:8460 (self-signed; pin CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT)\n'
printf '  Unraid mock        http://127.0.0.1:8480/graphql\n'

if [[ ! -f "$state_dir/dockge/dockge.db" ]]; then
  printf '\nDockge first-run setup is still manual: open http://127.0.0.1:5001 once and create the disposable account.\n'
fi

"${compose[@]}" ps
