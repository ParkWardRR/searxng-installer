<div align="center">

# 🕵️ SearXNG Quadlet Installer

[![Podman](https://img.shields.io/badge/Podman-Rootless-892CA0?style=for-the-badge&logo=podman&logoColor=white)](#)
[![Systemd](https://img.shields.io/badge/Systemd-Quadlet-4CAF50?style=for-the-badge&logo=linux&logoColor=white)](#)
[![WireGuard](https://img.shields.io/badge/WireGuard-VPN_Encrypted-881798?style=for-the-badge&logo=wireguard&logoColor=white)](#)
[![Bash Built](https://img.shields.io/badge/Built_With-Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](#)

*An advanced, 100% rootless, containerized deployment script for SearXNG.*

</div>

## What is this? (Explained for the 15-year old IT Pro)

Alright, check it out. When you run a search engine yourself to avoid Google harvesting your data, you run into two massive problems: 
1. **Security:** You do not want containers running as `root` bridging into your network. It's a massive attack vector.
2. **IP Blocks:** If you ping Google, Bing, and Yahoo via API concurrently, they will instantly recognize you are scraping them from a datacenter IP, hit you with endless Cloudflare Captchas, and perma-ban your VPS.

**This script solves both.**

It deploys **SearXNG** automatically using **Podman Quadlets**. Quadlets are the absolute bleeding edge of container tech—they completely replace bloated `docker-compose.yml` files by letting the native Linux `systemd` supervisor manage the containers directly in the kernel! Better yet? It runs entirely **rootless** in user space. There is no root daemon, zero root privileges, and zero chance a container exploit owns your hypervisor.

Beyond the security architecture, this script injects two incredibly powerful sidecars to SearXNG automatically:

*   **Valkey (Rate Limiting):** A modern fork of Redis acting as a high-speed memory cache. It sits in front of your SearXNG instance as a bouncer, actively rate-limiting web scrapers so they can't DDoS your search endpoint.
*   **Gluetun (VPN Proxy):** This is the magic. It spins up a WireGuard tunnel inside a detached container network, and dynamically modifies SearXNG's `settings.yml` to force *all* outgoing queries through the VPN tunnel (like Mullvad). This completely masks your server's IP address, bypassing upstream CAPTCHA blocks instantly.

You get an enterprise-grade, encrypted, untrackable search cluster in executing a single `.sh` file.

---

## 🚀 Key Features

*   **Rootless Podman:** Container runtime executes safely in userspace; ZERO root privileges are required to run the search engine.
*   **systemd Quadlet:** Next-gen `.container` configuration handling. It guarantees your containers boot gracefully with your machine.
*   **Valkey Limiter:** Instant IP-based bot protection and traffic rate limiting.
*   **VPN Sidecar (Gluetun):** Automatically anonymizes outbound traffic so providers like Google don't restrict your network.
*   **Auto-HTTPS (Caddy):** Optional deployment of the Caddy Reverse Proxy sidecar—giving you an instant "valid" SSL wrapper using Let's Encrypt.
*   **AI Integrated (JSON API):** Toggleable configuration out-of-the-box that formats SearXNG responses via pure JSON, making it an incredible tool for Large Language Models (LLMs) and agents like Open-WebUI.

## ⚙️ Configuration & Parameters

Open `install_searxng.sh` with any text editor (like `nano` or Sublime Text) and adjust the tunables at the very top. The script is highly flexible.

### Core Architecture Overrides
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `SEARXNG_PORT` | `8888` | The host port to expose the SearXNG Web UI on. |
| `SEARXNG_DIR` | `~/searxng` | The directory where settings and config files will be persisted. |
| `UWSGI_WORKERS` | `4` | Number of UWSGI workers for SearXNG concurrency. |
| `UWSGI_THREADS` | `4` | Number of UWSGI threads for SearXNG concurrency. |
| `ENABLE_AUTO_UPDATE` | `true` | Enables systemd timer to pull latest container images nightly. |

### Images
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `SEARXNG_IMAGE` | `docker.io/searxng/searxng:latest` | Target container image for SearXNG. |
| `VALKEY_IMAGE` | `docker.io/valkey/valkey:8-alpine` | Target container image for the Rate Limiter. |
| `CADDY_IMAGE` | `docker.io/caddy/caddy:latest` | Target container image for Caddy Reverse Proxy. |
| `GLUETUN_IMAGE` | `docker.io/qmcgaw/gluetun:latest` | Target container image for the VPN sidecar. |

### API & Bot Protection
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `ENABLE_VALKEY` | `true` | Set to false to bypass Valkey IP-based rate limiter (not recommended). |
| `ENABLE_JSON_API` | `true` | Allows output format to be JSON (e.g. bypassing HTML for agent/LLM usage). |

### VPN Sidecar (Gluetun Proxy)
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `ENABLE_VPN` | `false` | True will route all upstream search requests anonymously over VPN. |
| `VPN_PROVIDER` | `mullvad` | Configures the VPN daemon provider APIs. |
| `VPN_TYPE` | `wireguard` | Uses wireguard kernel module (`openvpn` also supported). |
| `WIREGUARD_PRIVATE_KEY` | `YOUR_KEY` | Cryptographically paired private key directly from your provider. |
| `WIREGUARD_ADDRESSES` | `10.x.x.x/32` | The internal IP Address that bonds to your specific Private Key. |

## 💻 Usage & Installation

You don't need `sudo` for this part. Run it directly as the user who will be hosting the network services!

```bash
# Provide execution privileges to the script
chmod +x ./install_searxng.sh

# Run the installer
./install_searxng.sh
```

**Uninstall Completely:**
*Messed up? Want to start fresh? Wipe the deployment instantly.*
```bash
systemctl --user disable --now searxng valkey caddy gluetun 
podman rm -f searxng valkey caddy gluetun
rm -rf ~/searxng
```

## OS Compatibility Support
Tested on: **AlmaLinux 10.1 (Heliotrope Lion)**
Packager Managers Supported: `dnf`, `apt`, `pacman` (RHEL, Debian, Ubuntu, Fedora, Arch Linux).
> *Note: If you run an older OS with Podman versions earlier than 4.4, the script automatically dynamically falls back to generating Classic SystemD units to preserve compatibility!*

---
