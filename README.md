# garmin_tedee
fenix7x and marq2



Garmin Tedee Lock on ASUS GT-AX11000 Pro — Complete Router + Garmin README

This README documents the working setup for controlling a Tedee smart lock from a Garmin Connect IQ watch app through an ASUS GT-AX11000 Pro running Asuswrt-Merlin.

The working network path is:

Garmin Watch
    |
    | HTTPS
    v
https://your.home.domain:PORT
    |
    v
nginx on ASUS router
    |
    | HTTP
    v
127.0.0.1:PORT
    |
    v
Python Tedee relay
    |
    | Tedee Bridge local API
    v
IP X.X.X.X:80
    |
    v
Tedee Smart Lock

The router-side files involved are:

/tmp/mnt/entwere/entware/tedee/server.py
/tmp/mnt/entwere/entware/tedee/.env

/opt/etc/init.d/S99tedeeproxy
/opt/etc/init.d/S80nginx

/opt/etc/nginx/nginx.conf

/jffs/scripts/services-start

/jffs/.le/your.home.domain_ecc/fullchain.pem
/jffs/.le/your.home.domain_ecc/domain.key

Important:

server.py, .env, S99tedeeproxy, nginx.conf, and /jffs/scripts/services-start are the files you actively configure.

/opt/etc/init.d/S80nginx is normally installed and maintained by the Entware nginx package.

fullchain.pem and domain.key are generated and maintained by the router's Let's Encrypt/DDNS certificate system.

Do not paste the contents of domain.key into documentation or source control.

Keep all real API tokens private.

1. Router and Tedee Details

Router:

Model: ASUS GT-AX11000 Pro
LAN IP: X.X.X.X
Firmware: Asuswrt-Merlin
Architecture: aarch64

Entware:

/tmp/mnt/entwere/entware

Python:

/opt/bin/python3

Tedee Bridge:

IP: X.X.X.X
Port: 80

Tedee lock:

Lock ID: XXXXXX

Public hostname:

your.home.domain

nginx HTTPS port:

PORT

Python relay port:

PORT

2. Required Directory

Create the Tedee relay directory:

mkdir -p /tmp/mnt/entwere/entware/tedee

3. /tmp/mnt/entwere/entware/tedee/.env

Create:

/tmp/mnt/entwere/entware/tedee/.env

Use:

TEDEE_BRIDGE_IP=X.X.X.X
TEDEE_BRIDGE_PORT=80
TEDEE_LOCK_ID=XXXXXX
TEDEE_BRIDGE_TOKEN=YOUR_PRIVATE_TEDEE_BRIDGE_TOKEN
WATCH_TOKEN=YOUR_PRIVATE_GARMIN_WATCH_TOKEN
PORT=XXXX

Protect the file:

chmod 600 /tmp/mnt/entwere/entware/tedee/.env

Generate a new strong watch token if required:

/opt/bin/python3 -c 'import secrets; print(secrets.token_urlsafe(32))'

Never commit the real .env file to GitHub.

4. /tmp/mnt/entwere/entware/tedee/server.py

Create:

/tmp/mnt/entwere/entware/tedee/server.py

Use the following complete file:

#!/opt/bin/python3

import json
import os
import time
import threading
import urllib.request
import urllib.error

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


# ================================================================
# CONFIG
# ================================================================

ENV_FILE = "/tmp/mnt/entwere/entware/tedee/.env"

ACTION_COOLDOWN = 1.0
BRIDGE_TIMEOUT = 5


def load_env(path):
    if not os.path.exists(path):
        return

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()

            if not line:
                continue

            if line.startswith("#"):
                continue

            if "=" not in line:
                continue

            key, value = line.split("=", 1)

            key = key.strip()
            value = value.strip()

            if (
                len(value) >= 2
                and value[0] == value[-1]
                and value[0] in ("'", '"')
            ):
                value = value[1:-1]

            os.environ.setdefault(key, value)


load_env(ENV_FILE)


TEDEE_BRIDGE_IP = os.environ.get(
    "TEDEE_BRIDGE_IP",
    "X.X.X.X"
)

TEDEE_BRIDGE_PORT = os.environ.get(
    "TEDEE_BRIDGE_PORT",
    "80"
)

TEDEE_LOCK_ID = os.environ.get(
    "TEDEE_LOCK_ID"
)

TEDEE_BRIDGE_TOKEN = os.environ.get(
    "TEDEE_BRIDGE_TOKEN"
)

WATCH_TOKEN = os.environ.get(
    "WATCH_TOKEN"
)

PORT = int(
    os.environ.get(
        "PORT",
        "8090"
    )
)


if not TEDEE_LOCK_ID:
    raise RuntimeError(
        "TEDEE_LOCK_ID is missing"
    )

if not TEDEE_BRIDGE_TOKEN:
    raise RuntimeError(
        "TEDEE_BRIDGE_TOKEN is missing"
    )

if not WATCH_TOKEN:
    raise RuntimeError(
        "WATCH_TOKEN is missing"
    )


BRIDGE_BASE = (
    f"http://{TEDEE_BRIDGE_IP}:"
    f"{TEDEE_BRIDGE_PORT}"
)


# ================================================================
# ACTION CONTROL
# ================================================================

action_mutex = threading.Lock()
last_action_time = 0.0


# ================================================================
# BRIDGE HELPERS
# ================================================================

def bridge_headers():
    return {
        "Accept": "application/json",
        "api_token": TEDEE_BRIDGE_TOKEN,
    }


def bridge_get_status():

    url = (
        f"{BRIDGE_BASE}/v1.0/lock/"
        f"{TEDEE_LOCK_ID}"
    )

    request = urllib.request.Request(
        url,
        method="GET",
        headers=bridge_headers()
    )

    with urllib.request.urlopen(
        request,
        timeout=BRIDGE_TIMEOUT
    ) as response:

        body = response.read()

        if not body:
            return {}

        return json.loads(
            body.decode("utf-8")
        )


def bridge_action(action):

    url = (
        f"{BRIDGE_BASE}/v1.0/lock/"
        f"{TEDEE_LOCK_ID}/{action}"
    )

    request = urllib.request.Request(
        url,
        data=b"",
        method="POST",
        headers=bridge_headers()
    )

    try:

        with urllib.request.urlopen(
            request,
            timeout=BRIDGE_TIMEOUT
        ) as response:

            return (
                response.status,
                response.read()
            )

    except urllib.error.HTTPError as exc:

        return (
            exc.code,
            exc.read()
        )


# ================================================================
# HTTP SERVER
# ================================================================

class TedeeHandler(BaseHTTPRequestHandler):

    server_version = "TedeeGarmin/1.4"
    protocol_version = "HTTP/1.1"


    # ------------------------------------------------------------
    # JSON RESPONSE
    # ------------------------------------------------------------

    def send_json(self, status_code, payload):

        body = json.dumps(
            payload,
            separators=(",", ":")
        ).encode("utf-8")

        self.send_response(
            status_code
        )

        self.send_header(
            "Content-Type",
            "application/json; charset=utf-8"
        )

        self.send_header(
            "Content-Length",
            str(len(body))
        )

        self.send_header(
            "Cache-Control",
            "no-store"
        )

        self.end_headers()

        self.wfile.write(body)


    # ------------------------------------------------------------
    # AUTH
    # ------------------------------------------------------------

    def authorized(self):

        token = self.headers.get(
            "X-Tedee-Watch-Token"
        )

        return token == WATCH_TOKEN


    def require_auth(self):

        if self.authorized():
            return True

        self.send_json(
            401,
            {
                "ok": False,
                "error": "unauthorized"
            }
        )

        return False


    # ------------------------------------------------------------
    # GET
    # ------------------------------------------------------------

    def do_GET(self):

        if self.path == "/health":

            self.send_json(
                200,
                {
                    "ok": True,
                    "service": "tedee-garmin"
                }
            )

            return


        if self.path == "/api/status":

            if not self.require_auth():
                return

            try:

                status = bridge_get_status()

                self.send_json(
                    200,
                    status
                )

            except Exception as exc:

                self.send_json(
                    502,
                    {
                        "ok": False,
                        "error": "bridge_status_failed",
                        "message": str(exc)
                    }
                )

            return


        self.send_json(
            404,
            {
                "ok": False,
                "error": "not_found"
            }
        )


    # ------------------------------------------------------------
    # POST
    # ------------------------------------------------------------

    def do_POST(self):

        # Consume any request body before auth/routing.
        # This keeps persistent HTTP/1.1 connections clean.

        try:

            length = int(
                self.headers.get(
                    "Content-Length"
                ) or 0
            )

        except (TypeError, ValueError):

            length = 0


        if length > 0:

            self.rfile.read(
                length
            )


        # Auth

        if not self.require_auth():
            return


        # Routes

        if self.path == "/api/lock":

            self.handle_action(
                "lock"
            )

            return


        if self.path == "/api/unlock":

            self.handle_action(
                "unlock"
            )

            return


        self.send_json(
            404,
            {
                "ok": False,
                "error": "not_found"
            }
        )


    # ------------------------------------------------------------
    # LOCK / UNLOCK
    # ------------------------------------------------------------

    def handle_action(self, action):

        global last_action_time


        # --------------------------------------------------------
        # CHECK CURRENT LOCK STATE FIRST
        #
        # Important states:
        # 2 = open / unlocked
        # 6 = closed / locked
        #
        # Redundant commands become successful no-ops.
        # --------------------------------------------------------

        try:

            current = bridge_get_status()

            state = current.get(
                "state"
            )

        except Exception as exc:

            self.send_json(
                502,
                {
                    "ok": False,
                    "action": action,
                    "error": "status_check_failed",
                    "message": str(exc)
                }
            )

            return


        # Already locked

        if (
            action == "lock"
            and state == 6
        ):

            self.send_json(
                200,
                {
                    "ok": True,
                    "action": "lock",
                    "note": "already_locked",
                    "state": 6
                }
            )

            return


        # Already unlocked

        if (
            action == "unlock"
            and state == 2
        ):

            self.send_json(
                200,
                {
                    "ok": True,
                    "action": "unlock",
                    "note": "already_unlocked",
                    "state": 2
                }
            )

            return


        # --------------------------------------------------------
        # COOLDOWN
        # --------------------------------------------------------

        with action_mutex:

            now = time.monotonic()

            elapsed = (
                now -
                last_action_time
            )


            if elapsed < ACTION_COOLDOWN:

                self.send_json(
                    429,
                    {
                        "ok": False,
                        "action": action,
                        "note": "cooldown",
                        "retryAfter": round(
                            ACTION_COOLDOWN - elapsed,
                            2
                        )
                    }
                )

                return


            last_action_time = now


        # --------------------------------------------------------
        # SEND ACTION TO TEDEE BRIDGE
        # --------------------------------------------------------

        try:

            status_code, body = (
                bridge_action(
                    action
                )
            )

        except Exception as exc:

            self.send_json(
                502,
                {
                    "ok": False,
                    "action": action,
                    "error": "bridge_action_failed",
                    "message": str(exc)
                }
            )

            return


        # --------------------------------------------------------
        # SUCCESS
        #
        # Tedee normally returns HTTP 204 No Content.
        # Garmin expects JSON, so normalize to HTTP 200 JSON.
        # --------------------------------------------------------

        if status_code in (
            200,
            204
        ):

            self.send_json(
                200,
                {
                    "ok": True,
                    "action": action
                }
            )

            return


        # --------------------------------------------------------
        # RACE / RETRY PROTECTION
        #
        # Recheck state before treating a Bridge rejection as a
        # real failure.
        # --------------------------------------------------------

        try:

            current = bridge_get_status()

            new_state = current.get(
                "state"
            )


            if (
                action == "lock"
                and new_state == 6
            ):

                self.send_json(
                    200,
                    {
                        "ok": True,
                        "action": "lock",
                        "note": "already_locked",
                        "state": 6
                    }
                )

                return


            if (
                action == "unlock"
                and new_state == 2
            ):

                self.send_json(
                    200,
                    {
                        "ok": True,
                        "action": "unlock",
                        "note": "already_unlocked",
                        "state": 2
                    }
                )

                return


        except Exception:
            pass


        # --------------------------------------------------------
        # REAL BRIDGE FAILURE
        # --------------------------------------------------------

        bridge_message = ""


        if body:

            try:

                bridge_message = body.decode(
                    "utf-8",
                    errors="replace"
                )

            except Exception:

                bridge_message = ""


        self.send_json(
            status_code,
            {
                "ok": False,
                "action": action,
                "error": "bridge_rejected",
                "bridgeStatus": status_code,
                "message": bridge_message
            }
        )


    # ------------------------------------------------------------
    # LOGGING
    # ------------------------------------------------------------

    def log_message(
        self,
        fmt,
        *args
    ):

        print(
            "%s - %s" %
            (
                self.address_string(),
                fmt % args
            ),
            flush=True
        )


# ================================================================
# START SERVER
# ================================================================

if __name__ == "__main__":

    server = ThreadingHTTPServer(
        (
            "0.0.0.0",
            PORT
        ),
        TedeeHandler
    )

    print(
        "Tedee Garmin relay listening on "
        f"0.0.0.0:{PORT}",
        flush=True
    )

    server.serve_forever()

Make executable:

chmod +x /tmp/mnt/entwere/entware/tedee/server.py

5. /opt/etc/init.d/S99tedeeproxy

Create:

/opt/etc/init.d/S99tedeeproxy

Use:

#!/bin/sh

ENABLED=yes

PROCS=tedeeproxy
ARGS=""
PREARGS=""
DESC="Tedee Garmin relay"

PYTHON="/opt/bin/python3"
SCRIPT="/tmp/mnt/entwere/entware/tedee/server.py"

PIDFILE="/opt/var/run/tedeeproxy.pid"
LOGFILE="/opt/var/log/tedeeproxy.log"


start() {
    echo "Starting ${DESC}..."

    if [ -f "$PIDFILE" ]; then
        PID="$(cat "$PIDFILE")"

        if kill -0 "$PID" 2>/dev/null; then
            echo "${DESC} already running with PID $PID"
            return 0
        fi

        rm -f "$PIDFILE"
    fi

    mkdir -p /opt/var/run
    mkdir -p /opt/var/log

    "$PYTHON" "$SCRIPT" >> "$LOGFILE" 2>&1 &

    PID=$!

    echo "$PID" > "$PIDFILE"

    sleep 1

    if kill -0 "$PID" 2>/dev/null; then
        echo "${DESC} started with PID $PID"
        return 0
    fi

    echo "Failed to start ${DESC}"
    rm -f "$PIDFILE"
    return 1
}


stop() {
    echo "Stopping ${DESC}..."

    if [ ! -f "$PIDFILE" ]; then
        echo "${DESC} is not running"
        return 0
    fi

    PID="$(cat "$PIDFILE")"

    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"

        COUNT=0

        while kill -0 "$PID" 2>/dev/null; do
            COUNT=$((COUNT + 1))

            if [ "$COUNT" -ge 10 ]; then
                kill -9 "$PID" 2>/dev/null
                break
            fi

            sleep 1
        done
    fi

    rm -f "$PIDFILE"

    echo "${DESC} stopped"
}


restart() {
    stop
    sleep 1
    start
}


status() {
    if [ -f "$PIDFILE" ]; then
        PID="$(cat "$PIDFILE")"

        if kill -0 "$PID" 2>/dev/null; then
            echo "${DESC} is running with PID $PID"
            return 0
        fi
    fi

    echo "${DESC} is not running"
    return 1
}


check() {
    status
}


case "$1" in
    start)
        start
        ;;

    stop)
        stop
        ;;

    restart)
        restart
        ;;

    status)
        status
        ;;

    check)
        check
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status|check}"
        exit 1
        ;;
esac

Make executable:

chmod +x /opt/etc/init.d/S99tedeeproxy

Create log/run directories if they do not exist:

mkdir -p /opt/var/log
mkdir -p /opt/var/run

Test:

/opt/etc/init.d/S99tedeeproxy start

Check:

/opt/etc/init.d/S99tedeeproxy status

Restart:

/opt/etc/init.d/S99tedeeproxy restart

Log:

tail -f /opt/var/log/tedeeproxy.log

6. /opt/etc/init.d/S80nginx

This file is normally supplied by the Entware nginx package.

Path:

/opt/etc/init.d/S80nginx

You normally do NOT need to replace or manually recreate it.

Verify it exists:

ls -l /opt/etc/init.d/S80nginx

Useful commands:

/opt/etc/init.d/S80nginx start
/opt/etc/init.d/S80nginx stop
/opt/etc/init.d/S80nginx restart

Validate nginx before restarting:

/opt/sbin/nginx -t

If S80nginx is missing, install/reinstall the Entware nginx package rather than copying an unknown service script from another router.

7. /opt/etc/nginx/nginx.conf

Create or replace:

/opt/etc/nginx/nginx.conf

with:

user nobody nobody;

worker_processes  1;

error_log  /opt/var/log/nginx/error.log;

pid        /opt/var/run/nginx.pid;


events {
    worker_connections  256;
}


http {

    include       mime.types;
    default_type  application/octet-stream;

    access_log  /opt/var/log/nginx/access.log;

    sendfile        on;

    keepalive_timeout  65;


    server {

        listen PORT ssl;
        server_name your.home.domain;


        ssl_certificate
            /jffs/.le/your.home.domain_ecc/fullchain.pem;

        ssl_certificate_key
            /jffs/.le/your.home.domain_ecc/domain.key;


        # --------------------------------------------------------
        # Health
        # --------------------------------------------------------

        location = /health {

            proxy_pass http://127.0.0.1:PORT/health;

            proxy_http_version 1.1;

            proxy_pass_request_headers on;

            proxy_set_header Host $host;

            proxy_set_header X-Real-IP $remote_addr;
        }


        # --------------------------------------------------------
        # Tedee status
        # --------------------------------------------------------

        location = /api/status {

            proxy_pass http://127.0.0.1:PORT/api/status;

            proxy_http_version 1.1;

            proxy_pass_request_headers on;

            proxy_set_header Host $host;

            proxy_set_header X-Real-IP $remote_addr;
        }


        # --------------------------------------------------------
        # Tedee LOCK
        # --------------------------------------------------------

        location = /api/lock {

            proxy_pass http://127.0.0.1:PORT/api/lock;

            proxy_http_version 1.1;

            proxy_pass_request_headers on;

            proxy_set_header Host $host;

            proxy_set_header X-Real-IP $remote_addr;
        }


        # --------------------------------------------------------
        # Tedee UNLOCK
        # --------------------------------------------------------

        location = /api/unlock {

            proxy_pass http://127.0.0.1:PORT/api/unlock;

            proxy_http_version 1.1;

            proxy_pass_request_headers on;

            proxy_set_header Host $host;

            proxy_set_header X-Real-IP $remote_addr;
        }


        # --------------------------------------------------------
        # Everything else
        # --------------------------------------------------------

        location / {

            return 404;
        }
    }
}

Create log directory if required:

mkdir -p /opt/var/log/nginx

Validate:

/opt/sbin/nginx -t

Expected:

syntax is ok
test is successful

Restart:

/opt/etc/init.d/S80nginx restart

Check:

netstat -lntp | grep PORT

Monitor access log:

tail -f /opt/var/log/nginx/access.log

Monitor nginx errors:

tail -f /opt/var/log/nginx/error.log

8. /jffs/scripts/services-start

Create or edit:

/jffs/scripts/services-start

Use:

#!/bin/sh

# Start Entware
/opt/etc/init.d/rc.unslung start

# Start Tedee Garmin relay
/opt/etc/init.d/S99tedeeproxy start

Make executable:

chmod +x /jffs/scripts/services-start

Important:

rc.unslung start starts Entware init scripts, including nginx if S80nginx is enabled.

Therefore you normally do not need to add another explicit:

/opt/etc/init.d/S80nginx start

line.

Also do not add a second Tedee relay startup line if S99tedeeproxy is already being started explicitly.

9. /jffs/.le/your.home.domain_ecc/fullchain.pem

Path:

/jffs/.le/your.home.domain_ecc/fullchain.pem

This is the Let's Encrypt certificate chain used by nginx.

Check it exists:

ls -l /jffs/.le/your.home.domain_ecc/fullchain.pem

Inspect the certificate:

openssl x509 \
  -in /jffs/.le/your.home.domain_ecc/fullchain.pem \
  -noout \
  -subject \
  -issuer \
  -dates

The certificate must cover:

homeie.hopto.org

Do not manually replace this file with arbitrary certificate text unless you know exactly what you are doing.

The router's certificate/DDNS system should manage renewal.

10. /jffs/.le/your.home.domain_ecc/domain.key

Path:

/jffs/.le/your.home.domain_ecc/domain.key

This is the private TLS key for the certificate.

Check it exists:

ls -l /jffs/.le/your.home.domain_ecc/domain.key

nginx references it as:

ssl_certificate_key
    /jffs/.le/your.home.domain_ecc/domain.key;

IMPORTANT:

Never paste the contents of this file into:

README files

GitHub

forums

ChatGPT

screenshots

email

source repositories

The path belongs in documentation; the private key contents do not.

11. Start Order

The required startup sequence is:

ASUS boots
    |
    v
/jffs/scripts/services-start
    |
    v
/opt/etc/init.d/rc.unslung start
    |
    +--> Entware nginx / S80nginx
    |
    v
/opt/etc/init.d/S99tedeeproxy start
    |
    v
Python relay listens on 8090
    |
    v
nginx listens on 9443

12. Test Python Relay Directly

Health:

curl -i http://127.0.0.1:PORT/health

Expected:

HTTP/1.1 200 OK

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

13. Test nginx HTTPS

From Windows:

curl.exe -i https://your.home.domain:PORT/health

Status:

curl.exe -i `
  -H "X-Tedee-Watch-Token: YOUR_WATCH_TOKEN" `
  https://your.home.domain:PORT/api/status

Lock:

curl.exe -i `
  -X POST `
  -H "X-Tedee-Watch-Token: YOUR_WATCH_TOKEN" `
  https://your.home.domain:PORT/api/lock

Unlock:

curl.exe -i `
  -X POST `
  -H "X-Tedee-Watch-Token: YOUR_WATCH_TOKEN" `
  https://your.home.domain:PORT/api/unlock

14. Expected Relay Responses

Normal successful unlock:

{
  "ok": true,
  "action": "unlock"
}

Normal successful lock:

{
  "ok": true,
  "action": "lock"
}

Already locked:

{
  "ok": true,
  "action": "lock",
  "note": "already_locked",
  "state": 6
}

Already unlocked:

{
  "ok": true,
  "action": "unlock",
  "note": "already_unlocked",
  "state": 2
}

Cooldown:

{
  "ok": false,
  "action": "lock",
  "note": "cooldown",
  "retryAfter": 0.5
}

15. Why server.py Uses HTTP/1.1

The handler contains:

protocol_version = "HTTP/1.1"

and every JSON response contains a correct:

Content-Length

The POST handler also consumes any incoming request body:

length = int(
    self.headers.get(
        "Content-Length"
    ) or 0
)

if length > 0:
    self.rfile.read(length)

This prevents unread POST body data from interfering with a later request when Garmin reuses an HTTP/1.1 connection.

16. Why Tedee 204 Is Converted to JSON 200

Tedee normally responds to a successful lock/unlock command with:

204 No Content

Garmin uses:

HTTP_RESPONSE_CONTENT_TYPE_JSON

so an empty 204 response can be inconvenient for the Connect IQ callback.

The relay therefore converts:

Tedee Bridge:
204 No Content

to:

Relay:
200 OK
Content-Type: application/json

{"ok":true,"action":"unlock"}

17. Why the Relay Checks Current State First

The relay makes actions idempotent.

If the lock is already locked:

state = 6

and Garmin sends:

LOCK

the relay returns:

200 OK
already_locked

instead of asking Tedee to perform an unnecessary lock operation.

Likewise:

state = 2
UNLOCK request

becomes:

200 OK
already_unlocked

This is particularly useful because Garmin sync operations may be retried.

18. Tedee Auto-Lock

If Tedee has:

autoLockEnabled = 1

with a delay of:

300 seconds

the lock will automatically re-lock after five minutes.

This means a later manual LOCK request may arrive when the lock is already secure.

The relay's already_locked handling makes that situation appear correctly as success instead of an error.

19. Action Cooldown

The relay currently uses:

ACTION_COOLDOWN = 1.0

Rapid repeated commands may return:

HTTP 429

with:

{
  "note": "cooldown"
}

The Garmin app should map this to:

PLEASE WAIT

rather than treating it as a serious lock failure.

20. Garmin Project Files

The Garmin source is separate from the router files.

Typical structure:

C:\tedee\garmin\
│
├── manifest.xml
├── monkey.jungle
│
├── source\
│   ├── TedeeApp.mc
│   ├── TedeeConfig.mc
│   ├── TedeeDelegate.mc
│   ├── TedeeSyncDelegate.mc
│   └── TedeeView.mc
│
├── resources-fenix7x\
│   └── drawables\
│       ├── launcher_icon.xml
│       └── launcher_icon_40x40.png
│
└── resources-marq2\
    └── drawables\
        ├── launcher_icon.xml
        └── launcher_icon_60x60.png

Garmin endpoint:

https://homeie.hopto.org:9443

Garmin sends:

X-Tedee-Watch-Token

with requests.

21. Garmin Build Commands

fēnix 7X:

cd C:\tedee\garmin

monkeyc `
  -f monkey.jungle `
  -o bin\Tedee-fenix7.prg `
  -y C:\tedee\developer_key `
  -d fenix7x `
  -w

MARQ Gen 2:

cd C:\tedee\garmin

monkeyc `
  -f monkey.jungle `
  -o bin\Tedee-marq2.prg `
  -y C:\tedee\developer_key `
  -d marq2 `
  -w

22. Monitoring

nginx access log:

tail -f /opt/var/log/nginx/access.log

nginx error log:

tail -f /opt/var/log/nginx/error.log

Tedee relay log:

tail -f /opt/var/log/tedeeproxy.log

A successful Garmin action should typically result in:

POST /api/unlock

or:

POST /api/lock

followed by:

GET /api/status

23. Verify Everything After Router Reboot

After reboot:

/opt/etc/init.d/S99tedeeproxy status

Check Python:

ps | grep server.py

Check nginx:

ps | grep nginx

Check listening ports:

netstat -lntp | grep 8090

and:

netstat -lntp | grep 9443

Test:

curl -i http://127.0.0.1:PORT/health

Then:

curl -i https://your.home.domain:PORT/health

24. Backup the Configuration

Recommended backup files:

/tmp/mnt/entwere/entware/tedee/server.py
/tmp/mnt/entwere/entware/tedee/.env
/opt/etc/init.d/S99tedeeproxy
/opt/etc/nginx/nginx.conf
/jffs/scripts/services-start

You may also record the certificate paths:

/jffs/.le/your.home.domain_ecc/fullchain.pem
/jffs/.le/your.home.domain_ecc/domain.key

but normally do not manually back up or redistribute the private key unless you have a secure encrypted backup procedure.

25. Security

Keep these private:

TEDEE_BRIDGE_TOKEN
WATCH_TOKEN
domain.key

Do not publish them.

If either token has ever been exposed publicly, rotate it.

The public service should expose only:

/health
/api/status
/api/lock
/api/unlock

Everything else should return:

404

26. Final Router-Side File Checklist

Custom application

/tmp/mnt/entwere/entware/tedee/server.py

Secrets/config

/tmp/mnt/entwere/entware/tedee/.env

Python relay service

/opt/etc/init.d/S99tedeeproxy

nginx service supplied by Entware

/opt/etc/init.d/S80nginx

nginx TLS reverse proxy configuration

/opt/etc/nginx/nginx.conf

Merlin boot hook

/jffs/scripts/services-start

Let's Encrypt certificate

/jffs/.le/your.home.domain_ecc/fullchain.pem

Let's Encrypt private key

/jffs/.le/your.home.domain_ecc/domain.key

27. Final Architecture

Garmin fēnix 7X / MARQ Gen 2
             |
             | HTTPS :PORT
             v
     your.home.domain
             |
             v
          nginx
             |
             | HTTP/1.1
             v
      127.0.0.1:PORT
             |
             v
        server.py
             |
             | api_token
             v
   Tedee Bridge X.X.X.X
             |
             v
        Tedee Lock

This is the complete router-side setup required for the working Garmin-to-Tedee solution.

This configuration was tested successfully with a physical Garmin fēnix 7X, marq2 and a Tedee smart lock.
