using Toybox.Application;
using Toybox.WatchUi;
using Toybox.Communications;

class TedeeApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }


    function onStart(state) {
    }


    function onStop(state) {
    }


    function getInitialView() {

        var view =
            new TedeeView();

        var delegate =
            new TedeeDelegate(view);

        return [
            view,
            delegate
        ];
    }


    // IMPORTANT:
    //
    // Do NOT add:
    //
    // as Communications.SyncDelegate
    //
    // Your SDK rejected that override return type.

    function getSyncDelegate() {

        return new TedeeSyncDelegate();
    }
}