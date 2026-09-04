# garmin_tedee
fenix7x and marq2



Tedee Lock Control from Garmin via ASUS Router (TESTED)

This guide documents the complete working setup for controlling a Tedee smart lock from a Garmin Connect IQ watch app using:

Garmin fēnix 7X / MARQ Gen 2

Garmin Connect IQ

ASUS GT-AX11000 Pro

Asuswrt-Merlin

Entware

Python relay service

nginx HTTPS reverse proxy

Tedee Bridge local API

The final architecture is:

Garmin Watch
    |
    | HTTPS
    v
https://your.domain.home:9443
    |
    v
nginx on ASUS router
    |
    | HTTP localhost
    v
127.0.0.1:PORT
    |
    v
Python Tedee relay
    |
    | HTTP + api_token
    v
Tedee Bridge IP
X.X.X.X:80
    |
    v
Tedee Smart Lock

1. Working environment

Router:

Model: ASUS GT-AX11000 Pro
Firmware: Asuswrt-Merlin
LAN IP: x.x.x.x
Architecture: aarch64

Entware:

/tmp/mnt/entwere/entware

Python:

/opt/bin/python3

Tedee Bridge:

IP: x.x.x.x
Port: 80

Tedee lock:

Lock ID: xxxxxx

Public hostname and HTTPS port:

your.domain.home:9443

Internal Python relay port:

8090

2. Tedee Bridge API

The local Tedee Bridge API is used.

GET  /v1.0/lock/{deviceId}
POST /v1.0/lock/{deviceId}/lock
POST /v1.0/lock/{deviceId}/unlock
POST /v1.0/lock/{deviceId}/pull

Authentication header:

api_token: YOUR_TEDEE_BRIDGE_TOKEN

The Bridge is configured for plain-token authentication. A successful Tedee action normally returns HTTP 204 No Content. The Python relay converts this to JSON HTTP 200, because Garmin expects JSON when HTTP_RESPONSE_CONTENT_TYPE_JSON is used.

Official documentation:

https://docs.tedee.com/bridge-api

3. Prepare Entware and Python

Check Python:

/opt/bin/python3 --version

Create the application directory:

mkdir -p /tmp/mnt/entwere/entware/tedee

4. Create the relay environment file

Create:

/tmp/mnt/entwere/entware/tedee/.env

Example:

TEDEE_BRIDGE_IP=x.x.x.x
TEDEE_BRIDGE_PORT=80
TEDEE_LOCK_ID=xxxxxx
TEDEE_BRIDGE_TOKEN=YOUR_PRIVATE_TEDEE_BRIDGE_TOKEN
WATCH_TOKEN=YOUR_PRIVATE_GARMIN_RELAY_TOKEN
PORT=xxxx

Protect it:

chmod 600 /tmp/mnt/entwere/entware/tedee/.env

Generate a strong watch token if needed:

/opt/bin/python3 -c 'import secrets; print(secrets.token_urlsafe(32))'

Do not publish either token.

5. Python relay

Create:

/tmp/mnt/entwere/entware/tedee/server.py

The final relay should provide:

GET  /health
GET  /api/status
POST /api/lock
POST /api/unlock

/api/status, /api/lock, and /api/unlock require:

X-Tedee-Watch-Token: YOUR_WATCH_TOKEN

Important handler settings:

server_version = "TedeeGarmin/1.4"
protocol_version = "HTTP/1.1"

At the beginning of do_POST() consume any request body before authentication or routing:

try:
    length = int(self.headers.get("Content-Length") or 0)
except (TypeError, ValueError):
    length = 0

if length > 0:
    self.rfile.read(length)

Every JSON response should include an accurate Content-Length.

Tedee action success should be normalized:

if status_code in (200, 204):
    self.send_json(
        200,
        {
            "ok": True,
            "action": action
        }
    )

6. Idempotent action handling

The relay checks the current Tedee state before acting.

Useful Tedee states:

0   uncalibrated
1   calibration
2   open
3   partially_open
4   opening
5   closing
6   closed
7   pull_spring
8   pulling
9   unknown
255 unpulling

If a LOCK request arrives while state is already 6, return:

{"ok":true,"action":"lock","note":"already_locked","state":6}

If an UNLOCK request arrives while state is already 2, return:

{"ok":true,"action":"unlock","note":"already_unlocked","state":2}

This makes retries safe and prevents a redundant request from appearing as a failure.

The relay currently uses:

ACTION_COOLDOWN = 1.0

Rapid repeat commands may return HTTP 429 with note: cooldown.

7. Relay service

Create the Entware init script:

/opt/etc/init.d/S99tedeeproxy

It should launch:

/opt/bin/python3 /tmp/mnt/entwere/entware/tedee/server.py

Useful commands:

/opt/etc/init.d/S99tedeeproxy start
/opt/etc/init.d/S99tedeeproxy stop
/opt/etc/init.d/S99tedeeproxy restart
/opt/etc/init.d/S99tedeeproxy status

Relay log:

tail -f /opt/var/log/tedeeproxy.log

8. Start Entware and relay automatically

Create or edit:

/jffs/scripts/services-start

Use:

#!/bin/sh
/opt/etc/init.d/rc.unslung start

# Start Entware Tedee relay.
/opt/etc/init.d/S99tedeeproxy start

Make executable:

chmod +x /jffs/scripts/services-start

Do not add duplicate Tedee startup lines.

9. Test the relay locally

Health:

curl -i http://127.0.0.1:PORT/health

Status:

curl -i \
  -H "X-Tedee-Watch-Token: YOUR_WATCH_TOKEN" \
  http://127.0.0.1:PORT/api/status

Lock:

curl -i \
  -X POST \
  -H "X-Tedee-Watch-Token: YOUR_WATCH_TOKEN" \
  http://127.0.0.1:PORT/api/lock

Unlock:

curl -i \
  -X POST \
  -H "X-Tedee-Watch-Token: YOUR_WATCH_TOKEN" \
  http://127.0.0.1:PORT/api/unlock

10. nginx HTTPS reverse proxy

Check nginx:

/opt/sbin/nginx -V

The working configuration uses:

user nobody nobody;

because nogroup is not available on this router.

The ASUS Let's Encrypt certificate is for:

homeie.hopto.org

Certificate files:

/jffs/.le/homeie.hopto.org_ecc/domain.key
/jffs/.le/homeie.hopto.org_ecc/fullchain.pem
/jffs/.le/homeie.hopto.org_ecc/homeie.hopto.org.key

Use the hostname covered by the certificate:

https://your.domain.home:PORT

Do not use the router IP as the public Garmin URL if the certificate is only issued for the hostname.

Conceptual nginx server block:

server {
    listen PORT ssl;
    server_name your.domain.home;

    ssl_certificate /jffs/.le/your.domain.home_ecc/fullchain.pem;
    ssl_certificate_key /jffs/.le/your.domain.homeecc/domain.key;

    location / {
        proxy_pass http://127.0.0.1:PORT;
        proxy_http_version 1.1;
        proxy_pass_request_headers on;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

Validate and restart:

/opt/sbin/nginx -t
/opt/etc/init.d/S80nginx restart

Check port PORT:

netstat -lntp | grep PORT

11. Test HTTPS from Windows

Health:

curl.exe -i https://your.domain.home:PORT/health

Status:

curl.exe -i `
  -H "X-Tedee-Watch-Token: YOUR_WATCH_TOKEN" `
  https://your.domain.home:PORT/api/status

Expected:

HTTP/1.1 200 OK
Content-Type: application/json

12. Garmin Connect IQ project

Example location:

C:\tedee\garmin

Project layout:

C:\tedee\garmin\
├── manifest.xml
├── monkey.jungle
├── source\
│   ├── TedeeApp.mc
│   ├── TedeeConfig.mc
│   ├── TedeeDelegate.mc
│   ├── TedeeSyncDelegate.mc
│   └── TedeeView.mc
├── resources\
│   ├── strings\strings.xml
│   └── drawables\launcher_icon.xml
├── resources-fenix7x\
│   └── drawables\
│       ├── launcher_icon.xml
│       └── launcher_icon_40x40.png
└── resources-marq2\
    └── drawables\
        ├── launcher_icon.xml
        └── launcher_icon_60x60.png

13. Garmin manifest

Use Garmin device IDs:

fenix7x
marq2

MARQ Gen 2 Adventurer uses marq2, not marq2adventurer.

Example manifest:

<?xml version="1.0"?>
<iq:manifest version="3" xmlns:iq="http://www.garmin.com/xml/connectiq">
  <iq:application
      id="7f3a9c2e4b1d6a809e5c72f314ab6802"
      type="watch-app"
      name="@Strings.AppName"
      entry="TedeeApp"
      launcherIcon="@Drawables.LauncherIcon">
    <iq:products>
      <iq:product id="fenix7x"/>
      <iq:product id="marq2"/>
    </iq:products>
    <iq:permissions>
      <iq:uses-permission id="Communications"/>
    </iq:permissions>
    <iq:languages>
      <iq:language>eng</iq:language>
    </iq:languages>
  </iq:application>
</iq:manifest>

14. Garmin strings and launcher icons

resources\strings\strings.xml:

<?xml version="1.0" encoding="UTF-8"?>
<strings>
    <string id="AppName">Tedee Lock</string>
</strings>

fēnix 7X launcher icon:

40 x 40 PNG

MARQ Gen 2 launcher icon:

60 x 60 PNG

fēnix resource XML:

<?xml version="1.0"?>
<drawables>
    <bitmap id="LauncherIcon" filename="launcher_icon_40x40.png"/>
</drawables>

MARQ resource XML:

<?xml version="1.0"?>
<drawables>
    <bitmap id="LauncherIcon" filename="launcher_icon_60x60.png"/>
</drawables>

15. TedeeConfig.mc

Use:

module TedeeConfig {
    const BASE_URL = "https://your.domain.home:PORT";
    const WATCH_TOKEN = "YOUR_PRIVATE_WATCH_TOKEN";

    function stateName(state) {
        var names = {
            0 => "Uncalibrated",
            1 => "Calibration",
            2 => "Open",
            3 => "Partially open",
            4 => "Opening",
            5 => "Closing",
            6 => "Closed",
            7 => "Pull spring",
            8 => "Pulling",
            9 => "Unknown",
            255 => "Unpulling"
        };

        return names[state] != null ? names[state] : "State " + state;
    }
}

Keep the real token private.

16. Garmin controls

UP / PREV     -> select UNLOCK
DOWN / NEXT   -> select LOCK
SELECT        -> execute selected action

UNLOCK requires confirmation.

The app uses cached state to choose the sensible default:

state 6 -> UNLOCK
state 2 -> LOCK
state 3 -> LOCK

17. Garmin sync architecture

For phone-independent operation, perform the requests in Garmin sync mode:

User presses LOCK / UNLOCK
        |
        v
Store tedee_pending_action
        |
        v
Communications.startSync()
        |
        v
Garmin launches sync mode
        |
        v
getSyncDelegate()
        |
        v
TedeeSyncDelegate.onStartSync()
        |
        v
POST /api/lock or /api/unlock
        |
        v
GET /api/status
        |
        v
Store state and battery
        |
        v
notifySyncComplete()

18. Important Monkey C details

Correct makeWebRequest() callback type:

function onStatusResponse(
    responseCode as Lang.Number,
    data as
        Lang.Dictionary or
        Lang.String or
        PersistedContent.Iterator or
        Null
) as Void

Imports:

using Toybox.Lang;
using Toybox.PersistedContent;

For typed Wi-Fi callback dictionaries, use:

function onWifiChecked(
    result as {
        :wifiAvailable as Lang.Boolean,
        :errorCode as Communications.WifiConnectionStatus
    }
) as Void

Use .equals() for command strings:

_action.equals("lock")
_action.equals("unlock")

Use the sync delegate override without forcing a return type if the SDK rejects it:

function getSyncDelegate() {
    return new TedeeSyncDelegate();
}

Avoid double sync completion. In onStopSync():

_stopping = true;
Communications.cancelAllRequests();
Communications.notifySyncComplete(null);

Callbacks should begin with:

if (_stopping) {
    return;
}

19. Garmin action-result mapping

Relay response notes:

already_locked   -> ALREADY LOCKED
already_unlocked -> ALREADY UNLOCKED
cooldown         -> PLEASE WAIT

Normal action responses remain successful JSON responses.

20. Garmin error codes encountered

-104  BLE_CONNECTION_UNAVAILABLE

Observed when foreground transport could not use Bluetooth.

-1001 SECURE_CONNECTION_REQUIRED

Solved by HTTPS through nginx.

-1002 UNSUPPORTED_CONTENT_TYPE_IN_RESPONSE

Avoided by converting Tedee 204 No Content to relay JSON 200.

-300 NETWORK_REQUEST_TIMED_OUT

Observed during foreground request testing. Sync mode was used for reliable phone-independent operation.

21. Garmin Wi-Fi recommendations

Use a compatible 2.4 GHz SSID, for example:

SSID: Garmin24
Band: 2.4 GHz
Mode: b/g/n
Wi-Fi 6 / 802.11ax: OFF
Bandwidth: 20 MHz
Channel: 1-11
Security: WPA2-Personal
Encryption: AES
Hidden SSID: NO
Smart Connect: OFF for this SSID

22. Build the Garmin app

fēnix 7X:

cd C:\tedee\garmin

monkeyc -f monkey.jungle `
  -o bin\Tedee-fenix7.prg `
  -y C:\tedee\developer_key `
  -d fenix7x `
  -w

MARQ Gen 2:

cd C:\tedee\garmin

monkeyc -f monkey.jungle `
  -o bin\Tedee-marq2.prg `
  -y C:\tedee\developer_key `
  -d marq2 `
  -w

23. Monitor nginx and relay logs

nginx:

tail -f /opt/var/log/nginx/access.log

A watch request looks similar to:

192.168.1.59 ... "GET /api/status HTTP/1.1" 200 ... "Garmin fenix 7X/26.9"

For an action, expect:

POST /api/unlock

or:

POST /api/lock

followed by:

GET /api/status

Relay log:

tail -f /opt/var/log/tedeeproxy.log

24. End-to-end test

Open two SSH windows.

Window 1:

tail -f /opt/var/log/nginx/access.log

Window 2:

tail -f /opt/var/log/tedeeproxy.log

Then on Garmin:

Open Tedee Lock.

Confirm cached state appears.

Select UNLOCK.

Confirm the unlock prompt.

Let Garmin enter Wi-Fi sync.

Confirm the door physically unlocks.

Confirm nginx shows POST /api/unlock.

Confirm the relay contacts the Tedee Bridge.

Confirm the action is normalized to JSON HTTP 200.

Confirm Garmin sends GET /api/status.

Confirm the new lock state is cached.

Repeat with LOCK.

25. Expected final behaviour

Locked door:

State: CLOSED
Default action: UNLOCK

Unlock flow:

UNLOCK
-> confirmation
-> Garmin Wi-Fi sync
-> POST /api/unlock
-> Tedee 204
-> relay JSON 200
-> GET /api/status
-> cached state updated

Already locked:

LOCK
-> relay sees state 6
-> no redundant Tedee lock command required
-> HTTP 200
-> note=already_locked
-> watch displays ALREADY LOCKED

Already unlocked:

UNLOCK
-> relay sees state 2
-> HTTP 200
-> note=already_unlocked
-> watch displays ALREADY UNLOCKED

26. Tedee auto-lock

If Tedee has auto-lock enabled with a 300 second delay, the lock can secure itself five minutes after unlocking. A later manual LOCK command may therefore be redundant. The relay's idempotent state check makes that a successful no-op rather than an error.

27. Security recommendations

Keep these secret:

TEDEE_BRIDGE_TOKEN
WATCH_TOKEN

Recommended:

Do not commit .env.

Do not publish the real watch token.

Rotate tokens if exposed.

Keep the router firmware updated.

Keep the Let's Encrypt certificate renewed.

Limit nginx exposure to the required API paths where practical.

Do not expose the ASUS administration interface on the same public port used by the Tedee relay.

28. Useful service commands

Relay:

/opt/etc/init.d/S99tedeeproxy restart
/opt/etc/init.d/S99tedeeproxy status

nginx:

/opt/sbin/nginx -t
/opt/etc/init.d/S80nginx restart

Ports and processes:

netstat -lntp
ps | grep python
ps | grep nginx

29. Final working data flow

Garmin fēnix 7X
        |
        | Garmin Wi-Fi sync
        | HTTPS
        v
homeie.hopto.org:9443
        |
        v
nginx
        |
        | HTTP/1.1
        v
127.0.0.1:8090
        |
        v
Python Tedee relay
        |
        | api_token
        v
IP X.X.X.X:80
        |
        v
Tedee Bridge
        |
        v
Tedee Lock

30. Key lessons from the working implementation

The pieces that made the final setup reliable were:

HTTPS in front of the Python relay.

Correct Let's Encrypt hostname.

Garmin Communications permission.

Garmin sync mode for phone-independent Wi-Fi requests.

Correct typed Monkey C callbacks.

Persistent action state through Application.Storage.

.equals() string comparison.

A single effective notifySyncComplete() path.

Conversion of Tedee 204 action success into JSON 200.

Idempotent lock/unlock handling.

Accurate HTTP Content-Length.

HTTP/1.1 support in the Python handler.

Reading and discarding unused POST request bodies.

Cached lock state used to choose the sensible default action.

This configuration was tested successfully with a physical Garmin fēnix 7X, marq2 and a Tedee smart lock.
