import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// One square of the contribution graph. Used by both the panel (compact,
// non-interactive) and the popup (interactive, with a tooltip).
Rectangle {
    id: cell

    property int count: 0
    property string date: ""          // YYYY-MM-DD
    property color baseColor: "#40c463"
    property bool hasError: false
    property bool interactive: false

    signal activated()

    readonly property real shadeAlpha: {
        if (count >= 10) return 1.0;
        if (count >= 7) return 0.8;
        if (count >= 4) return 0.6;
        return 0.4;
    }

    readonly property color shade: count <= 0
        ? Qt.alpha(Kirigami.Theme.textColor, 0.05)
        : Qt.alpha(baseColor, shadeAlpha)

    // Parsed manually: new Date("YYYY-MM-DD") is UTC and can shift a day locally.
    readonly property string dateLabel: {
        var parts = date.split("-");
        if (parts.length !== 3)
            return date;
        var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        return Qt.formatDate(d, Qt.locale().dateFormat(Locale.LongFormat));
    }

    radius: Math.round(Math.min(width, height) * 0.2)
    color: hasError ? Kirigami.Theme.negativeTextColor : shade

    border.width: interactive && mouseArea.containsMouse ? 1 : 0
    border.color: Kirigami.Theme.highlightColor

    Behavior on color {
        ColorAnimation { duration: Kirigami.Units.shortDuration }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: cell.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cell.activated()
    }

    QQC2.ToolTip {
        id: tooltip

        visible: cell.interactive && mouseArea.containsMouse
        delay: Kirigami.Units.toolTipDelay
        padding: Kirigami.Units.largeSpacing

        background: Rectangle {
            Kirigami.Theme.colorSet: Kirigami.Theme.Tooltip
            Kirigami.Theme.inherit: false
            color: Kirigami.Theme.backgroundColor
            radius: Math.round(Kirigami.Units.smallSpacing * 1.5)
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
        }

        contentItem: ColumnLayout {
            Kirigami.Theme.colorSet: Kirigami.Theme.Tooltip
            Kirigami.Theme.inherit: false
            spacing: Kirigami.Units.smallSpacing / 2

            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 0.6
                    Layout.preferredHeight: Layout.preferredWidth
                    Layout.alignment: Qt.AlignVCenter
                    radius: 2
                    color: cell.shade
                }

                QQC2.Label {
                    text: cell.count === 0
                        ? i18n("No contributions")
                        : i18np("%1 contribution", "%1 contributions", cell.count)
                    font.bold: true
                    color: Kirigami.Theme.textColor
                }
            }

            QQC2.Label {
                text: cell.dateLabel
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
        }
    }
}
