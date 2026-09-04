using Toybox.WatchUi;

class TedeeDelegate
    extends WatchUi.BehaviorDelegate {

    var _view;


    function initialize(view) {

        BehaviorDelegate.initialize();

        _view = view;
    }


    function onNextPage() {

        _view.moveDown();

        return true;
    }


    function onPreviousPage() {

        _view.moveUp();

        return true;
    }


    function onSelect() {

        _view.selectAction();

        return true;
    }
}