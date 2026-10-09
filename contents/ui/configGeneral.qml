import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Bindings to main.xml (the *Default properties silence Plasma's config warnings)
    property alias cfg_githubUsername: usernameField.text
    property alias cfg_githubToken: tokenField.text
    property string cfg_graphColor
    property string cfg_panelDisplayMode
    property string cfg_usernamePosition
    property string cfg_githubUsernameDefault
    property string cfg_githubTokenDefault
    property string cfg_graphColorDefault
    property string cfg_panelDisplayModeDefault
    property string cfg_usernamePositionDefault

    readonly property var displayModes: [
        { text: i18n("Graph Only"), value: "graph" },
        { text: i18n("Username Only"), value: "username" },
        { text: i18n("Both"), value: "both" }
    ]

    readonly property var usernamePositions: [
        { text: i18n("Left of graph"), value: "left" },
        { text: i18n("Right of graph"), value: "right" }
    ]

    ColorDialog {
        id: colorDialog
        title: i18n("Choose Graph Color")
        selectedColor: page.cfg_graphColor
        onAccepted: page.cfg_graphColor = selectedColor.toString()
    }

    Kirigami.FormLayout {
        QQC2.TextField {
            id: usernameField
            Kirigami.FormData.label: i18n("GitHub Username:")
            Layout.fillWidth: true
            placeholderText: "torvalds"
        }

        QQC2.TextField {
            id: tokenField
            Kirigami.FormData.label: i18n("Personal Access Token:")
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: "ghp_..."
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Graph Color:")
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                radius: Math.round(Kirigami.Units.smallSpacing / 2)
                color: page.cfg_graphColor
                border.width: 1
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.3)
            }

            QQC2.Button {
                text: i18n("Pick Color...")
                icon.name: "color-picker"
                onClicked: colorDialog.open()
            }
        }

        QQC2.ComboBox {
            id: displayModeCombo
            Kirigami.FormData.label: i18n("Panel Display Mode:")
            Layout.fillWidth: true
            model: page.displayModes
            textRole: "text"
            valueRole: "value"
            onActivated: page.cfg_panelDisplayMode = currentValue
        }

        QQC2.ComboBox {
            id: positionCombo
            Kirigami.FormData.label: i18n("Username Position:")
            Layout.fillWidth: true
            visible: page.cfg_panelDisplayMode === "both"
            model: page.usernamePositions
            textRole: "text"
            valueRole: "value"
            onActivated: page.cfg_usernamePosition = currentValue
        }
    }

    // Select the stored values without writing anything back to the config.
    Component.onCompleted: {
        displayModeCombo.currentIndex = Math.max(0, displayModeCombo.indexOfValue(cfg_panelDisplayMode));
        positionCombo.currentIndex = Math.max(0, positionCombo.indexOfValue(cfg_usernamePosition));
    }
}
