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

    signal refreshRequested()

    readonly property bool hasError: errorMessage !== ""

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 15
    Layout.preferredWidth: Kirigami.Units.gridUnit * 20
    Layout.preferredHeight: Kirigami.Units.gridUnit * 16

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
                running: full.isLoading
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            QQC2.ToolButton {
                visible: full.showRefreshButton
                enabled: !full.isLoading
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

        // ---- Empty / error state -------------------------------------------
        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: full.hasError
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
            visible: !full.hasError
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
    }
}
