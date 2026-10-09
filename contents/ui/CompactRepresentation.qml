import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Panel representation: optional username + a 7-day strip of squares.
Item {
    id: compact

    property var contributions: []          // last 7 days
    property string username: ""
    property color baseColor: "#40c463"
    property string displayMode: "both"     // "graph" | "username" | "both"
    property string usernamePosition: "right" // "left" | "right"
    property bool hasError: false

    signal clicked()

    readonly property bool showGraph: displayMode === "graph" || displayMode === "both"
    readonly property bool showUsername: displayMode === "username" || displayMode === "both"
    readonly property bool usernameOnLeft: displayMode === "username" || usernamePosition === "left"
    readonly property int cellSize: Math.round(Kirigami.Units.iconSizes.small * 0.75)

    Layout.minimumWidth: row.implicitWidth
    Layout.minimumHeight: row.implicitHeight
    Layout.preferredWidth: row.implicitWidth
    Layout.preferredHeight: row.implicitHeight

    component UsernameLabel: QQC2.Label {
        text: compact.username
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
    }

    MouseArea {
        anchors.fill: parent
        onClicked: compact.clicked()
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        UsernameLabel {
            visible: compact.showUsername && compact.usernameOnLeft
        }

        RowLayout {
            visible: compact.showGraph
            spacing: Math.round(Kirigami.Units.smallSpacing / 2)
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: 7

                ContributionCell {
                    required property int index
                    readonly property var entry: index < compact.contributions.length
                        ? compact.contributions[index] : null

                    Layout.preferredWidth: compact.cellSize
                    Layout.preferredHeight: compact.cellSize
                    count: entry ? entry.contributionCount : 0
                    baseColor: compact.baseColor
                    hasError: compact.hasError
                }
            }
        }

        Kirigami.Icon {
            visible: compact.hasError
            source: "dialog-warning"
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            Layout.alignment: Qt.AlignVCenter
        }

        UsernameLabel {
            visible: compact.showUsername && !compact.usernameOnLeft
        }
    }
}
