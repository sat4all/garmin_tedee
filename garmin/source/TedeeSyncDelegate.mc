using Toybox.Application.Storage;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.PersistedContent;


class TedeeSyncDelegate
    extends Communications.SyncDelegate {

    var _action = null;

    var _stopping = false;

    var _actionAccepted = false;


    // ============================================================
    // INITIALIZE
    // ============================================================

    function initialize() {

        SyncDelegate.initialize();
    }


    // ============================================================
    // SYNC REQUIRED
    // ============================================================

    function isSyncNeeded()
        as Lang.Boolean {

        return true;
    }


    // ============================================================
    // START SYNC
    // ============================================================

    function onStartSync()
        as Void {

        _stopping = false;
        _actionAccepted = false;

        Communications.notifySyncProgress(
            5
        );


        var pending =
            Storage.getValue(
                "tedee_pending_action"
            );


        if (pending == null) {

            finishFailure(
                -1,
                "NO COMMAND"
            );

            return;
        }


        _action =
            pending.toString();


        if (_action.equals("lock")) {

            sendLock();

            return;
        }


        if (_action.equals("unlock")) {

            sendUnlock();

            return;
        }


        finishFailure(
            -1,
            "UNKNOWN COMMAND"
        );
    }


    // ============================================================
    // LOCK
    // ============================================================

    function sendLock()
        as Void {

        Communications.notifySyncProgress(
            20
        );


        var url =
            TedeeConfig.BASE_URL +
            "/api/lock";


        var headers = {

            "X-Tedee-Watch-Token" =>
                TedeeConfig.WATCH_TOKEN,

            "Accept" =>
                "application/json"
        };


        var options = {

            :method =>
                Communications.HTTP_REQUEST_METHOD_POST,

            :headers =>
                headers,

            :responseType =>
                Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };


        Communications.makeWebRequest(
            url,
            null,
            options,
            method(:onLockResponse)
        );
    }


    function onLockResponse(
        responseCode as Lang.Number,
        data as
            Lang.Dictionary or
            Lang.String or
            PersistedContent.Iterator or
            Null
    ) as Void {

        if (_stopping) {
            return;
        }


        // --------------------------------------------------------
        // SUCCESS
        // --------------------------------------------------------

        if (responseCode == 200) {

            _actionAccepted = true;

            saveActionResult(
                data,
                "lock"
            );

            Communications.notifySyncProgress(
                60
            );

            getStatus();

            return;
        }


        // --------------------------------------------------------
        // COOLDOWN IS NOT A HARD FAILURE
        // --------------------------------------------------------

        if (responseCode == 429) {

            Storage.setValue(
                "tedee_action_note",
                "cooldown"
            );


            // Do not retry this command automatically.
            Storage.deleteValue(
                "tedee_pending_action"
            );


            Communications.notifySyncProgress(
                60
            );

            getStatus();

            return;
        }


        Storage.deleteValue(
            "tedee_pending_action"
        );


        finishFailure(
            responseCode,
            "LOCK FAILED"
        );
    }


    // ============================================================
    // UNLOCK
    // ============================================================

    function sendUnlock()
        as Void {

        Communications.notifySyncProgress(
            20
        );


        var url =
            TedeeConfig.BASE_URL +
            "/api/unlock";


        var headers = {

            "X-Tedee-Watch-Token" =>
                TedeeConfig.WATCH_TOKEN,

            "Accept" =>
                "application/json"
        };


        var options = {

            :method =>
                Communications.HTTP_REQUEST_METHOD_POST,

            :headers =>
                headers,

            :responseType =>
                Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };


        Communications.makeWebRequest(
            url,
            null,
            options,
            method(:onUnlockResponse)
        );
    }


    function onUnlockResponse(
        responseCode as Lang.Number,
        data as
            Lang.Dictionary or
            Lang.String or
            PersistedContent.Iterator or
            Null
    ) as Void {

        if (_stopping) {
            return;
        }


        // --------------------------------------------------------
        // SUCCESS
        // --------------------------------------------------------

        if (responseCode == 200) {

            _actionAccepted = true;

            saveActionResult(
                data,
                "unlock"
            );

            Communications.notifySyncProgress(
                60
            );

            getStatus();

            return;
        }


        // --------------------------------------------------------
        // COOLDOWN
        // --------------------------------------------------------

        if (responseCode == 429) {

            Storage.setValue(
                "tedee_action_note",
                "cooldown"
            );


            Storage.deleteValue(
                "tedee_pending_action"
            );


            Communications.notifySyncProgress(
                60
            );

            getStatus();

            return;
        }


        Storage.deleteValue(
            "tedee_pending_action"
        );


        finishFailure(
            responseCode,
            "UNLOCK FAILED"
        );
    }


    // ============================================================
    // SAVE ACTION RESPONSE
    // ============================================================

    function saveActionResult(
        data as
            Lang.Dictionary or
            Lang.String or
            PersistedContent.Iterator or
            Null,
        action as Lang.String
    ) as Void {

        Storage.deleteValue(
            "tedee_action_note"
        );


        if (data instanceof Lang.Dictionary) {

            var response =
                data as Lang.Dictionary;


            var note =
                response["note"];


            if (note != null) {

                Storage.setValue(
                    "tedee_action_note",
                    note.toString()
                );

                return;
            }
        }


        // Normal successful action with no special note.

        if (action.equals("lock")) {

            Storage.setValue(
                "tedee_action_note",
                "lock_sent"
            );

        } else if (
            action.equals("unlock")
        ) {

            Storage.setValue(
                "tedee_action_note",
                "unlock_sent"
            );
        }
    }


    // ============================================================
    // GET CURRENT STATUS
    // ============================================================

    function getStatus()
        as Void {

        Communications.notifySyncProgress(
            75
        );


        var url =
            TedeeConfig.BASE_URL +
            "/api/status";


        var headers = {

            "X-Tedee-Watch-Token" =>
                TedeeConfig.WATCH_TOKEN,

            "Accept" =>
                "application/json"
        };


        var options = {

            :method =>
                Communications.HTTP_REQUEST_METHOD_GET,

            :headers =>
                headers,

            :responseType =>
                Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };


        Communications.makeWebRequest(
            url,
            null,
            options,
            method(:onStatusResponse)
        );
    }


    // ============================================================
    // STATUS RESPONSE
    // ============================================================

    function onStatusResponse(
        responseCode as Lang.Number,
        data as
            Lang.Dictionary or
            Lang.String or
            PersistedContent.Iterator or
            Null
    ) as Void {

        if (_stopping) {
            return;
        }


        if (responseCode != 200) {

            // If the action itself succeeded but status failed,
            // keep the pending command.
            //
            // Retrying is safe because the relay is now idempotent.

            finishFailure(
                responseCode,
                "STATUS FAILED"
            );

            return;
        }


        if (data instanceof Lang.Dictionary) {

            var response =
                data as Lang.Dictionary;


            var state =
                response["state"];


            if (state != null) {

                Storage.setValue(
                    "tedee_state",
                    state
                );
            }


            var battery =
                response["batteryLevel"];


            if (battery != null) {

                Storage.setValue(
                    "tedee_battery",
                    battery
                );
            }
        }


        // We have completed the full round trip.
        //
        // Action -> Bridge -> Status
        //
        // Now it is safe to remove pending command.

        Storage.deleteValue(
            "tedee_pending_action"
        );


        finishSuccess();
    }


    // ============================================================
    // SUCCESS
    // ============================================================

    function finishSuccess()
        as Void {

        if (_stopping) {
            return;
        }


        Storage.setValue(
            "tedee_sync_success",
            true
        );


        Storage.deleteValue(
            "tedee_last_error"
        );


        Communications.notifySyncProgress(
            100
        );


        Communications.notifySyncComplete(
            null
        );
    }


    // ============================================================
    // FAILURE
    // ============================================================

    function finishFailure(
        code,
        message
    ) as Void {

        if (_stopping) {
            return;
        }


        Storage.setValue(
            "tedee_sync_success",
            false
        );


        Storage.setValue(
            "tedee_last_error",
            code
        );


        Storage.setValue(
            "tedee_last_error_message",
            message
        );


        Communications.notifySyncComplete(
            message
        );
    }


    // ============================================================
    // CANCEL
    // ============================================================

    function onStopSync()
        as Void {

        // Set this BEFORE cancelAllRequests().
        //
        // cancelAllRequests() can invoke a pending callback.
        // The callback sees _stopping == true and therefore does
        // not call notifySyncComplete() a second time.

        _stopping = true;


        Communications.cancelAllRequests();


        Communications.notifySyncComplete(
            null
        );
    }
}