using Toybox.Graphics;
using Toybox.Communications;
using Toybox.WatchUi;

class TedeeView extends WatchUi.View {
    var connectionText = "CONNECTING";
    var lockText = "";
    var batteryText = "";
    var messageText = "";
    var busy = false;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        refresh();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        dc.drawText(w / 2, 12, Graphics.FONT_MEDIUM, "TEDEE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 48, Graphics.FONT_SMALL, connectionText, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 82, Graphics.FONT_MEDIUM, lockText, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 122, Graphics.FONT_SMALL, batteryText, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 154, Graphics.FONT_SMALL, messageText, Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(w / 2, 188, Graphics.FONT_TINY, "SEL  REFRESH", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 204, Graphics.FONT_TINY, "NEXT  UNLOCK", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(w / 2, 220, Graphics.FONT_TINY, "PREV  LOCK", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function request(path, method, callback) {
        var options = {
            :method => method,
            :headers => {
                "X-Tedee-Watch-Token" => TedeeConfig.WATCH_TOKEN,
                "Accept" => "application/json"
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(
            TedeeConfig.BASE_URL + path,
            null,
            options,
            callback
        );
    }

    function refresh() {
        if (busy) {
            return;
        }

        connectionText = "READING...";
        messageText = "";
        WatchUi.requestUpdate();
        request("/api/status", Communications.HTTP_REQUEST_METHOD_GET, method(:statusCallback));
    }

    function statusCallback(responseCode, data) {
        if (responseCode == 200 && data != null) {
            connectionText = "ONLINE";

            var state = data["state"];
            lockText = TedeeConfig.stateName(state);

            if (data["batteryLevel"] != null) {
                batteryText = "BATTERY  " + data["batteryLevel"] + "%";
            } else {
                batteryText = "";
            }
        } else {
            connectionText = "OFFLINE";
            lockText = "";
            batteryText = "";
            messageText = "ERROR " + responseCode;
        }

        WatchUi.requestUpdate();
    }

    function lock() {
        if (busy) {
            return;
        }

        busy = true;
        messageText = "LOCKING...";
        WatchUi.requestUpdate();
        request("/api/lock", Communications.HTTP_REQUEST_METHOD_POST, method(:actionCallback));
    }

    function unlock() {
        if (busy) {
            return;
        }

        var dialog = new WatchUi.Confirmation("Unlock Main door?");
        WatchUi.pushView(dialog, new TedeeUnlockConfirmationDelegate(self), WatchUi.SLIDE_IMMEDIATE);
    }

    function performUnlock() {
        if (busy) {
            return;
        }

        busy = true;
        messageText = "UNLOCKING...";
        WatchUi.requestUpdate();
        request("/api/unlock", Communications.HTTP_REQUEST_METHOD_POST, method(:actionCallback));
    }

    function actionCallback(responseCode, data) {
        busy = false;

        if (responseCode == 204 || responseCode == 200) {
            messageText = "COMMAND SENT";
            refreshAfterAction();
        } else if (responseCode == 401) {
            messageText = "UNAUTHORIZED";
        } else if (responseCode == 429) {
            messageText = "WAIT A MOMENT";
        } else {
            messageText = "ERROR " + responseCode;
        }

        WatchUi.requestUpdate();
    }

    function refreshAfterAction() {
        // Allow the bridge a moment to update the reported state.
        // The user can also press SELECT for an immediate refresh.
        request("/api/status", Communications.HTTP_REQUEST_METHOD_GET, method(:postActionStatusCallback));
    }

    function postActionStatusCallback(responseCode, data) {
        if (responseCode == 200 && data != null) {
            connectionText = "ONLINE";
            lockText = TedeeConfig.stateName(data["state"]);
            if (data["batteryLevel"] != null) {
                batteryText = "BATTERY  " + data["batteryLevel"] + "%";
            }
        }
        WatchUi.requestUpdate();
    }
}

class TedeeUnlockConfirmationDelegate extends WatchUi.ConfirmationDelegate {
    var view;

    function initialize(tedeeView) {
        ConfirmationDelegate.initialize();
        view = tedeeView;
    }

    function onResponse(response) {
        if (response == WatchUi.CONFIRM_YES) {
            view.performUnlock();
        }
        return true;
    }
}
