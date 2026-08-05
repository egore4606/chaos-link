![Warning: the application, user interface, installer, and primary documentation are in Russian](docs/russian-language-warning.svg)

<p align="center"><strong>This English page is a project overview. Use the <a href="README.md">Russian README</a> for the current setup and operating instructions.</strong></p>

# Chaos Link

**Let your friends sabotage your CS2 session from their phones in real time.**

[![CI](https://github.com/egore4606/chaos-link/actions/workflows/ci.yml/badge.svg)](https://github.com/egore4606/chaos-link/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/egore4606/chaos-link)](https://github.com/egore4606/chaos-link/releases/latest)
[![Windows](https://img.shields.io/badge/host-Windows-0078D4?logo=windows)](README.md#требования)

Chaos Link turns an ordinary game with friends into a shared chaos challenge. Run it on the consenting player's Windows PC, send the room link to friends, and let them make the match harder from their phones: force a jump or reload, draw the knife, jerk the aim, block movement, flash the screen, or trigger a random screamer. Everyone sees the same cooldowns in real time.

> [!IMPORTANT]
> Chaos Link intentionally affects keyboard, mouse, screen, and audio input on the host PC. Install and run it only with the gaming-PC owner's informed permission. It has no autostart, hidden service, remote shell, DLL injection, or game-memory access.

![Chaos Link desktop and mobile control panel](docs/ui-concept.png)

## Main features

- Any number of browser controllers in one room
- Shared server-authoritative cooldowns
- Admin pause, per-effect cooldown settings, and temporary guest blocks
- Nine allow-listed AutoHotkey v2 effects
- User-managed random screamer images and sounds
- LAN access and an optional temporary Cloudflare Quick Tunnel
- One-file Windows installer with Start, Stop, and Uninstall shortcuts
- Emergency input release from the admin panel or `Ctrl+Shift+F12`

## Architecture

```mermaid
flowchart LR
    C1["Friend's browser"] -->|HTTPS / WebSocket| S["Chaos Link server"]
    C2["Admin browser"] -->|HTTPS / WebSocket| S
    S -->|Allow-listed command| A["Windows agent"]
    A -->|Effect ID + duration| H["AutoHotkey v2"]
    H --> G["CS2 / host desktop"]
    A -->|Execution result| S
    S -->|Shared state and cooldowns| C1
    S -->|Shared state and cooldowns| C2
```

The browser authenticates to the ASP.NET Core server. The server validates the room and role, serializes state changes, and forwards accepted effect IDs to the single gaming-PC agent. The browser never communicates with AutoHotkey directly.

## Quick start

1. Download `ChaosLink-Setup.exe` from the [latest release](https://github.com/egore4606/chaos-link/releases/latest).
2. Run it, review the displayed actions, type `INSTALL`, and approve the UAC prompt.
3. Send the public URL, room code, and **guest key** to your friends.
4. Keep the **admin key** private. Use the desktop shortcuts to stop or uninstall the session.

The installer and application prompts are in Russian. Detailed requirements, development commands, effect descriptions, security notes, and support instructions are maintained in the [primary Russian README](README.md).

> [!NOTE]
> The generated `https://*.trycloudflare.com` address changes after each restart. Cloudflare Quick Tunnels are intended for temporary sessions, not permanent production hosting.

No open-source license has been granted yet. Unless a license is added, the repository remains publicly viewable source with all rights reserved by its owner.
