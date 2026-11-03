import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.notification as KNotifications
import org.kde.plasma.plasma5support as P5Support
import "GitHubApi.js" as GitHubApi
import "GitHubRadarApi.js" as RadarApi

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground
    preferredRepresentation: (Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                              || Plasmoid.formFactor === PlasmaCore.Types.Vertical)
                             ? compactRepresentation
                             : fullRepresentation

    toolTipMainText: i18n("GitHub Radar")
    toolTipSubText: {
        var lines = [];
        if (latestPush)
            lines.push(i18n("Last push: @%1 → %2 [%3]", latestPush.actor, RadarApi.repoShortName(latestPush.repo), latestPush.branch));
        if (radarError !== "" || errorMessage !== "")
            lines.push(i18n("Offline – showing cached data"));
        else if (radarLastCheck)
            lines.push(i18n("Last check: %1", Qt.formatTime(radarLastCheck, Locale.LongFormat)));
        return lines.join("\n");
    }

    // ---- Configuration -----------------------------------------------------
    readonly property string githubUsername: Plasmoid.configuration.githubUsername || ""
    readonly property string githubToken: Plasmoid.configuration.githubToken || ""
    readonly property color graphColor: Plasmoid.configuration.graphColor || "#40c463"
    readonly property string panelDisplayMode: Plasmoid.configuration.panelDisplayMode || "both"
    readonly property string usernamePosition: Plasmoid.configuration.usernamePosition || "right"
    readonly property bool needsSetup: githubUsername === "" || githubToken === ""
    readonly property bool showRefreshButton: Plasmoid.configuration.showRefreshButton
    // Days of history to fetch for the popup (GitHubApi clamps it to 7..365).
    readonly property int popupDays: Plasmoid.configuration.popupDays || 30
    // Background polling rate in minutes (60 or 5); never faster than 5 whatever the config says.
    readonly property int refreshIntervalMs: Math.max(5, Plasmoid.configuration.refreshIntervalMinutes || 60) * 60000

    // Radar settings
    readonly property bool radarEnabled: Plasmoid.configuration.radarEnabled
    readonly property bool radarMyReposOnly: Plasmoid.configuration.radarMyReposOnly
    readonly property bool radarManualOnly: Plasmoid.configuration.radarManualOnly
    readonly property int radarBaseSeconds: Math.max(5, Plasmoid.configuration.radarPollSeconds || 20)
    readonly property int radarActiveSeconds: Math.max(5, Plasmoid.configuration.radarActivePollSeconds || 10)
    readonly property int radarMaxSeconds: Math.max(5, Plasmoid.configuration.radarMaxPollSeconds || 60)
    readonly property bool radarShowInPanel: Plasmoid.configuration.radarShowInPanel
    readonly property int radarPanelMaxChars: Math.max(10, Plasmoid.configuration.radarPanelMaxChars || 35)
    readonly property string radarIcon: Plasmoid.configuration.radarIcon || "vcs-normal"
    readonly property bool radarNotify: Plasmoid.configuration.radarNotify
    readonly property bool radarSound: Plasmoid.configuration.radarSound
    readonly property string radarSoundFile: Plasmoid.configuration.radarSoundFile || ""

    // ---- State ---------------------------------------------------------------
    property var contributionDays: []       // last `popupDays` days, oldest first
    readonly property var contributions7Days: contributionDays.slice(-7)
    readonly property var stats: GitHubApi.calculateStats(contributionDays)

    property string errorMessage: ""
    property bool isLoading: false
    property bool notificationSentToday: false
    property var activeRequest: null

    // The in-memory contributionDays acts as the cache; these track how fresh it is.
    property var lastUpdated: null          // Date of the last successful fetch
    property real lastSuccessTime: 0        // same moment, in ms since epoch

    // Radar state. radarEvents is newest first and doubles as the offline cache.
    property var radarEvents: []
    property var radarSeen: []              // ids of pushes already handled
    property var radarEtags: ({})
    property bool radarStartup: true        // first successful poll never notifies
    property bool radarLoading: false
    property string radarError: ""
    property var radarLastCheck: null
    property var radarLastSuccess: null
    property int radarInterval: radarBaseSeconds
    property var radarRequest: null
    property bool radarManualCheck: false
    readonly property var latestPush: radarEvents.length > 0 ? radarEvents[0] : null

    // Panel text sequence after a new push: 0 = "[branch] message", 1 = repo, 2 = actor, 3 = "Up to date"
    property int panelPhase: 2

    readonly property int requestTimeoutMs: 15000
    readonly property int cooldownMs: 60000 // min. time between manual refreshes that hit GitHub
    readonly property int streakWarningHour: 20

    // ---- Notification ----------------------------------------------------------
    KNotifications.Notification {
        id: streakNotification
        eventId: "notification"
        title: i18n("GitHub Streak Saver")
        text: i18n("Warning: Your GitHub streak is at risk! 0 contributions today.")
        iconName: "dialog-warning"
    }

    function checkStreakSaver() {
        if (contributionDays.length === 0)
            return;

        var todayData = contributionDays[contributionDays.length - 1];
        var hour = new Date().getHours();

        if (hour < streakWarningHour)
            notificationSentToday = false;

        if (hour >= streakWarningHour && todayData.contributionCount === 0 && !notificationSentToday) {
            streakNotification.sendEvent();
            notificationSentToday = true;
        }
    }

    // ---- Data loading ------------------------------------------------------------
    function describeError(result) {
        switch (result.errorCode) {
        case "missing_credentials":
            return i18n("GitHub credentials missing or invalid. Please configure the widget.");
        case "unauthorized":
            return i18n("Invalid or expired GitHub token.");
        case "user_not_found":
            return i18n("GitHub user \"%1\" was not found.", githubUsername);
        case "rate_limited":
            return i18n("GitHub refused the request (rate limit or insufficient token permissions).");
        case "network":
            return i18n("Could not reach GitHub. Check your internet connection.");
        case "server":
            return i18n("GitHub is having problems right now. Try again later.");
        case "parse":
            return i18n("GitHub returned an unreadable response.");
        default:
            return result.error;
        }
    }

    function cancelRequest() {
        requestTimeout.stop();
        if (activeRequest) {
            activeRequest.abort();
            activeRequest = null;
        }
        isLoading = false;
    }

    function handleResult(result) {
        requestTimeout.stop();
        activeRequest = null;
        isLoading = false;

        if (result.errorCode) {
            errorMessage = describeError(result);
            return;
        }

        errorMessage = "";
        contributionDays = result.data;
        lastUpdated = new Date();
        lastSuccessTime = lastUpdated.getTime();
        saveContributionCache();
        checkStreakSaver();
    }

    // ---- Offline cache ---------------------------------------------------------
    // The last successful downloads are kept in the widget's config, so with no
    // internet the widget still shows the most recent data it ever got.
    function saveContributionCache() {
        try {
            Plasmoid.configuration.cachedContributions = JSON.stringify({
                u: githubUsername, t: lastSuccessTime, d: RadarApi.packDays(contributionDays)
            });
        } catch (e) {
            console.warn("GitHub Radar: could not save contribution cache", e);
        }
    }

    function saveRadarCache() {
        try {
            Plasmoid.configuration.cachedRadar = JSON.stringify({
                u: githubUsername,
                t: radarLastSuccess ? radarLastSuccess.getTime() : 0,
                e: radarEvents,
                s: radarSeen
            });
        } catch (e) {
            console.warn("GitHub Radar: could not save radar cache", e);
        }
    }

    function loadCaches() {
        if (needsSetup)
            return;
        try {
            var c = JSON.parse(Plasmoid.configuration.cachedContributions || "null");
            if (c && c.u === githubUsername && c.d && c.d.length > 0) {
                contributionDays = RadarApi.unpackDays(c.d);
                lastSuccessTime = 0;            // stale: never blocks a refresh
                lastUpdated = new Date(c.t);
            }
        } catch (e) {
            console.warn("GitHub Radar: bad contribution cache", e);
        }
        try {
            var r = JSON.parse(Plasmoid.configuration.cachedRadar || "null");
            if (r && r.u === githubUsername) {
                radarEvents = r.e || [];
                radarSeen = r.s || [];
                radarLastSuccess = r.t ? new Date(r.t) : null;
            }
        } catch (e) {
            console.warn("GitHub Radar: bad radar cache", e);
        }
    }

    function loadData() {
        cancelRequest();

        if (needsSetup) {
            errorMessage = describeError({ errorCode: "missing_credentials" });
            contributionDays = [];
            radarEvents = [];
            return;
        }

        isLoading = true;
        errorMessage = "";
        requestTimeout.restart();
        activeRequest = GitHubApi.fetchContributions(githubUsername, githubToken, popupDays, handleResult);
    }

    // Manual refresh. While the cache is fresh (last fetch succeeded less than
    // cooldownMs ago) the cached data is kept and no request is sent, so
    // spamming the button cannot burn through GitHub's rate limit. After an
    // error the cache is not trusted, so retrying is always allowed.
    // Timer refreshes and config changes call loadData() directly and are not throttled.
    function refresh() {
        if (isLoading)
            return;

        var cacheIsFresh = errorMessage === "" && lastSuccessTime > 0
                           && Date.now() - lastSuccessTime < cooldownMs;
        if (!cacheIsFresh)
            loadData();
    }

    // ---- Radar -------------------------------------------------------------------
    function resetRadarState() {
        cancelRadar();
        radarEvents = [];
        radarSeen = [];
        radarEtags = ({});
        radarStartup = true;
        radarError = "";
        radarLastSuccess = null;
        radarInterval = radarBaseSeconds;
        panelPhase = 2;
    }

    function cancelRadar() {
        radarTimeout.stop();
        if (radarRequest) {
            radarRequest.abort();
            radarRequest = null;
        }
        radarLoading = false;
    }

    function scheduleRadar() {
        radarTimer.stop();
        if (radarEnabled && !needsSetup && !radarManualOnly) {
            radarTimer.interval = radarInterval * 1000;
            radarTimer.restart();
        }
    }

    function pollRadar(manual) {
        if (!radarEnabled || needsSetup || radarLoading)
            return;
        radarTimer.stop();
        radarLoading = true;
        radarManualCheck = manual === true;
        radarTimeout.restart();
        radarRequest = RadarApi.pollEvents(githubUsername, githubToken, radarEtags, handleRadarPoll);
    }

    function radarFailed(result) {
        radarTimeout.stop();
        radarRequest = null;
        radarLoading = false;
        radarLastCheck = new Date();
        radarError = describeError(result);     // cached events stay untouched
        scheduleRadar();
    }

    function handleRadarPoll(result) {
        radarRequest = null;
        if (result.errorCode) {
            radarFailed(result);
            return;
        }

        radarEtags = result.etags;
        radarLastCheck = new Date();
        radarLastSuccess = radarLastCheck;
        radarError = "";

        var wasStartup = radarStartup;
        var fresh = [];
        var seen = radarSeen.slice();
        var incoming = result.pushes.slice().sort(function(a, b) {
            return a.createdAt < b.createdAt ? -1 : (a.createdAt > b.createdAt ? 1 : 0);
        });

        for (var i = 0; i < incoming.length; i++) {
            var p = incoming[i];
            if (seen.indexOf(p.id) !== -1)
                continue;
            seen.push(p.id);
            if (radarMyReposOnly && RadarApi.repoOwner(p.repo).toLowerCase() !== githubUsername.toLowerCase())
                continue;
            fresh.push(p);
        }
        radarSeen = seen.slice(-300);
        fresh = fresh.slice(-10);

        // The events API no longer always includes commits, so look up missing messages.
        resolveMessages(fresh, 0, function() { finishRadarPoll(fresh, wasStartup); });
    }

    function resolveMessages(list, index, done) {
        while (index < list.length && list[index].message !== "")
            index++;
        if (index >= list.length) {
            done();
            return;
        }
        radarTimeout.restart();
        radarRequest = RadarApi.fetchCommitMessage(list[index].repo, list[index].sha, githubToken, function(message) {
            radarRequest = null;
            list[index].message = message || i18n("New update");
            resolveMessages(list, index + 1, done);
        });
    }

    function finishRadarPoll(fresh, wasStartup) {
        radarTimeout.stop();
        radarRequest = null;
        radarLoading = false;
        radarStartup = false;

        if (fresh.length > 0) {
            radarEvents = RadarApi.mergePushes(radarEvents, fresh, 30);
            radarInterval = Math.min(radarActiveSeconds, radarMaxSeconds);
            if (!wasStartup) {
                startPanelSequence(0);
                if (radarNotify)
                    fresh.forEach(function(p) { notifyPush(p); });
                if (radarSound)
                    playSound();
            }
        } else {
            radarInterval = Math.min(radarMaxSeconds, radarInterval + 5);
            if (radarManualCheck && !wasStartup)
                startPanelSequence(3);
        }

        saveRadarCache();
        scheduleRadar();
    }

    // ---- Panel text ----------------------------------------------------------------
    function startPanelSequence(phase) {
        panelPhase = phase;
        panelTimer.interval = phase === 3 ? 2000 : 3000;
        panelTimer.restart();
    }

    function shorten(text, max) {
        return text.length > max ? text.substring(0, max) + ".." : text;
    }

    readonly property string panelRadarText: {
        if (!latestPush)
            return "";
        switch (panelPhase) {
        case 0: return shorten("[" + latestPush.branch + "] " + latestPush.message, radarPanelMaxChars);
        case 1: return RadarApi.repoShortName(latestPush.repo);
        case 3: return i18n("Up to date");
        default: return latestPush.actor;
        }
    }

    Timer {
        id: panelTimer
        onTriggered: {
            if (root.panelPhase === 0) {
                root.panelPhase = 1;
                restart();
            } else if (root.panelPhase === 1 || root.panelPhase === 3) {
                root.panelPhase = 2;
            }
        }
    }

    Timer {
        id: radarTimer
        repeat: false
        onTriggered: root.pollRadar(false)
    }

    Timer {
        id: radarTimeout
        interval: root.requestTimeoutMs
        onTriggered: {
            root.cancelRadar();
            root.radarError = i18n("The request to GitHub timed out. Will retry on the next refresh.");
            root.scheduleRadar();
        }
    }

    // ---- Notification + sound ---------------------------------------------------------
    Component {
        id: pushNotificationComponent

        KNotifications.Notification {
            id: pushNotification

            property var push

            componentName: "plasma_workspace"
            eventId: "notification"
            title: push.count > 1
                ? i18n("@%1 pushed %2 commits", push.actor, push.count)
                : i18n("New Push by @%1", push.actor)
            text: i18n("Repo: %1\nBranch: %2\nMsg: %3", RadarApi.repoShortName(push.repo), push.branch, push.message)
            iconName: root.radarIcon

            actions: [
                KNotifications.Action {
                    label: i18n("Open Repo")
                    onActivated: Qt.openUrlExternally(RadarApi.repoUrl(pushNotification.push))
                },
                KNotifications.Action {
                    label: i18n("User Profile")
                    onActivated: Qt.openUrlExternally(RadarApi.actorUrl(pushNotification.push))
                },
                KNotifications.Action {
                    label: i18n("View Branch")
                    onActivated: Qt.openUrlExternally(RadarApi.branchUrl(pushNotification.push))
                },
                KNotifications.Action {
                    label: i18n("View Commit")
                    onActivated: Qt.openUrlExternally(RadarApi.commitUrl(pushNotification.push))
                }
            ]

            onClosed: destroy(1000)
        }
    }

    function notifyPush(push) {
        var n = pushNotificationComponent.createObject(root, { push: push });
        if (n)
            n.sendEvent();
    }

    P5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
    }

    function shellQuote(text) {
        return text.replace(/(["\\$`])/g, "\\$1");
    }

    function playSound() {
        var file = radarSoundFile.trim();
        if (file.indexOf("file://") === 0)
            file = decodeURIComponent(file.substring(7));

        var fallback = "canberra-gtk-play -i message-new-instant"
                     + " || paplay /usr/share/sounds/freedesktop/stereo/message-new-instant.oga";
        var cmd = fallback;
        if (file !== "") {
            var home = file === "~" || file.indexOf("~/") === 0;
            var path = '"' + (home ? "$HOME" + shellQuote(file.substring(1)) : shellQuote(file)) + '"';
            cmd = "if [ -f " + path + " ]; then (mpv --no-terminal --no-video --really-quiet " + path
                + " || paplay " + path + " || ffplay -nodisp -autoexit -loglevel quiet " + path
                + "); else " + fallback + "; fi";
        }
        // The trailing comment keeps every source string unique so it always runs.
        shell.connectSource(cmd + " # " + Date.now());
    }

    function refreshAll() {
        refresh();
        pollRadar(true);
    }

    Timer {
        id: requestTimeout
        interval: root.requestTimeoutMs
        onTriggered: {
            root.cancelRequest();
            root.errorMessage = i18n("The request to GitHub timed out. Will retry on the next refresh.");
        }
    }

    Timer {
        interval: root.refreshIntervalMs
        running: true
        repeat: true
        onTriggered: root.loadData()
    }

    Component.onCompleted: {
        loadCaches();
        loadData();
        pollRadar(false);
    }

    // callLater coalesces username + token changes into a single request.
    Connections {
        target: Plasmoid.configuration
        function onGithubUsernameChanged() { Qt.callLater(root.credentialsChanged) }
        function onGithubTokenChanged() { Qt.callLater(root.credentialsChanged) }
        function onPopupDaysChanged() { Qt.callLater(root.loadData) }
        function onRadarEnabledChanged() { Qt.callLater(root.radarSettingsChanged) }
        function onRadarMyReposOnlyChanged() { Qt.callLater(root.radarSettingsChanged) }
        function onRadarManualOnlyChanged() { Qt.callLater(root.radarSettingsChanged) }
        function onRadarPollSecondsChanged() { Qt.callLater(root.radarSettingsChanged) }
    }

    function credentialsChanged() {
        resetRadarState();
        loadData();
        pollRadar(false);
    }

    function radarSettingsChanged() {
        radarInterval = radarBaseSeconds;
        if (!radarEnabled) {
            cancelRadar();
            radarTimer.stop();
        } else {
            // A changed repo filter must not hide pushes that were skipped earlier.
            pollRadar(false);
            scheduleRadar();
        }
    }

    // ---- Representations -----------------------------------------------------------
    compactRepresentation: CompactRepresentation {
        contributions: root.contributions7Days
        username: root.githubUsername
        baseColor: root.graphColor
        displayMode: root.panelDisplayMode
        usernamePosition: root.usernamePosition
        hasError: root.errorMessage !== "" && root.contributionDays.length === 0
        warning: root.errorMessage !== "" || root.radarError !== ""
        radarVisible: root.radarEnabled && root.radarShowInPanel
        radarIconName: root.radarIcon
        radarText: root.panelRadarText
        onClicked: root.expanded = !root.expanded
        onMiddleClicked: root.refreshAll()
    }

    fullRepresentation: FullRepresentation {
        username: root.githubUsername
        contributions: root.contributionDays
        baseColor: root.graphColor
        isLoading: root.isLoading
        errorMessage: root.errorMessage
        needsSetup: root.needsSetup
        totalContributions: root.stats.total
        currentStreak: root.stats.current
        longestStreak: root.stats.longest
        showRefreshButton: root.showRefreshButton
        lastUpdated: root.lastUpdated
        radarEnabled: root.radarEnabled
        radarEvents: root.radarEvents
        radarLoading: root.radarLoading
        radarError: root.radarError
        radarLastCheck: root.radarLastCheck
        radarLastSuccess: root.radarLastSuccess
        onRefreshRequested: root.refreshAll()
    }
}
