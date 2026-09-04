using Toybox.WatchUi;

class TedeeDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {
        WatchUi.getActiveView().refresh();
        return true;
    }

    function onNextPage() {
        WatchUi.getActiveView().unlock();
        return true;
    }

    function onPreviousPage() {
        WatchUi.getActiveView().lock();
        return true;
    }
}
