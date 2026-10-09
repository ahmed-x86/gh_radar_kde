import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Popup / desktop representation: header, 30-day grid and summary stats.
Item {
    id: full

    property string username: ""
    property var contributions: []          // last 30 days, oldest first
    property color baseColor: "#40c463"
    property bool isLoading: false
    property string errorMessage: ""
    property bool needsSetup: false
    property int totalContributions: 0
    property int currentStreak: 0
    property int longestStreak: 0

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

            Item {
                id: gridArea

                Layout.fillWidth: true
                Layout.fillHeight: true

                readonly property int cellSpacing: Kirigami.Units.smallSpacing

                // Empty cells before the first day so rows line up with weekdays.
                readonly property int leadingPadding: full.contributions.length > 0
                    ? full.contributions[0].weekday : 0
                readonly property int columnCount: Math.max(1,
                    Math.ceil((leadingPadding + full.contributions.length) / 7))

                // Largest square that fits both dimensions, within sane bounds.
                readonly property int cellSize: Math.max(
                    Math.round(Kirigami.Units.gridUnit / 2),
                    Math.floor(Math.min(
                        (width - (columnCount - 1) * cellSpacing) / columnCount,
                        (height - 6 * cellSpacing) / 7,
                        Kirigami.Units.gridUnit * 1.6)))

                GridLayout {
                    id: grid

                    anchors.centerIn: parent
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

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                uniformCellSizes: true

                StatCard {
                    Layout.fillWidth: true
                    value: String(full.totalContributions)
                    label: i18n("Total (30d)")
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
