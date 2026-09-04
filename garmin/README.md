# Tedee Lock — Garmin fēnix 7X

Connect IQ watch app for a Tedee lock through the user's Python relay.

## Controls

- SELECT: refresh lock status
- NEXT: unlock, with confirmation
- PREV: lock

The app displays connection state, Tedee lock state and battery level.

## Architecture

fēnix 7X → Garmin Connect Mobile/Wi-Fi → HTTPS relay → Tedee Bridge → Tedee lock

Garmin's `Communications.makeWebRequest()` is used for asynchronous JSON REST requests. The app therefore needs the `Communications` permission.

## Configure

Edit `source/TedeeConfig.mc`:

```text
const BASE_URL = "https://YOUR-RELAY-DOMAIN.example";
const WATCH_TOKEN = "YOUR_LONG_RANDOM_WATCH_TOKEN";
```

Do not put the Tedee Bridge API token in this application.

## Build

Install Garmin Connect IQ SDK 9.x and open the `garmin` directory as the Connect IQ project. Build for `fenix7x`.

The generated `.prg` can be installed to the watch using Garmin's Connect IQ development workflow.

## Relay API expected by the app

GET `/api/status`

POST `/api/lock`

POST `/api/unlock`

Header:

`X-Tedee-Watch-Token: ...`

The relay should be HTTPS when used outside the trusted LAN.
