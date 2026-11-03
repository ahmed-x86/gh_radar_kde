import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Popup / desktop representation: header, scrollable contribution grid and summary stats.
Item {
    id: full

    property string username: ""
    property var contributions: []          // last N configured days, oldest first
    property color baseColor: "#40c463"
    property bool isLoading: false
    property string errorMessage: ""
    property bool needsSetup: false
    property int totalContributions: 0
    property int currentStreak: 0
    property int longestStreak: 0
    property bool showRefreshButton: true
    property var lastUpdated: null          // Date of the last successful fetch

    // Radar
    property bool radarEnabled: true
    property var radarEvents: []            // newest first
    property bool radarLoading: false
    property string radarError: ""
    property var radarLastCheck: null
    property var radarLastSuccess: null

    signal refreshRequested()

    readonly property bool hasError: errorMessage !== ""
    readonly property bool hasData: contributions.length > 0
    // An error only replaces the view when there is no cached data to show instead.
    readonly property bool blocked: hasError && !hasData

    function timeAgo(iso) {
        var secs = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 1000));
        if (secs < 60) return i18n("just now");
        var mins = Math.floor(secs / 60);
        if (mins < 60) return i18n("%1m ago", mins);
        var hours = Math.floor(mins / 60);
        if (hours < 24) return i18n("%1h ago", hours);
        return i18n("%1d ago", Math.floor(hours / 24));
    }

    function repoName(repo) {
        return repo.split("/").pop();
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredHeight: Kirigami.Units.gridUnit * 18

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        // ---- Header -------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "vcs-normal"
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            Kirigami.Heading {
                level: 2
                text: full.username !== ""
                    ? i18n("%1's GitHub Activity", full.username)
                    : i18n("GitHub Activity")
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            QQC2.BusyIndicator {
                running: full.isLoading || full.radarLoading
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            QQC2.ToolButton {
                visible: full.showRefreshButton
                enabled: !full.isLoading && !full.radarLoading
                icon.name: "view-refresh"
                display: QQC2.AbstractButton.IconOnly
                onClicked: full.refreshRequested()

                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.text: full.lastUpdated
                    ? i18n("Refresh (last updated at %1)", Qt.formatTime(full.lastUpdated, Locale.ShortFormat))
                    : i18n("Refresh")
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // ---- Cached-data banner --------------------------------------------
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: (full.hasError || full.radarError !== "") && !full.needsSetup && (full.hasData || full.radarEvents.length > 0)
            type: Kirigami.MessageType.Warning
            text: full.lastUpdated
                ? i18n("Showing cached data from %1. %2", Qt.formatDateTime(full.lastUpdated, Locale.ShortFormat),
                       full.hasError ? full.errorMessage : full.radarError)
                : (full.hasError ? full.errorMessage : full.radarError)
        }

        QQC2.TabBar {
            id: tabs
            Layout.fillWidth: true
            visible: full.radarEnabled && !full.needsSetup
            QQC2.TabButton { text: i18n("Contributions") }
            QQC2.TabButton { text: i18n("Radar") }
        }

        // ---- Empty / error state -------------------------------------------
        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: full.blocked && (!full.radarEnabled || tabs.currentIndex === 0 || full.needsSetup)
            text: full.errorMessage
            icon.name: full.needsSetup ? "account-add" : "dialog-warning"
            explanation: full.needsSetup
                ? i18n("Please right-click the widget and select 'Configure...' to set up your account.")
                : ""
        }

        // ---- Data view -----------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !full.blocked && (!full.radarEnabled || tabs.currentIndex === 0)
            spacing: Kirigami.Units.largeSpacing

            QQC2.ScrollView {
                id: gridArea

                Layout.fillWidth: true
                Layout.fillHeight: true

                // Long ranges grow the grid sideways; only the horizontal bar is ever used.
                QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AsNeeded
                QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff

                readonly property int cellSpacing: Kirigami.Units.smallSpacing
                readonly property int minCellSize: Math.round(Kirigami.Units.gridUnit * 0.8)
                readonly property int maxCellSize: Math.round(Kirigami.Units.gridUnit * 1.6)
                // Room kept for the horizontal scroll bar when it is shown.
                readonly property int scrollBarReserve: Kirigami.Units.gridUnit

                // Empty cells before the first day so rows line up with weekdays.
                readonly property int leadingPadding: full.contributions.length > 0
                    ? full.contributions[0].weekday : 0
                readonly property int columnCount: Math.max(1,
                    Math.ceil((leadingPadding + full.contributions.length) / 7))

                // Decided from the width alone (cells at minimum size don't fit), so it
                // cannot feed back into the height budget below and cause a binding loop.
                readonly property bool needsScroll:
                    columnCount * minCellSize + (columnCount - 1) * cellSpacing > availableWidth

                readonly property real heightBudget: height - (needsScroll ? scrollBarReserve : 0)

                // Largest square that fits the view, but never below minCellSize:
                // when too many weeks are shown the grid scrolls instead of shrinking.
                readonly property int cellSize: Math.max(minCellSize, Math.floor(Math.min(
                    (availableWidth - (columnCount - 1) * cellSpacing) / columnCount,
                    (heightBudget - 6 * cellSpacing) / 7,
                    maxCellSize)))

                Flickable {
                    id: flick

                    contentWidth: Math.max(grid.implicitWidth, width)
                    contentHeight: Math.max(grid.implicitHeight, height)
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    // Newest days sit on the right; start there so older ones are a scroll away.
                    function scrollToLatest() {
                        contentX = Math.max(0, contentWidth - width);
                    }

                    onContentWidthChanged: Qt.callLater(scrollToLatest)
                    Component.onCompleted: Qt.callLater(scrollToLatest)

                    // Plain mouse wheels only scroll vertically; map them to the horizontal axis.
                    WheelHandler {
                        orientation: Qt.Vertical
                        acceptedDevices: PointerDevice.Mouse
                        onWheel: event => {
                            flick.contentX = Math.max(0, Math.min(
                                flick.contentWidth - flick.width,
                                flick.contentX - event.angleDelta.y));
                        }
                    }

                    GridLayout {
                        id: grid

                        // Centered while it fits, left-anchored (scrollable) once it overflows.
                        x: Math.max(0, Math.round((flick.width - implicitWidth) / 2))
                        y: Math.max(0, Math.round((flick.height - implicitHeight) / 2))

                        rows: 7
                        flow: GridLayout.TopToBottom
                        columnSpacing: gridArea.cellSpacing
                        rowSpacing: gridArea.cellSpacing

                        Repeater {
                            model: gridArea.leadingPadding

                            Item {
                                Layout.preferredWidth: gridArea.cellSize
                                Layout.preferredHeight: gridArea.cellSize
                            }
                        }

                        Repeater {
                            model: full.contributions

                            ContributionCell {
                                required property var modelData

                                Layout.preferredWidth: gridArea.cellSize
                                Layout.preferredHeight: gridArea.cellSize
                                count: modelData.contributionCount
                                date: modelData.date
                                baseColor: full.baseColor
                                interactive: true
                                onActivated: Qt.openUrlExternally("https://github.com/" + full.username)
                            }
                        }
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                uniformCellSizes: true

                StatCard {
                    Layout.fillWidth: true
                    value: String(full.totalContributions)
                    label: i18n("Total (%1d)", full.contributions.length)
                }

                StatCard {
                    Layout.fillWidth: true
                    value: String(full.currentStreak)
                    label: i18n("Current Streak")
                }

                StatCard {
                    Layout.fillWidth: true
                    value: String(full.longestStreak)
                    label: i18n("Longest Streak")
                }
            }
        }

        // ---- Radar tab -----------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: full.radarEnabled && !full.needsSetup && tabs.currentIndex === 1
            spacing: Kirigami.Units.smallSpacing

            Kirigami.PlaceholderMessage {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: full.radarEvents.length === 0
                icon.name: full.radarError !== "" ? "dialog-warning" : "vcs-normal"
                text: full.radarError !== "" ? full.radarError : i18n("No push activity yet")
                explanation: full.radarError === "" ? i18n("New pushes by you and the people you follow will appear here.") : ""
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: full.radarEvents.length > 0

                ListView {
                    id: radarList
                    clip: true
                    model: full.radarEvents
                    spacing: 0

                    delegate: QQC2.ItemDelegate {
                        id: row
                        required property var modelData
                        width: ListView.view.width

                        onClicked: Qt.openUrlExternally(modelData.sha
                            ? "https://github.com/" + modelData.repo + "/commit/" + modelData.sha
                            : "https://github.com/" + modelData.repo)

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Avatar {
                                source: row.modelData.avatar
                                name: row.modelData.actor
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.bold: true
                                    text: row.modelData.count > 1
                                        ? i18n("@%1 pushed %2 commits", row.modelData.actor, row.modelData.count)
                                        : i18n("@%1 pushed", row.modelData.actor)
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: row.modelData.message
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font: Kirigami.Theme.smallFont
                                    color: Kirigami.Theme.disabledTextColor
                                    text: full.repoName(row.modelData.repo) + " · " + row.modelData.branch
                                          + " · " + full.timeAgo(row.modelData.createdAt)
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "folder-open"
                                display: QQC2.AbstractButton.IconOnly
                                onClicked: Qt.openUrlExternally("https://github.com/" + row.modelData.repo)
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: i18n("Open Repo")
                            }
                            QQC2.ToolButton {
                                icon.name: "user-identity"
                                display: QQC2.AbstractButton.IconOnly
                                onClicked: Qt.openUrlExternally("https://github.com/" + row.modelData.actor)
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: i18n("User Profile")
                            }
                            QQC2.ToolButton {
                                icon.name: "vcs-branch"
                                display: QQC2.AbstractButton.IconOnly
                                visible: row.modelData.branch !== ""
                                onClicked: Qt.openUrlExternally("https://github.com/" + row.modelData.repo + "/tree/" + row.modelData.branch)
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: i18n("View Branch")
                            }
                        }
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                visible: full.radarLastCheck !== null || full.radarLastSuccess !== null
                text: full.radarError !== "" && full.radarLastSuccess
                    ? i18n("Last successful check: %1", Qt.formatDateTime(full.radarLastSuccess, Locale.ShortFormat))
                    : (full.radarLastCheck ? i18n("Last check: %1", Qt.formatTime(full.radarLastCheck, Locale.ShortFormat)) : "")
            }
        }
    }
}
