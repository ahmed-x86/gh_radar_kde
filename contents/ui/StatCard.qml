import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A single statistic: big value with a small caption underneath.
ColumnLayout {
    property string value
    property string label

    spacing: 0

    Kirigami.Heading {
        level: 1
        text: parent.value
        font.weight: Font.DemiBold
        Layout.alignment: Qt.AlignHCenter
    }

    QQC2.Label {
        text: parent.label
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.disabledTextColor
        Layout.alignment: Qt.AlignHCenter
    }
}
