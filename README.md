# Jlee-Aitaxi

A simple Taxi job resource for QBCore-based FiveM servers.

## Overview
- **Resource:** `Jlee-Aitaxi`
- **Purpose:** Provides a basic taxi service allowing players to request and accept taxi rides with server-side payment handling and a lightweight HTML UI.
- **Framework:** `qb-core` (required)

## Files
- `fxmanifest.lua` — Resource manifest and dependencies.
- `config.lua` — Configurable settings (fares, job names, etc.).
- `server/server.lua` — Server-side logic, validation, and QBCore integration.
- `client/client.lua` — Client-side interactions, markers, and event triggers.
- `html/index.html`, `html/script.js` — Lightweight in-game web UI.

## Features
- QBCore integration via `exports['qb-core']:GetCoreObject()`.
- Taxi request and accept flow between players.
- Server-side validation for player existence and money transactions.
- Config-driven settings for fares, cooldowns, and job restrictions.
- Simple HTML/JS browser UI for ride requests/dispatch.
- Event-driven architecture using `RegisterNetEvent`.

## Installation
1. Place the `Jlee-Aitaxi` folder into your server `resources` directory.
2. Ensure `qb-core` is installed and running on your server.
3. Add to `server.cfg`: `ensure Jlee-Aitaxi`.

## Configuration
- Edit `config.lua` to adjust fares, cooldowns, job restrictions, and UI options.
- Back up `config.lua` before making production changes.


## Support
https://discord.gg/tEGXGzpVRv

