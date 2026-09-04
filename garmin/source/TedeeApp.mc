using Toybox.Application;
using Toybox.WatchUi;

class TedeeApp extends AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [ new TedeeView(), new TedeeDelegate() ];
    }
}
