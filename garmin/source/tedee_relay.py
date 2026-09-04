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
    "192.168.1.167"
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

        # --------------------------------------------------------
        # CONSUME REQUEST BODY
        #
        # Garmin may send a small POST body even though this relay
        # does not need one.
        #
        # With HTTP/1.1 the connection may be reused, so leaving
        # request-body bytes unread could interfere with parsing
        # the next request on the same connection.
        # --------------------------------------------------------

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


        # --------------------------------------------------------
        # AUTH
        # --------------------------------------------------------

        if not self.require_auth():
            return


        # --------------------------------------------------------
        # ROUTES
        # --------------------------------------------------------

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


        # ========================================================
        # CHECK CURRENT LOCK STATE FIRST
        #
        # Tedee states:
        #
        # 2 = open
        # 3 = partially open
        # 6 = closed / locked
        #
        # Redundant commands become successful no-ops.
        # ========================================================

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


        # --------------------------------------------------------
        # ALREADY LOCKED
        # --------------------------------------------------------

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


        # --------------------------------------------------------
        # ALREADY UNLOCKED
        # --------------------------------------------------------

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


        # ========================================================
        # COOLDOWN
        # ========================================================

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


        # ========================================================
        # SEND ACTION TO TEDEE BRIDGE
        # ========================================================

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


        # ========================================================
        # SUCCESS
        #
        # Tedee normally returns:
        #
        # HTTP 204 No Content
        #
        # Garmin expects JSON, therefore normalize this to:
        #
        # HTTP 200
        # Content-Type: application/json
        #
        # {"ok":true,"action":"unlock"}
        # ========================================================

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


        # ========================================================
        # RACE-CONDITION / RETRY PROTECTION
        #
        # The state may have changed after our original status
        # check but before Tedee processed the POST.
        #
        # Recheck before treating a Bridge rejection as failure.
        # ========================================================

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


        # ========================================================
        # REAL BRIDGE FAILURE
        # ========================================================

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