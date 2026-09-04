module TedeeConfig {
    // Set this to the HTTPS address of your Python relay.
    // Example: https://lock.example.com
    const BASE_URL = "https://YOUR-RELAY-DOMAIN.example";

    // Set this to the same WATCH_TOKEN configured on the router relay.
    const WATCH_TOKEN = "CHANGE-ME";

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
        return names[state] != null ? names[state] : "State " + state;
    }
}
