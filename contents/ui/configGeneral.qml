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
    property alias cfg_showRefreshButton: refreshButtonCheck.checked
    property string cfg_graphColor
    property string cfg_panelDisplayMode
    property string cfg_usernamePosition
    property int cfg_refreshIntervalMinutes
    property string cfg_githubUsernameDefault
    property string cfg_githubTokenDefault
    property bool cfg_showRefreshButtonDefault
    property string cfg_graphColorDefault
    property string cfg_panelDisplayModeDefault
    property string cfg_usernamePositionDefault
    property int cfg_refreshIntervalMinutesDefault

    readonly property var displayModes: [
        { text: i18n("Graph Only"), value: "graph" },
        { text: i18n("Username Only"), value: "username" },
        { text: i18n("Both"), value: "both" }
    ]

    readonly property var usernamePositions: [
        { text: i18n("Left of graph"), value: "left" },
        { text: i18n("Right of graph"), value: "right" }
    ]

    readonly property var refreshRates: [
        { text: i18n("Standard (Every 1 Hour)"), value: 60 },
        { text: i18n("Aggressive / Frequent (Every 5 Minutes)"), value: 5 }
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

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: refreshRateCombo
            Kirigami.FormData.label: i18n("Background Refresh Rate:")
            Layout.fillWidth: true
            model: page.refreshRates
            textRole: "text"
            valueRole: "value"
            onActivated: page.cfg_refreshIntervalMinutes = currentValue
        }

        QQC2.CheckBox {
            id: refreshButtonCheck
            Kirigami.FormData.label: i18n("Refresh:")
            text: i18n("Show Manual Refresh Button")
        }
    }

    // Select the stored values without writing anything back to the config.
    Component.onCompleted: {
        displayModeCombo.currentIndex = Math.max(0, displayModeCombo.indexOfValue(cfg_panelDisplayMode));
        positionCombo.currentIndex = Math.max(0, positionCombo.indexOfValue(cfg_usernamePosition));
        refreshRateCombo.currentIndex = Math.max(0, refreshRateCombo.indexOfValue(cfg_refreshIntervalMinutes));
    }
}
