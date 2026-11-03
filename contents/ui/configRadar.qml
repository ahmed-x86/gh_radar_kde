import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Bindings to main.xml (the *Default properties silence Plasma's config warnings)
    property alias cfg_radarEnabled: enabledCheck.checked
    property alias cfg_radarMyReposOnly: myReposCheck.checked
    property alias cfg_radarManualOnly: manualCheck.checked
    property alias cfg_radarPollSeconds: pollSpin.value
    property alias cfg_radarActivePollSeconds: activeSpin.value
    property alias cfg_radarMaxPollSeconds: maxSpin.value
    property alias cfg_radarShowInPanel: panelCheck.checked
    property alias cfg_radarPanelMaxChars: charsSpin.value
    property string cfg_radarIcon
    property alias cfg_radarNotify: notifyCheck.checked
    property alias cfg_radarSound: soundCheck.checked
    property alias cfg_radarSoundFile: soundField.text
    property bool cfg_radarEnabledDefault
    property bool cfg_radarMyReposOnlyDefault
    property bool cfg_radarManualOnlyDefault
    property int cfg_radarPollSecondsDefault
    property int cfg_radarActivePollSecondsDefault
    property int cfg_radarMaxPollSecondsDefault
    property bool cfg_radarShowInPanelDefault
    property int cfg_radarPanelMaxCharsDefault
    property string cfg_radarIconDefault
    property bool cfg_radarNotifyDefault
    property bool cfg_radarSoundDefault
    property string cfg_radarSoundFileDefault

    // Icons offered for the panel text and the notifications (all from the Breeze theme).
    readonly property var radarIcons: [
        "vcs-normal", "vcs-branch", "vcs-commit", "vcs-merge", "vcs-diff",
        "vcs-pull-request", "vcs-locally-modified", "vcs-added", "code-context", "applications-development"
    ]

    FileDialog {
        id: soundDialog
        title: i18n("Choose Notification Sound")
        nameFilters: [i18n("Audio files (*.mp3 *.ogg *.oga *.wav *.flac)"), i18n("All files (*)")]
        onAccepted: soundField.text = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
    }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: enabledCheck
            Kirigami.FormData.label: i18n("Radar:")
            text: i18n("Watch GitHub push activity")
        }

        QQC2.CheckBox {
            id: myReposCheck
            enabled: enabledCheck.checked
            Kirigami.FormData.label: i18n("Filter:")
            text: i18n("Only track pushes to my own repositories")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Checking") }

        QQC2.CheckBox {
            id: manualCheck
            enabled: enabledCheck.checked
            Kirigami.FormData.label: i18n("Mode:")
            text: i18n("Manual refresh only (middle-click the widget or use the refresh button)")
        }

        RowLayout {
            enabled: enabledCheck.checked && !manualCheck.checked
            Kirigami.FormData.label: i18n("Starting interval:")
            QQC2.SpinBox { id: pollSpin; from: 5; to: 3600; stepSize: 5; editable: true }
            QQC2.Label { text: i18n("seconds") }
        }

        RowLayout {
            enabled: enabledCheck.checked && !manualCheck.checked
            Kirigami.FormData.label: i18n("After new activity:")
            QQC2.SpinBox { id: activeSpin; from: 5; to: 3600; stepSize: 5; editable: true }
            QQC2.Label { text: i18n("seconds") }
        }

        RowLayout {
            enabled: enabledCheck.checked && !manualCheck.checked
            Kirigami.FormData.label: i18n("Slowest interval:")
            QQC2.SpinBox { id: maxSpin; from: 5; to: 3600; stepSize: 5; editable: true }
            QQC2.Label { text: i18n("seconds") }
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.disabledTextColor
            text: i18n("Checks start at the starting interval, speed up after new activity and slow down by 5 seconds each quiet check, up to the slowest interval.")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Panel") }

        QQC2.CheckBox {
            id: panelCheck
            enabled: enabledCheck.checked
            Kirigami.FormData.label: i18n("Show in panel:")
            text: i18n("Latest activity (icon + user / repo / message)")
        }

        RowLayout {
            enabled: enabledCheck.checked && panelCheck.checked
            Kirigami.FormData.label: i18n("Max text length:")
            QQC2.SpinBox { id: charsSpin; from: 10; to: 100; stepSize: 5; editable: true }
            QQC2.Label { text: i18n("characters") }
        }

        Flow {
            enabled: enabledCheck.checked
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            Kirigami.FormData.label: i18n("Icon:")
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: page.radarIcons

                QQC2.ToolButton {
                    required property string modelData
                    icon.name: modelData
                    display: QQC2.AbstractButton.IconOnly
                    checkable: true
                    checked: page.cfg_radarIcon === modelData
                    onClicked: page.cfg_radarIcon = modelData
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: modelData
                }
            }
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Alerts") }

        QQC2.CheckBox {
            id: notifyCheck
            enabled: enabledCheck.checked
            Kirigami.FormData.label: i18n("Notifications:")
            text: i18n("Show a notification for new pushes")
        }

        QQC2.CheckBox {
            id: soundCheck
            enabled: enabledCheck.checked
            Kirigami.FormData.label: i18n("Sound:")
            text: i18n("Play a sound for new pushes")
        }

        RowLayout {
            enabled: enabledCheck.checked && soundCheck.checked
            Layout.fillWidth: true
            Kirigami.FormData.label: i18n("Sound file:")

            QQC2.TextField {
                id: soundField
                Layout.fillWidth: true
                placeholderText: i18n("Empty = system notification sound")
            }
            QQC2.Button {
                icon.name: "document-open"
                text: i18n("Browse...")
                onClicked: soundDialog.open()
            }
        }
    }
}
