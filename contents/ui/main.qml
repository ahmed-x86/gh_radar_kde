import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.notification as KNotifications
import "GitHubApi.js" as GitHubApi

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground
    preferredRepresentation: (Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                              || Plasmoid.formFactor === PlasmaCore.Types.Vertical)
                             ? compactRepresentation
                             : fullRepresentation

    // ---- Configuration -----------------------------------------------------
    readonly property string githubUsername: Plasmoid.configuration.githubUsername || ""
    readonly property string githubToken: Plasmoid.configuration.githubToken || ""
    readonly property color graphColor: Plasmoid.configuration.graphColor || "#40c463"
    readonly property string panelDisplayMode: Plasmoid.configuration.panelDisplayMode || "both"
    readonly property string usernamePosition: Plasmoid.configuration.usernamePosition || "right"
    readonly property bool needsSetup: githubUsername === "" || githubToken === ""
    readonly property bool showRefreshButton: Plasmoid.configuration.showRefreshButton
    // Background polling rate in minutes (60 or 5); never faster than 5 whatever the config says.
    readonly property int refreshIntervalMs: Math.max(5, Plasmoid.configuration.refreshIntervalMinutes || 60) * 60000

    // ---- State ---------------------------------------------------------------
    property var contributions30Days: []
    readonly property var contributions7Days: contributions30Days.slice(-7)
    readonly property var stats: GitHubApi.calculateStats(contributions30Days)

    property string errorMessage: ""
    property bool isLoading: false
    property bool notificationSentToday: false
    property var activeRequest: null

    // The in-memory contributions30Days acts as the cache; these track how fresh it is.
    property var lastUpdated: null          // Date of the last successful fetch
    property real lastSuccessTime: 0        // same moment, in ms since epoch

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
        if (contributions30Days.length === 0)
            return;

        var todayData = contributions30Days[contributions30Days.length - 1];
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
        contributions30Days = result.data;
        lastUpdated = new Date();
        lastSuccessTime = lastUpdated.getTime();
        checkStreakSaver();
    }

    function loadData() {
        cancelRequest();

        if (needsSetup) {
            errorMessage = describeError({ errorCode: "missing_credentials" });
            contributions30Days = [];
            return;
        }

        isLoading = true;
        errorMessage = "";
        requestTimeout.restart();
        activeRequest = GitHubApi.fetchContributions(githubUsername, githubToken, handleResult);
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

    Component.onCompleted: loadData()

    // callLater coalesces username + token changes into a single request.
    Connections {
        target: Plasmoid.configuration
        function onGithubUsernameChanged() { Qt.callLater(root.loadData) }
        function onGithubTokenChanged() { Qt.callLater(root.loadData) }
    }

    // ---- Representations -----------------------------------------------------------
    compactRepresentation: CompactRepresentation {
        contributions: root.contributions7Days
        username: root.githubUsername
        baseColor: root.graphColor
        displayMode: root.panelDisplayMode
        usernamePosition: root.usernamePosition
        hasError: root.errorMessage !== ""
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: FullRepresentation {
        username: root.githubUsername
        contributions: root.contributions30Days
        baseColor: root.graphColor
        isLoading: root.isLoading
        errorMessage: root.errorMessage
        needsSetup: root.needsSetup
        totalContributions: root.stats.total
        currentStreak: root.stats.current
        longestStreak: root.stats.longest
        showRefreshButton: root.showRefreshButton
        lastUpdated: root.lastUpdated
        onRefreshRequested: root.refresh()
    }
}
