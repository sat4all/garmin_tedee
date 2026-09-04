using Toybox.Application.Storage;
using Toybox.Communications;
using Toybox.Graphics;
using Toybox.WatchUi;


class TedeeView extends WatchUi.View {

    var connectionText = "READY";

    var lockText = "UNKNOWN";

    var batteryText = "";

    var messageText = "";

    // 0 = unlock
    // 1 = lock

    var selectedAction = 0;

    var syncStarted = false;


    // ============================================================
    // INITIALIZE
    // ============================================================

    function initialize() {

        View.initialize();
    }


    // ============================================================
    // SHOW
    // ============================================================

    function onShow() {

        syncStarted = false;

        connectionText =
            "READY";


        loadCachedStatus();

        loadActionNote();

        loadLastError();


        WatchUi.requestUpdate();
    }


    // ============================================================
    // CACHED STATUS
    // ============================================================

    function loadCachedStatus() {

        var state =
            Storage.getValue(
                "tedee_state"
            );


        var battery =
            Storage.getValue(
                "tedee_battery"
            );


        if (state != null) {

            lockText =
                TedeeConfig.stateName(
                    state
                );


            // Locked -> sensible default is UNLOCK.

            if (state == 6) {

                selectedAction = 0;
            }


            // Open or partially open -> sensible default is LOCK.

            if (
                state == 2
                || state == 3
            ) {

                selectedAction = 1;
            }
        }


        if (battery != null) {

            batteryText =
                "BATTERY " +
                battery.toString() +
                "%";
        }
    }


    // ============================================================
    // ACTION RESULT
    // ============================================================

    function loadActionNote() {

        var note =
            Storage.getValue(
                "tedee_action_note"
            );


        if (note == null) {
            return;
        }


        var value =
            note.toString();


        if (
            value.equals(
                "already_locked"
            )
        ) {

            messageText =
                "ALREADY LOCKED";

        } else if (
            value.equals(
                "already_unlocked"
            )
        ) {

            messageText =
                "ALREADY UNLOCKED";

        } else if (
            value.equals(
                "lock_sent"
            )
        ) {

            messageText =
                "LOCK SENT";

        } else if (
            value.equals(
                "unlock_sent"
            )
        ) {

            messageText =
                "UNLOCK SENT";

        } else if (
            value.equals(
                "cooldown"
            )
        ) {

            messageText =
                "PLEASE WAIT";
        }


        Storage.deleteValue(
            "tedee_action_note"
        );
    }


    // ============================================================
    // LAST ERROR
    // ============================================================

    function loadLastError() {

        var success =
            Storage.getValue(
                "tedee_sync_success"
            );


        if (success == null) {
            return;
        }


        if (success == true) {

            Storage.deleteValue(
                "tedee_sync_success"
            );

            Storage.deleteValue(
                "tedee_last_error"
            );

            Storage.deleteValue(
                "tedee_last_error_message"
            );

            return;
        }


        var error =
            Storage.getValue(
                "tedee_last_error"
            );


        if (error != null) {

            messageText =
                "ERROR " +
                error.toString();
        }


        Storage.deleteValue(
            "tedee_sync_success"
        );

        Storage.deleteValue(
            "tedee_last_error"
        );

        Storage.deleteValue(
            "tedee_last_error_message"
        );
    }


    // ============================================================
    // DRAW
    // ============================================================

    function onUpdate(dc) {

        var width =
            dc.getWidth();


        dc.setColor(
            Graphics.COLOR_WHITE,
            Graphics.COLOR_BLACK
        );


        dc.clear();


        // --------------------------------------------------------
        // TITLE
        // --------------------------------------------------------

        dc.drawText(
            width / 2,
            20,
            Graphics.FONT_MEDIUM,
            "TEDEE",
            Graphics.TEXT_JUSTIFY_CENTER
        );


        // --------------------------------------------------------
        // CONNECTION / ACTION STATE
        // --------------------------------------------------------

        dc.drawText(
            width / 2,
            55,
            Graphics.FONT_SMALL,
            connectionText,
            Graphics.TEXT_JUSTIFY_CENTER
        );


        // --------------------------------------------------------
        // LOCK STATE
        // --------------------------------------------------------

        dc.drawText(
            width / 2,
            90,
            Graphics.FONT_MEDIUM,
            lockText,
            Graphics.TEXT_JUSTIFY_CENTER
        );


        // --------------------------------------------------------
        // BATTERY
        // --------------------------------------------------------

        dc.drawText(
            width / 2,
            125,
            Graphics.FONT_SMALL,
            batteryText,
            Graphics.TEXT_JUSTIFY_CENTER
        );


        // --------------------------------------------------------
        // ACTIONS
        // --------------------------------------------------------

        if (!syncStarted) {

            if (selectedAction == 0) {

                dc.drawText(
                    width / 2,
                    160,
                    Graphics.FONT_MEDIUM,
                    "> UNLOCK <",
                    Graphics.TEXT_JUSTIFY_CENTER
                );


                dc.drawText(
                    width / 2,
                    195,
                    Graphics.FONT_SMALL,
                    "LOCK",
                    Graphics.TEXT_JUSTIFY_CENTER
                );

            } else {

                dc.drawText(
                    width / 2,
                    160,
                    Graphics.FONT_SMALL,
                    "UNLOCK",
                    Graphics.TEXT_JUSTIFY_CENTER
                );


                dc.drawText(
                    width / 2,
                    195,
                    Graphics.FONT_MEDIUM,
                    "> LOCK <",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }

        } else {

            dc.drawText(
                width / 2,
                165,
                Graphics.FONT_MEDIUM,
                "STARTING WIFI",
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }


        // --------------------------------------------------------
        // RESULT MESSAGE
        // --------------------------------------------------------

        if (
            messageText != ""
        ) {

            dc.drawText(
                width / 2,
                225,
                Graphics.FONT_TINY,
                messageText,
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }


    // ============================================================
    // UP
    // ============================================================

    function moveUp() {

        if (syncStarted) {
            return;
        }


        selectedAction = 0;

        messageText = "";


        WatchUi.requestUpdate();
    }


    // ============================================================
    // DOWN
    // ============================================================

    function moveDown() {

        if (syncStarted) {
            return;
        }


        selectedAction = 1;

        messageText = "";


        WatchUi.requestUpdate();
    }


    // ============================================================
    // SELECT
    // ============================================================

    function selectAction() {

        if (syncStarted) {
            return;
        }


        if (selectedAction == 0) {

            showUnlockConfirmation();

        } else {

            startWifiSync(
                "lock"
            );
        }
    }


    // ============================================================
    // UNLOCK CONFIRMATION
    // ============================================================

    function showUnlockConfirmation() {

        var dialog =
            new WatchUi.Confirmation(
                "Unlock Main door?"
            );


        WatchUi.pushView(
            dialog,
            new TedeeUnlockConfirmationDelegate(
                self
            ),
            WatchUi.SLIDE_IMMEDIATE
        );
    }


    // ============================================================
    // CONFIRMED UNLOCK
    // ============================================================

    function performUnlock() {

        startWifiSync(
            "unlock"
        );
    }


    // ============================================================
    // START GARMIN WIFI SYNC
    // ============================================================

    function startWifiSync(action) {

        if (syncStarted) {
            return;
        }


        syncStarted = true;


        // Remove old result information.

        Storage.deleteValue(
            "tedee_action_note"
        );

        Storage.deleteValue(
            "tedee_last_error"
        );

        Storage.deleteValue(
            "tedee_last_error_message"
        );

        Storage.deleteValue(
            "tedee_sync_success"
        );


        // Store command before entering Garmin sync mode.

        Storage.setValue(
            "tedee_pending_action",
            action
        );


        if (
            action.equals(
                "lock"
            )
        ) {

            connectionText =
                "LOCKING";

        } else {

            connectionText =
                "UNLOCKING";
        }


        messageText =
            "STARTING WIFI";


        WatchUi.requestUpdate();


        Communications.startSync();
    }
}


// ================================================================
// UNLOCK CONFIRMATION DELEGATE
// ================================================================

class TedeeUnlockConfirmationDelegate
    extends WatchUi.ConfirmationDelegate {

    var _view;


    function initialize(view) {

        ConfirmationDelegate.initialize();

        _view = view;
    }


    function onResponse(response) {

        if (
            response ==
            WatchUi.CONFIRM_YES
        ) {

            _view.performUnlock();
        }


        return true;
    }
}