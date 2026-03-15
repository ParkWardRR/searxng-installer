<div align="center">

# 🕵️ SearXNG Quadlet Installer

[![License: Blue Oak 1.0.0](https://img.shields.io/badge/License-Blue_Oak_1.0.0-blue.svg)](https://blueoakcouncil.org/license/1.0.0)
[![Status: Production](https://img.shields.io/badge/Status-Production_Ready-success)](#)
[![Security: Rootless](https://img.shields.io/badge/Security-100%25_Rootless-critical)](#)

### Architecture
[![Podman](https://img.shields.io/badge/Podman-892CA0?style=for-the-badge&logo=podman&logoColor=white)](#)
[![Systemd](https://img.shields.io/badge/Systemd_Quadlet-4CAF50?style=for-the-badge&logo=linux&logoColor=white)](#)
[![WireGuard](https://img.shields.io/badge/WireGuard_VPN-881798?style=for-the-badge&logo=wireguard&logoColor=white)](#)
[![Bash Built](https://img.shields.io/badge/Bash_Script-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)](#)
[![Redis/Valkey](https://img.shields.io/badge/Valkey_Limiter-DC382D?style=for-the-badge&logo=redis&logoColor=white)](#)

### Officially Supported OS
[![AlmaLinux](https://img.shields.io/badge/AlmaLinux-100000?style=for-the-badge&logo=almalinux&logoColor=white)](#)
[![RHEL](https://img.shields.io/badge/RHEL-CC0000?style=for-the-badge&logo=redhat&logoColor=white)](#)
[![Fedora](https://img.shields.io/badge/Fedora-51A2DA?style=for-the-badge&logo=fedora&logoColor=white)](#)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](#)
[![Debian](https://img.shields.io/badge/Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)](#)
[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=arch-linux&logoColor=white)](#)

*An advanced, 100% rootless, containerized deployment script for SearXNG.*

</div>

## What is this?

### The Basics
So, you want to stop Google from tracking everything you search for? Setting up your own search engine (SearXNG) is awesome, but it comes with two massive headaches:
1. **You'll get banned by Google.** If you just spin up a cloud server and start scraping results, Google and Bing see 1,000 searches coming from a single datacenter IP, hit you with endless Cloudflare CAPTCHAs, and eventually block your server's IP entirely.
2. **Hackers.** If someone hacks your search engine container, you don't want them getting `root` access to your entire server.

**This script fixes both automatically.** It runs your search engine inside **Podman** (like Docker, but secure because it doesn't need root admin rights). More importantly, it attaches a **Mullvad VPN Sidecar** to your search engine. Every time your server asks Google for a search result, it routes that request through a VPN tunnel first. Google thinks you're just some random person on a Mullvad exit node, never sees your server's real IP, and leaves you alone. Finally, it slaps a **Valkey bouncer** on the front door to block other people's bots from spamming your new search engine. ONE command, and you get all of this.

---

### For the IT Pro
This is a fully automated, idempotent bash deployment script for SearXNG that utilizes modern **systemd Quadlets** and **Rootless Podman** on RHEL/Debian/Arch based systems. 

Bloated `docker-compose.yml` stacks running under a high-privilege docker daemon are an unnecessary attack vector. This script replaces that paradigm. It natively instructs systemd (via `.container` Quadlet files) to manage the lifecycle of a rootless Podman overlay network in userspace. 

To solve upstream scraping bans (Google/Bing IP blocking), the script provisions an encrypted **WireGuard VPN sidecar (`gluetun`)** attached to the same network overlay. The script securely dynamically injects proxy routing rules directly into SearXNG's `settings.yml` to force all egress HTTP scraper traffic through the VPN `tun` device, effectively masking your bare-metal hypervisor's public IP. Incoming ingress is protected by **Valkey**, which operates as a high-speed memory cache and token-bucket rate limiter to mitigate layer 7 DDoS floods.

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
**Primary Focus:** Built and thoroughly tested for **AlmaLinux 10.1 (Heliotrope Lion)**.
*Other Supported Distributions:* By detecting the host package manager, `dnf`, `apt`, and `pacman` environments (RHEL, Fedora, Debian, Ubuntu, Arch Linux) should also deploy successfully.
> *Note: If you run an older OS with Podman versions earlier than 4.4, the script automatically dynamically falls back to generating Classic SystemD units to preserve compatibility!*

---
