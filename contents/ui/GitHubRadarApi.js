.pragma library

// GitHub REST "events" client for the activity radar (port of github_radar.py).
//
// Everything reports through a callback exactly once, either with a result
// object or with { errorCode, error } (same codes as GitHubApi.js), and
// returns a handle whose abort() guarantees the callback never fires.

var API = "https://api.github.com";

function failure(code, message) {
    return { errorCode: code, error: message };
}

function describeHttpFailure(status, statusText) {
    if (status === 0)
        return failure("network", "Network error: could not reach GitHub.");
    if (status === 401)
        return failure("unauthorized", "Invalid or expired GitHub Token.");
    if (status === 404)
        return failure("user_not_found", "GitHub user not found.");
    if (status === 403 || status === 429)
        return failure("rate_limited", "GitHub refused the request (rate limit or insufficient token permissions).");
    if (status >= 500)
        return failure("server", "GitHub is having problems (HTTP " + status + "). Try again later.");
    return failure("http", "HTTP Error: " + status + " " + statusText);
}

// GET with optional ETag. cb(result) where result is
//   { status: 200, etag, data } | { status: 304 } | { errorCode, error }
function getJson(url, token, etag, callback) {
    var finished = false;
    var xhr = new XMLHttpRequest();

    function finish(result) {
        if (finished)
            return;
        finished = true;
        callback(result);
    }

    var handle = {
        abort: function() {
            finished = true;
            xhr.abort();
        }
    };

    xhr.open("GET", url);
    xhr.setRequestHeader("Authorization", "Bearer " + token);
    xhr.setRequestHeader("Accept", "application/vnd.github+json");
    if (etag)
        xhr.setRequestHeader("If-None-Match", etag);

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;

        if (xhr.status === 304) {
            finish({ status: 304 });
        } else if (xhr.status === 200) {
            var data;
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {
                finish(failure("parse", "GitHub returned an unreadable response."));
                return;
            }
            finish({ status: 200, etag: xhr.getResponseHeader("ETag") || "", data: data });
        } else {
            finish(describeHttpFailure(xhr.status, xhr.statusText));
        }
    };

    try {
        xhr.send();
    } catch (e) {
        finish(failure("network", "Network error: " + e));
    }
    return handle;
}

// Reduce a PushEvent to the few fields the widget needs (small enough to cache).
function normalizePush(ev) {
    var p = ev.payload || {};
    var commits = p.commits || [];
    var first = commits.length > 0 ? commits[0] : null;
    var actor = ev.actor || {};
    return {
        id: String(ev.id),
        createdAt: ev.created_at || "",
        repo: ev.repo.name,                                  // owner/name
        actor: actor.display_login || actor.login || "?",
        avatar: actor.avatar_url || "",
        branch: (p.ref || "").replace("refs/heads/", ""),
        count: commits.length || p.size || p.distinct_size || 1,
        sha: first ? first.sha : (p.head || ""),
        message: first && first.message ? first.message.split("\n")[0] : ""
    };
}

// Fetches the user's own events and received events (conditional requests
// via `etags`, a { url: etag } map). Result:
//   { pushes: [normalized...], etags: {...}, unchanged: bool }
function pollEvents(username, token, etags, callback) {
    var urls = [
        API + "/users/" + encodeURIComponent(username) + "/events",
        API + "/users/" + encodeURIComponent(username) + "/received_events"
    ];
    var pending = urls.length;
    var results = [];
    var handles = [];
    var failed = false;
    var newEtags = {};
    for (var k in etags)
        newEtags[k] = etags[k];

    function done() {
        var pushes = [];
        var changed = false;
        for (var i = 0; i < results.length; i++) {
            var r = results[i];
            if (r.status !== 200)
                continue;
            changed = true;
            newEtags[urls[i]] = r.etag;
            for (var j = 0; j < r.data.length; j++) {
                if (r.data[j].type === "PushEvent")
                    pushes.push(normalizePush(r.data[j]));
            }
        }
        callback({ pushes: pushes, etags: newEtags, unchanged: !changed });
    }

    urls.forEach(function(url, i) {
        handles.push(getJson(url, token, etags[url], function(result) {
            if (failed)
                return;
            if (result.errorCode) {
                failed = true;
                handles.forEach(function(h) { h.abort(); });
                callback(result);
                return;
            }
            results[i] = result;
            if (--pending === 0)
                done();
        }));
    });

    return {
        abort: function() {
            failed = true;
            handles.forEach(function(h) { h.abort(); });
        }
    };
}

// First line of a commit's message, or "" on any failure.
function fetchCommitMessage(repo, sha, token, callback) {
    return getJson(API + "/repos/" + repo + "/commits/" + sha, token, "", function(result) {
        if (result.errorCode || !result.data || !result.data.commit)
            callback("");
        else
            callback((result.data.commit.message || "").split("\n")[0]);
    });
}

function repoShortName(repo) {
    return repo.split("/").pop();
}

function repoOwner(repo) {
    return repo.split("/")[0];
}

function repoUrl(p) { return "https://github.com/" + p.repo; }
function actorUrl(p) { return "https://github.com/" + p.actor; }
function branchUrl(p) { return p.branch ? "https://github.com/" + p.repo + "/tree/" + p.branch : repoUrl(p); }
function commitUrl(p) { return p.sha ? "https://github.com/" + p.repo + "/commit/" + p.sha : repoUrl(p); }

// Merge new pushes into an existing newest-first list (deduplicated, capped).
function mergePushes(existing, fresh, limit) {
    var byId = {};
    var all = [];
    fresh.concat(existing).forEach(function(p) {
        if (!byId[p.id]) {
            byId[p.id] = true;
            all.push(p);
        }
    });
    all.sort(function(a, b) { return a.createdAt < b.createdAt ? 1 : (a.createdAt > b.createdAt ? -1 : 0); });
    return all.slice(0, limit);
}

// Contribution cache helpers: [[date, count], ...] <-> GitHub day objects.
function packDays(days) {
    return days.map(function(d) { return [d.date, d.contributionCount]; });
}

function unpackDays(packed) {
    return packed.map(function(row) {
        var parts = row[0].split("-");
        var weekday = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])).getDay();
        return { date: row[0], contributionCount: row[1], weekday: weekday };
    });
}
