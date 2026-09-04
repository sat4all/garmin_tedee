module TedeeConfig {

    const BASE_URL =
        "https://homeie.hopto.org:9443";

    const WATCH_TOKEN =
        "rafaltedee";

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

        return names[state] != null
            ? names[state]
            : "State " + state;
    }
}