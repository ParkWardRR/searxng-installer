#!/usr/bin/env bash
# ==============================================================================
#                      S E A R X N G   I N S T A L L E R                        
# ==============================================================================
#
# An advanced, production-ready, interactive bash installer for deploying a 
# fully anonymized, privacy-respecting SearXNG meta-search engine behind a 
# Valkey bot-limiter, secured by an automated Caddy reverse proxy, and tunneled 
# through a Mullvad/WireGuard VPN.
#
#     ► Architecture: Rootless Podman & systemd Quadlet
#     ► OS Support:   AlmaLinux, Fedora, Ubuntu, Debian, Arch
#     ► Validation:   Fully live-tested on AlmaLinux 10.1 (Heliotrope Lion)
#
# ------------------------------------------------------------------------------
#  🚀 KEY FEATURES
# ------------------------------------------------------------------------------
# • Rootless Podman:    Runs safely in userspace; ZERO root privileges required.
# • systemd Quadlet:    Modern .container files (No bloated docker-compose).
# • Valkey Limiter:     Instant IP-based bot protection and rate limiting.
# • VPN Sidecar (v4):   Routes outgoing searches through WireGuard (Mullvad), 
#                       hiding your IP and preventing Google/Bing blocks.
# • Auto-HTTPS (v3):    Built-in Caddy sidecar for Let's Encrypt SSL.
# • JSON API (v3):      Toggleable structured logging for AI/LLM integration.
#
# ------------------------------------------------------------------------------
#  ⚙️ CONFIGURATION & TUNABLES
# ------------------------------------------------------------------------------
# Customize your deployment by editing the variables in the block below.
#
# [CORE]
# SEARXNG_PORT       Host port to expose the SearXNG Web UI (Default: 8888)
# SEARXNG_DIR        Directory for persistent configs (Default: ~/searxng)
# ENABLE_AUTO_UPDATE Nightly podman-auto-update timer (Default: true)
#
# [API & PROXY]
# ENABLE_JSON_API    Output JSON for AI agents (Open-WebUI) (Default: true)
# ENABLE_CADDY       Auto-deploy Caddy Reverse Proxy sidecar (Default: false)
# CADDY_DOMAIN       Target URL for Let's Encrypt (e.g. search.example.com)
#
# [VPN SIDECAR]
# ENABLE_VPN         Route upstream traffic through Gluetun (Default: false)
# VPN_PROVIDER       Your VPN provider (Default: mullvad)
# VPN_TYPE           Protocol to use (Default: wireguard)
# WIREGUARD_PRIVATE_KEY Cryptographically paired key from provider
# WIREGUARD_ADDRESSES   Internal IP bonded to your key (e.g. 10.x.x.x/32)
#
# ------------------------------------------------------------------------------
#  💻 USAGE & UNINSTALL
# ------------------------------------------------------------------------------
# Execute:      chmod +x ./install_searxng.sh && ./install_searxng.sh
# 
# Uninstall:    systemctl --user disable --now searxng valkey caddy gluetun 
#               podman rm -f searxng valkey caddy gluetun
#               rm -rf ~/searxng
#
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─── Tunables ────────────────────────────────────────────────────────────────
SEARXNG_PORT="${SEARXNG_PORT:-8888}"                    # Host port
SEARXNG_IMAGE="${SEARXNG_IMAGE:-docker.io/searxng/searxng:latest}"
VALKEY_IMAGE="${VALKEY_IMAGE:-docker.io/valkey/valkey:8-alpine}"
CADDY_IMAGE="${CADDY_IMAGE:-docker.io/caddy/caddy:latest}"
SEARXNG_DIR="${SEARXNG_DIR:-${HOME}/searxng}"
SEARXNG_NETWORK="searxng-net"
ENABLE_VALKEY="${ENABLE_VALKEY:-true}"                  # Set false to skip rate-limiter
ENABLE_AUTO_UPDATE="${ENABLE_AUTO_UPDATE:-true}"        # podman-auto-update timer
UWSGI_WORKERS="${UWSGI_WORKERS:-4}"
UWSGI_THREADS="${UWSGI_THREADS:-4}"

# --- v3 Optional Features ---
ENABLE_JSON_API="${ENABLE_JSON_API:-true}"              # format: json (e.g., for LLM Integration)
ENABLE_CADDY="${ENABLE_CADDY:-false}"                   # deploy Caddy reverse proxy sidecar
CADDY_DOMAIN="${CADDY_DOMAIN:-search.example.com}"      # Domain for Caddy auto-HTTPS

# --- v4 VPN Sidecar (Gluetun) ---
ENABLE_VPN="${ENABLE_VPN:-false}"                       # Route outbound traffic via VPN
VPN_TYPE="${VPN_TYPE:-wireguard}"
VPN_PROVIDER="${VPN_PROVIDER:-mullvad}"
WIREGUARD_PRIVATE_KEY="${WIREGUARD_PRIVATE_KEY:-YOUR_PRIVATE_KEY_HERE}"
WIREGUARD_ADDRESSES="${WIREGUARD_ADDRESSES:-10.x.x.x/32}"
GLUETUN_IMAGE="${GLUETUN_IMAGE:-docker.io/qmcgaw/gluetun:latest}"

# ─── Console Formatting ─────────────────────────────────────────────────────
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

_ts()       { date '+%H:%M:%S'; }
log_info()  { echo -e "${CYAN}[$(_ts)] ▸${NC} $1"; }
log_ok()    { echo -e "${GREEN}[$(_ts)] ✔${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[$(_ts)] ⚠${NC} $1"; }
log_err()   { echo -e "${RED}[$(_ts)] ✖${NC} $1" >&2; }
die()       { log_err "$1"; exit 1; }

banner() {
    echo -e "${BOLD}${CYAN}"
    cat <<'ART'
   ____                  __  ___   _____________
  / __/___  ___ _ ____  / / / / | / / ____/ ___/
 _\ \/ -_)/ _ `// __/ / /_/ /  |/ / / __ \__ \ 
/___/\__/ \_,_//_/ /_/\____/|_|//_/_/ /____/___/
          Podman Installer v4
ART
    echo -e "${NC}"
}

# ─── Dependency Detection ───────────────────────────────────────────────────
detect_pkg_mgr() {
    if   command -v dnf     &>/dev/null; then echo "dnf"
    elif command -v apt-get &>/dev/null; then echo "apt-get"
    elif command -v pacman  &>/dev/null; then echo "pacman"
    else die "Unsupported distro. Install Podman manually, then re-run."
    fi
}

pkg_install() {
    local mgr="$1"; shift
    case "$mgr" in
        dnf)     sudo dnf install -y "$@" ;;
        apt-get) sudo apt-get install -y "$@" ;;
        pacman)  sudo pacman -S --noconfirm "$@" ;;
    esac
}

ensure_cmd() {
    local cmd="$1" pkg="${2:-$1}"
    if ! command -v "$cmd" &>/dev/null; then
        log_info "Installing ${cmd}..."
        pkg_install "$PKG_MGR" "$pkg"
    fi
}

# ─── Pre-flight ─────────────────────────────────────────────────────────────
preflight() {
    if [ "$EUID" -eq 0 ]; then
        log_err "Running as root completely breaks Podman's rootless security model on modern systems (e.g. Quadlet/systemd generator failures)."
        die "Aborted. You MUST run this script as a normal, unprivileged user (with sudo access)."
    fi

    PKG_MGR="$(detect_pkg_mgr)"
    log_info "Detected package manager: ${BOLD}${PKG_MGR}${NC}"

    # System update
    log_info "Updating system packages..."
    case "$PKG_MGR" in
        dnf)     sudo dnf update -y -q ;;
        apt-get) sudo apt-get update -qq && sudo apt-get upgrade -y -qq ;;
        pacman)  sudo pacman -Syu --noconfirm ;;
    esac

    ensure_cmd curl
    ensure_cmd openssl
    ensure_cmd podman

    log_ok "Podman $(podman --version | awk '{print $3}') ready."
}

# ─── Podman Network ─────────────────────────────────────────────────────────
setup_network() {
    if ! podman network exists "$SEARXNG_NETWORK" 2>/dev/null; then
        log_info "Creating Podman network ${BOLD}${SEARXNG_NETWORK}${NC}..."
        podman network create "$SEARXNG_NETWORK"
    else
        log_ok "Network ${SEARXNG_NETWORK} already exists."
    fi
}

# ─── Configuration Files ────────────────────────────────────────────────────
generate_config() {
    mkdir -p "${SEARXNG_DIR}/settings"

    local SETTINGS_FILE="${SEARXNG_DIR}/settings/settings.yml"
    local SECRET_KEY
    SECRET_KEY="$(openssl rand -hex 32)"

    log_info "Generating optimised settings.yml..."
    cat > "$SETTINGS_FILE" <<YAML
# SearXNG Settings — auto-generated by install_searxng.sh
# Docs: https://docs.searxng.org/admin/settings/settings.html

use_default_settings: true

general:
  instance_name: "SearXNG"
  privacypolicy_url: false
  donation_url: false
  enable_metrics: true

server:
  secret_key: "${SECRET_KEY}"
  bind_address: "0.0.0.0"
  port: 8080
  image_proxy: true
  method: "POST"
  limiter: ${ENABLE_VALKEY}
  public_instance: false

search:
  safe_search: 0
  autocomplete: "google"
  default_lang: "auto"
  formats:
    - html
$([ "$ENABLE_JSON_API" = "true" ] && echo "    - json")

ui:
  static_use_hash: true
  default_theme: "simple"
  theme_args:
    simple_style: "auto"
  infinite_scroll: true
  query_in_title: true

outgoing:
  request_timeout: 5.0
  max_request_timeout: 15.0
  useragent_suffix: ""
  pool_connections: 100
  pool_maxsize: 20
  enable_http2: true
YAML

    if [ "$ENABLE_VPN" = "true" ]; then
        cat >> "$SETTINGS_FILE" <<VPN
  proxies:
    all://:
      - http://gluetun:8888
VPN
    fi

    cat >> "$SETTINGS_FILE" <<YAML

engines:
  # Prioritise privacy-respecting engines with their own indexes
  - name: brave
    disabled: false
    weight: 1.5
  - name: duckduckgo
    disabled: false
    weight: 1.2
  - name: mojeek
    disabled: false
    weight: 1.0
  - name: qwant
    disabled: false
    weight: 1.0
  - name: startpage
    disabled: false
    weight: 1.0
  # De-prioritise tracker-heavy engines
  - name: google
    disabled: false
    weight: 0.8
  - name: bing
    disabled: false
    weight: 0.6
  - name: yahoo
    disabled: true

YAML

    if [ "$ENABLE_VALKEY" = "true" ]; then
        cat >> "$SETTINGS_FILE" <<YAML
valkey:
  url: "valkey://valkey:6379/0"

YAML
    fi

    chmod 600 "$SETTINGS_FILE"
    log_ok "settings.yml written to ${SETTINGS_FILE}"

    # ── Limiter config ──
    if [ "$ENABLE_VALKEY" = "true" ]; then
        local LIMITER_FILE="${SEARXNG_DIR}/settings/limiter.toml"
        log_info "Generating limiter.toml for bot protection..."
        cat > "$LIMITER_FILE" <<'TOML'
# SearXNG Rate-Limiter Configuration
# Docs: https://docs.searxng.org/admin/searx.botdetection.html

[botdetection.ip_limit]
# Max requests per IP within the sliding window
link_token   = true

[botdetection.ip_lists]
pass_ip      = []
block_ip     = []
# pass_searxng_org = true  # uncomment to pass SearXNG.org monitoring
TOML
        chmod 600 "$LIMITER_FILE"
        log_ok "limiter.toml written."
    fi
}

# ─── Container Cleanup ──────────────────────────────────────────────────────
cleanup_existing() {
    for ctr in searxng valkey caddy gluetun; do
        if podman ps -a --format '{{.Names}}' | grep -qxF "$ctr"; then
            log_warn "Removing existing container: ${ctr}"
            podman stop "$ctr" 2>/dev/null || true
            podman rm -f "$ctr" 2>/dev/null || true
        fi
    done
}

# ─── Pull Images ────────────────────────────────────────────────────────────
pull_images() {
    log_info "Pulling SearXNG image: ${BOLD}${SEARXNG_IMAGE}${NC}..."
    podman pull "$SEARXNG_IMAGE"

    if [ "$ENABLE_VALKEY" = "true" ]; then
        log_info "Pulling Valkey image: ${BOLD}${VALKEY_IMAGE}${NC}..."
        podman pull "$VALKEY_IMAGE"
    fi

    if [ "$ENABLE_CADDY" = "true" ]; then
        log_info "Pulling Caddy image: ${BOLD}${CADDY_IMAGE}${NC}..."
        podman pull "$CADDY_IMAGE"
    fi

    if [ "$ENABLE_VPN" = "true" ]; then
        log_info "Pulling Gluetun image: ${BOLD}${GLUETUN_IMAGE}${NC}..."
        podman pull "$GLUETUN_IMAGE"
    fi
}

# ─── Quadlet (Systemd) Integration ───────────────────────────────────────
setup_quadlet() {
    local QUADLET_DIR="${HOME}/.config/containers/systemd"
    mkdir -p "$QUADLET_DIR"

    log_info "Writing Quadlet unit files to ${QUADLET_DIR}..."

    # ── Network Quadlet ──
    cat > "${QUADLET_DIR}/${SEARXNG_NETWORK}.network" <<EOF
[Network]
NetworkName=${SEARXNG_NETWORK}
EOF

    # ── Valkey Quadlet ──
    if [ "$ENABLE_VALKEY" = "true" ]; then
        cat > "${QUADLET_DIR}/valkey.container" <<EOF
[Unit]
Description=Valkey — In-memory data store for SearXNG rate-limiter
Before=searxng.service

[Container]
Image=${VALKEY_IMAGE}
ContainerName=valkey
AutoUpdate=registry
Network=${SEARXNG_NETWORK}.network
Volume=valkey-data:/data:Z
Exec=valkey-server --save 30 1 --loglevel warning
HealthCmd=valkey-cli ping || exit 1
HealthInterval=30s
HealthRetries=3
HealthTimeout=5s

[Service]
Restart=on-failure
TimeoutStopSec=30

[Install]
WantedBy=default.target
EOF

        # Valkey named volume
        cat > "${QUADLET_DIR}/valkey-data.volume" <<EOF
[Volume]
VolumeName=valkey-data
EOF
    fi

    # ── Gluetun / VPN Quadlet ──
    if [ "$ENABLE_VPN" = "true" ]; then
        cat > "${QUADLET_DIR}/gluetun.container" <<EOF
[Unit]
Description=Gluetun VPN Sidecar
Before=searxng.service

[Container]
Image=${GLUETUN_IMAGE}
ContainerName=gluetun
AutoUpdate=registry
Network=${SEARXNG_NETWORK}.network
AddCapability=NET_ADMIN
AddDevice=/dev/net/tun
SecurityLabelDisable=true
Environment=VPN_SERVICE_PROVIDER=${VPN_PROVIDER}
Environment=VPN_TYPE=${VPN_TYPE}
Environment=WIREGUARD_PRIVATE_KEY=${WIREGUARD_PRIVATE_KEY}
Environment=WIREGUARD_ADDRESSES=${WIREGUARD_ADDRESSES}
Environment=HTTPPROXY=on
HealthCmd=wget -qO- https://ifconfig.me/ip || exit 1
HealthInterval=30s
HealthRetries=3
HealthTimeout=10s

[Service]
Restart=on-failure
TimeoutStopSec=30

[Install]
WantedBy=default.target
EOF
    fi

    # ── SearXNG Quadlet ──
    local VOLUMES="-v ${SEARXNG_DIR}/settings/settings.yml:/etc/searxng/settings.yml:Z"
    if [ "$ENABLE_VALKEY" = "true" ] && [ -f "${SEARXNG_DIR}/settings/limiter.toml" ]; then
        VOLUMES="${VOLUMES} -v ${SEARXNG_DIR}/settings/limiter.toml:/etc/searxng/limiter.toml:Z"
    fi

    local AFTER_UNIT=""
    local REQUIRES_UNIT=""
    if [ "$ENABLE_VALKEY" = "true" ]; then
        AFTER_UNIT="valkey.service "
        REQUIRES_UNIT="valkey.service "
    fi
    if [ "$ENABLE_VPN" = "true" ]; then
        AFTER_UNIT="${AFTER_UNIT}gluetun.service"
        REQUIRES_UNIT="${REQUIRES_UNIT}gluetun.service"
    fi
    
    local AFTER_LINE=""
    local REQUIRES_LINE=""
    if [ -n "$AFTER_UNIT" ]; then
        AFTER_LINE="After=${AFTER_UNIT}"
        REQUIRES_LINE="Requires=${REQUIRES_UNIT}"
    fi

    cat > "${QUADLET_DIR}/searxng.container" <<EOF
[Unit]
Description=SearXNG — Privacy-respecting metasearch engine
${AFTER_LINE}
${REQUIRES_LINE}

[Container]
Image=${SEARXNG_IMAGE}
ContainerName=searxng
AutoUpdate=registry
Network=${SEARXNG_NETWORK}.network
PublishPort=${SEARXNG_PORT}:8080
${VOLUMES}
Environment=UWSGI_WORKERS=${UWSGI_WORKERS}
Environment=UWSGI_THREADS=${UWSGI_THREADS}
HealthCmd=wget -q --spider http://localhost:8080/ || exit 1
HealthInterval=30s
HealthRetries=5
HealthTimeout=10s
HealthStartPeriod=15s

[Service]
Restart=on-failure
TimeoutStopSec=60

[Install]
WantedBy=default.target
EOF

    # ── Caddy Quadlet ──
    if [ "$ENABLE_CADDY" = "true" ]; then
        log_info "Generating Caddyfile for auto-HTTPS..."
        local CADDYFILE="${SEARXNG_DIR}/settings/Caddyfile"
        cat > "$CADDYFILE" <<EOF
${CADDY_DOMAIN} {
    reverse_proxy searxng:8080
}
EOF
        chmod 600 "$CADDYFILE"

        cat > "${QUADLET_DIR}/caddy.container" <<EOF
[Unit]
Description=Caddy Reverse Proxy
After=searxng.service
Requires=searxng.service

[Container]
Image=${CADDY_IMAGE}
ContainerName=caddy
AutoUpdate=registry
Network=${SEARXNG_NETWORK}.network
PublishPort=80:80
PublishPort=443:443
PublishPort=443:443/udp
Volume=${SEARXNG_DIR}/settings/Caddyfile:/etc/caddy/Caddyfile:Z
Volume=caddy-data:/data:Z
Volume=caddy-config:/config:Z

[Service]
Restart=on-failure
TimeoutStopSec=30

[Install]
WantedBy=default.target
EOF

        # Caddy named volumes
        cat > "${QUADLET_DIR}/caddy-data.volume" <<EOF
[Volume]
VolumeName=caddy-data
EOF
        cat > "${QUADLET_DIR}/caddy-config.volume" <<EOF
[Volume]
VolumeName=caddy-config
EOF
    fi

    log_ok "Quadlet files written."
}

# ─── Fallback: Classic Systemd ──────────────────────────────────────────────
setup_classic_systemd() {
    local SVC_DIR="${HOME}/.config/systemd/user"
    mkdir -p "$SVC_DIR"

    log_warn "Writing classic systemd service units to ${SVC_DIR}..."

    # ── Valkey service ──
    if [ "$ENABLE_VALKEY" = "true" ]; then
        cat > "${SVC_DIR}/valkey.service" <<EOF
[Unit]
Description=Valkey Data Store
After=network-online.target
Wants=network-online.target

[Service]
Restart=on-failure
TimeoutStopSec=30
ExecStartPre=-/usr/bin/podman rm -f valkey
ExecStart=/usr/bin/podman run --name valkey --rm \\
    --network ${SEARXNG_NETWORK} \\
    --health-cmd "valkey-cli ping || exit 1" \\
    --health-interval 30s \\
    -v valkey-data:/data:Z \\
    ${VALKEY_IMAGE} \\
    valkey-server --save 30 1 --loglevel warning
ExecStop=/usr/bin/podman stop -t 10 valkey

[Install]
WantedBy=default.target
EOF
    fi

    # ── Gluetun / VPN service ──
    if [ "$ENABLE_VPN" = "true" ]; then
        cat > "${SVC_DIR}/gluetun.service" <<EOF
[Unit]
Description=Gluetun VPN Sidecar
After=network-online.target
Wants=network-online.target

[Service]
Restart=on-failure
TimeoutStopSec=30
ExecStartPre=-/usr/bin/podman rm -f gluetun
ExecStart=/usr/bin/podman run --name gluetun --rm \\
    --network ${SEARXNG_NETWORK} \\
    --cap-add=NET_ADMIN \\
    --device=/dev/net/tun \\
    --security-opt label=disable \\
    -e VPN_SERVICE_PROVIDER=${VPN_PROVIDER} \\
    -e VPN_TYPE=${VPN_TYPE} \\
    -e WIREGUARD_PRIVATE_KEY=${WIREGUARD_PRIVATE_KEY} \\
    -e WIREGUARD_ADDRESSES=${WIREGUARD_ADDRESSES} \\
    -e HTTPPROXY=on \\
    --health-cmd "wget -qO- https://ifconfig.me/ip || exit 1" \\
    --health-interval 30s \\
    ${GLUETUN_IMAGE}
ExecStop=/usr/bin/podman stop -t 10 gluetun

[Install]
WantedBy=default.target
EOF
    fi

    # ── SearXNG service ──
    local EXTRA_VOLUMES=""
    if [ "$ENABLE_VALKEY" = "true" ] && [ -f "${SEARXNG_DIR}/settings/limiter.toml" ]; then
        EXTRA_VOLUMES="-v ${SEARXNG_DIR}/settings/limiter.toml:/etc/searxng/limiter.toml:Z"
    fi

    local AFTER_LINE="After=network-online.target"
    local REQUIRES_LINE=""
    if [ "$ENABLE_VALKEY" = "true" ]; then
        AFTER_LINE="${AFTER_LINE} valkey.service"
        REQUIRES_LINE="${REQUIRES_LINE} valkey.service"
    fi
    if [ "$ENABLE_VPN" = "true" ]; then
        AFTER_LINE="${AFTER_LINE} gluetun.service"
        REQUIRES_LINE="${REQUIRES_LINE} gluetun.service"
    fi

    cat > "${SVC_DIR}/searxng.service" <<EOF
[Unit]
Description=SearXNG Podman Container
${AFTER_LINE}
${REQUIRES_LINE}
Wants=network-online.target

[Service]
Restart=on-failure
TimeoutStopSec=60
ExecStartPre=-/usr/bin/podman rm -f searxng
ExecStart=/usr/bin/podman run --name searxng --rm \\
    --network ${SEARXNG_NETWORK} \\
    -p ${SEARXNG_PORT}:8080 \\
    -e UWSGI_WORKERS=${UWSGI_WORKERS} \\
    -e UWSGI_THREADS=${UWSGI_THREADS} \\
    --health-cmd "wget -q --spider http://localhost:8080/ || exit 1" \\
    --health-interval 30s \\
    --health-start-period 15s \\
    -v ${SEARXNG_DIR}/settings/settings.yml:/etc/searxng/settings.yml:Z \\
    ${EXTRA_VOLUMES} \\
    ${SEARXNG_IMAGE}
ExecStop=/usr/bin/podman stop -t 10 searxng

[Install]
WantedBy=default.target
EOF

    # ── Caddy service ──
    if [ "$ENABLE_CADDY" = "true" ]; then
        log_info "Generating Caddyfile for auto-HTTPS..."
        local CADDYFILE="${SEARXNG_DIR}/settings/Caddyfile"
        cat > "$CADDYFILE" <<EOF
${CADDY_DOMAIN} {
    reverse_proxy searxng:8080
}
EOF
        chmod 600 "$CADDYFILE"

        cat > "${SVC_DIR}/caddy.service" <<EOF
[Unit]
Description=Caddy Reverse Proxy
After=network-online.target searxng.service
Requires=searxng.service

[Service]
Restart=on-failure
TimeoutStopSec=30
ExecStartPre=-/usr/bin/podman rm -f caddy
ExecStart=/usr/bin/podman run --name caddy --rm \\
    --network ${SEARXNG_NETWORK} \\
    -p 80:80 -p 443:443 -p 443:443/udp \\
    -v ${SEARXNG_DIR}/settings/Caddyfile:/etc/caddy/Caddyfile:Z \\
    -v caddy-data:/data:Z \\
    -v caddy-config:/config:Z \\
    ${CADDY_IMAGE}
ExecStop=/usr/bin/podman stop -t 10 caddy

[Install]
WantedBy=default.target
EOF
    fi

    log_ok "Classic systemd units written."
}

# ─── Start Services ─────────────────────────────────────────────────────────
start_services() {
    log_info "Reloading systemd user daemon..."
    systemctl --user daemon-reload
    
    # Wait for the systemd generator to process new Quadlet files.
    # On slower VMs, a single daemon-reload doesn't block until units are visible.
    local retries=10
    while ! systemctl --user list-unit-files | grep -q searxng.service; do
        if [ "$retries" -le 0 ]; then
            log_warn "Quadlet generation timeout. Proceeding and hoping for the best..."
            break
        fi
        sleep 1
        retries=$((retries - 1))
    done

    # Final reload to ensure systemd sees the newly minted service links
    systemctl --user daemon-reload

    # Check if Quadlet generated the services
    local use_quadlet=false
    if systemctl --user cat searxng.service &>/dev/null 2>&1; then
        use_quadlet=true
    fi

    if [ "$ENABLE_VALKEY" = "true" ]; then
        log_info "Starting Valkey..."
        systemctl --user start valkey.service || log_warn "Valkey service start failed — check: systemctl --user status valkey"
        sleep 2
    fi

    if [ "$ENABLE_VPN" = "true" ]; then
        log_info "Starting Gluetun VPN Sidecar..."
        systemctl --user start gluetun.service || log_warn "Gluetun service start failed — check: systemctl --user status gluetun"
        sleep 2
    fi

    log_info "Starting SearXNG..."
    systemctl --user start searxng.service || log_warn "SearXNG service start failed — check: systemctl --user status searxng"

    if [ "$ENABLE_CADDY" = "true" ]; then
        log_info "Starting Caddy..."
        systemctl --user start caddy.service || log_warn "Caddy service start failed — check: systemctl --user status caddy"
    fi

    # loginctl linger so services survive logout
    if ! loginctl show-user "${USER}" --property=Linger 2>/dev/null | grep -q "yes"; then
        log_info "Enabling systemd linger for user ${USER} (auto-start on boot)..."
        sudo loginctl enable-linger "${USER}" || log_warn "Could not enable linger. Services may not survive logout."
    fi
}

# ─── Auto-Update Timer ──────────────────────────────────────────────────────
setup_auto_update() {
    if [ "$ENABLE_AUTO_UPDATE" != "true" ]; then return; fi

    log_info "Enabling podman-auto-update timer (daily image checks)..."
    systemctl --user enable --now podman-auto-update.timer 2>/dev/null \
        || log_warn "podman-auto-update.timer not available. Install podman >= 4.0 or enable manually."
}

# ─── Health Verification ────────────────────────────────────────────────────
verify() {
    log_info "Waiting for SearXNG to become healthy..."
    local retries=20
    local delay=3
    for ((i=1; i<=retries; i++)); do
        if curl -sf -o /dev/null "http://127.0.0.1:${SEARXNG_PORT}/"; then
            log_ok "SearXNG is responding on port ${SEARXNG_PORT}!"
            return 0
        fi
        sleep "$delay"
        echo -ne "  attempt ${i}/${retries}...\r"
    done
    log_warn "SearXNG did not respond within $((retries * delay))s. Check logs:"
    echo "    podman logs searxng"
    echo "    systemctl --user status searxng"
}

# ─── Summary ────────────────────────────────────────────────────────────────
print_summary() {
    local IP_ADDR
    IP_ADDR="$(hostname -I 2>/dev/null | awk '{print $1}')" || IP_ADDR="$(hostname)"

    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║              SearXNG Installation Complete                   ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Access URL:${NC}        http://${IP_ADDR}:${SEARXNG_PORT}/"
    echo -e "  ${BOLD}Config dir:${NC}        ${SEARXNG_DIR}/settings/"
    echo -e "  ${BOLD}Settings file:${NC}     ${SEARXNG_DIR}/settings/settings.yml"
    if [ "$ENABLE_VALKEY" = "true" ]; then
        echo -e "  ${BOLD}Rate limiter:${NC}      ✔ Valkey enabled (anti-bot protection)"
    fi
    if [ "$ENABLE_VPN" = "true" ]; then
        echo -e "  ${BOLD}Anonymity:${NC}           ✔ Gluetun VPN Sidecar enabled (${VPN_TYPE} / ${VPN_PROVIDER})"
    fi
    if [ "$ENABLE_JSON_API" = "true" ]; then
        echo -e "  ${BOLD}API Format:${NC}        ✔ JSON API enabled for LLM integration"
    fi
    if [ "$ENABLE_CADDY" = "true" ]; then
        echo -e "  ${BOLD}Reverse Proxy:${NC}     ✔ Caddy enabled routing ${CADDY_DOMAIN} -> HTTPS"
    fi
    if [ "$ENABLE_AUTO_UPDATE" = "true" ]; then
        echo -e "  ${BOLD}Auto-update:${NC}       ✔ Daily image update checks"
    fi
    echo ""
    echo -e "  ${BOLD}Useful commands:${NC}"
    echo -e "    ${CYAN}podman logs -f searxng${NC}                  # Live logs"
    echo -e "    ${CYAN}systemctl --user status searxng${NC}         # Service status"
    echo -e "    ${CYAN}systemctl --user restart searxng${NC}        # Restart"
    echo -e "    ${CYAN}podman auto-update --dry-run${NC}            # Check for updates"
    echo -e "    ${CYAN}podman healthcheck run searxng${NC}          # Run health check"
    if [ "$ENABLE_VALKEY" = "true" ]; then
        echo -e "    ${CYAN}systemctl --user status valkey${NC}          # Valkey status"
    fi
    if [ "$ENABLE_CADDY" = "true" ]; then
        echo -e "    ${CYAN}systemctl --user status caddy${NC}           # Caddy Reverse Proxy status"
        echo -e "    ${CYAN}podman logs -f caddy${NC}                    # Caddy logs (SSL cert issues)"
    fi
    if [ "$ENABLE_VPN" = "true" ]; then
        echo -e "    ${CYAN}systemctl --user status gluetun${NC}         # VPN Sidecar status"
        echo -e "    ${CYAN}podman logs -f gluetun${NC}                  # VPN wireguard connection logs"
    fi
    echo ""
    echo -e "  ${BOLD}To uninstall:${NC}"
    echo -e "    systemctl --user disable --now searxng valkey caddy gluetun 2>/dev/null"
    echo -e "    podman rm -f searxng valkey caddy gluetun 2>/dev/null"
    echo -e "    rm -rf ${SEARXNG_DIR}"
    echo ""
}

# ════════════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════════════
main() {
    banner
    preflight
    setup_network
    pull_images
    generate_config
    cleanup_existing

    # Prefer Quadlet (Podman ≥ 4.4) but fall back to classic units
    local podman_major
    podman_major="$(podman --version | awk '{print $3}' | cut -d. -f1)"
    local podman_minor
    podman_minor="$(podman --version | awk '{print $3}' | cut -d. -f2)"

    if [ "$podman_major" -ge 5 ] || { [ "$podman_major" -ge 4 ] && [ "$podman_minor" -ge 4 ]; }; then
        setup_quadlet
    else
        log_warn "Podman ${podman_major}.${podman_minor} detected — Quadlet requires ≥ 4.4. Using classic systemd units."
        setup_classic_systemd
    fi

    start_services
    setup_auto_update
    verify
    print_summary
}

main "$@"
