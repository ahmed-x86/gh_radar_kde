.pragma library

// GitHub GraphQL client for the contributions widget.
//
// fetchContributions() never throws and always reports through the callback
// exactly once, with either
//     { data: [ { date, contributionCount, weekday }, ... ] }
// or  { errorCode: "<code>", error: "<English fallback message>" }
// so the UI can translate known codes with i18n() and fall back to `error`.
//
// QML's XMLHttpRequest has no reliable `timeout` support, so the caller is
// expected to enforce a timeout and call abort() on the returned handle.

var ENDPOINT = "https://api.github.com/graphql";

// Bounds for the requested window. GitHub rejects contributionsCollection
// ranges longer than one year, hence the 365-day ceiling.
var MIN_WINDOW_DAYS = 7;
var MAX_WINDOW_DAYS = 365;
var DEFAULT_WINDOW_DAYS = 30;

var QUERY = "query($user: String!, $from: DateTime!, $to: DateTime!) {"
          + "  user(login: $user) {"
          + "    contributionsCollection(from: $from, to: $to) {"
          + "      contributionCalendar {"
          + "        weeks { contributionDays { date contributionCount weekday } }"
          + "      }"
          + "    }"
          + "  }"
          + "}";

function failure(code, message) {
    return { errorCode: code, error: message };
}

function isoDate(date) {
    return date.toISOString().split("T")[0];
}

// Coerce whatever the config hands us into an integer within the allowed bounds.
function normalizeWindowDays(value) {
    var days = Math.floor(Number(value));
    if (isNaN(days))
        days = DEFAULT_WINDOW_DAYS;
    return Math.max(MIN_WINDOW_DAYS, Math.min(MAX_WINDOW_DAYS, days));
}

// Inclusive [from, to] window of exactly `windowDays` days, as YYYY-MM-DD
// strings (UTC, like GitHub's calendar). Today counts as the last day, so a
// 365-day window spans less than a year and is accepted by GitHub.
function buildRange(windowDays) {
    var days = normalizeWindowDays(windowDays);
    var today = new Date();
    var from = new Date(today.getTime());
    from.setUTCDate(today.getUTCDate() - (days - 1));
    return { from: isoDate(from), to: isoDate(today) };
}

function describeHttpFailure(status, statusText) {
    if (status === 0)
        return failure("network", "Network error: could not reach GitHub.");
    if (status === 401)
        return failure("unauthorized", "Invalid or expired GitHub Token.");
    if (status === 403 || status === 429)
        return failure("rate_limited", "GitHub refused the request (rate limit or insufficient token permissions).");
    if (status >= 500)
        return failure("server", "GitHub is having problems (HTTP " + status + "). Try again later.");
    return failure("http", "HTTP Error: " + status + " " + statusText);
}

// Flatten GitHub's week/day structure and drop the padding days that GitHub
// adds to complete the first and last week.
function flattenDays(weeks, range) {
    var days = [];
    for (var i = 0; i < weeks.length; i++) {
        var weekDays = weeks[i].contributionDays || [];
        for (var j = 0; j < weekDays.length; j++) {
            var day = weekDays[j];
            // ISO dates compare correctly as plain strings.
            if (day.date >= range.from && day.date <= range.to)
                days.push(day);
        }
    }
    return days;
}

function parseResponse(responseText, range) {
    var response;
    try {
        response = JSON.parse(responseText);
    } catch (e) {
        return failure("parse", "GitHub returned an unreadable response.");
    }

    if (response.errors && response.errors.length > 0) {
        var first = response.errors[0];
        if (first.type === "NOT_FOUND")
            return failure("user_not_found", first.message);
        return failure("graphql", first.message);
    }

    var user = response.data && response.data.user;
    if (!user)
        return failure("user_not_found", "GitHub user not found.");

    var weeks = user.contributionsCollection.contributionCalendar.weeks;
    return { data: flattenDays(weeks, range) };
}

// Returns { abort() }. Calling abort() guarantees the callback will not fire.
// `windowDays` is the number of days to fetch, today included (7..365).
function fetchContributions(username, token, windowDays, callback) {
    var finished = false;
    var xhr = null;

    function finish(result) {
        if (finished)
            return;
        finished = true;
        callback(result);
    }

    var handle = {
        abort: function() {
            finished = true;
            if (xhr)
                xhr.abort();
        }
    };

    if (!username || !token) {
        finish(failure("missing_credentials", "Missing GitHub Username or Token."));
        return handle;
    }

    var range = buildRange(windowDays);
    var body = JSON.stringify({
        query: QUERY,
        variables: {
            user: username,
            from: range.from + "T00:00:00Z",
            to: range.to + "T23:59:59Z"
        }
    });

    xhr = new XMLHttpRequest();
    xhr.open("POST", ENDPOINT);
    xhr.setRequestHeader("Authorization", "Bearer " + token);
    xhr.setRequestHeader("Content-Type", "application/json");

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;

        if (xhr.status === 200)
            finish(parseResponse(xhr.responseText, range));
        else
            finish(describeHttpFailure(xhr.status, xhr.statusText));
    };

    try {
        xhr.send(body);
    } catch (e) {
        finish(failure("network", "Network error: " + e));
    }

    return handle;
}

// Total contributions plus current/longest streak over the given days.
// Works on any array length, so it follows the configured window; streaks
// can therefore never be longer than that window.
function calculateStats(days) {
    var total = 0;
    var current = 0;
    var longest = 0;

    for (var i = 0; i < days.length; i++) {
        var count = days[i].contributionCount;
        total += count;
        if (count > 0) {
            current++;
            if (current > longest)
                longest = current;
        } else {
            current = 0;
        }
    }

    return { total: total, current: current, longest: longest };
}
