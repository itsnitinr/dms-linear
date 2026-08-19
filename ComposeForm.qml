// The compose form, shown in place of the issue list. The draft itself lives
// on the widget so closing the popout mid-sentence does not lose it; this file
// only draws it and reports edits back.
import QtQuick
import qs.Common
import qs.Widgets
import "Linear.js" as Linear

Item {
    id: root

    property var teams: []
    property string draftTeamId: ""
    property string draftTitle: ""
    property bool draftAssignSelf: true
    property bool canAssign: true
    property bool busy: false
    // Empty when the draft is fileable; otherwise what is missing.
    property string problem: ""

    signal titleEdited(string text)
    signal teamPicked(string teamId)
    signal assignToggled(bool on)
    signal submitted
    signal cancelled

    readonly property var teamLabels: (teams || []).map(team => Linear.teamLabel(team))
    readonly property string currentTeamLabel: Linear.teamLabel(Linear.teamById(teams, draftTeamId))

    function focusTitle() {
        titleField.forceActiveFocus()
    }

    // Both DankTextField and DankDropdown write to their own value property
    // when the user edits them, which would tear down a declarative binding to
    // the draft. So the draft is pushed into them by hand instead, and only
    // when it has actually drifted, which keeps the round trip from looping.
    function syncFromDraft() {
        // The draft can arrive while the form is still being built.
        if (!titleField || !teamField)
            return
        if (titleField.text !== root.draftTitle)
            titleField.text = root.draftTitle
        if (teamField.currentValue !== root.currentTeamLabel)
            teamField.currentValue = root.currentTeamLabel
    }

    onDraftTitleChanged: syncFromDraft()
    onDraftTeamIdChanged: syncFromDraft()
    onTeamsChanged: syncFromDraft()
    Component.onCompleted: syncFromDraft()

    implicitHeight: column.implicitHeight
    width: parent ? parent.width : 0
    height: implicitHeight

    Column {
        id: column

        width: parent.width
        spacing: Theme.spacingS

        DankTextField {
            id: titleField

            width: parent.width
            labelText: "Title"
            placeholderText: "What needs doing?"
            maximumLength: 255
            enabled: !root.busy
            showClearButton: true
            onTextEdited: root.titleEdited(text)
            onAccepted: root.submitted()

            Keys.onEscapePressed: event => {
                root.cancelled()
                event.accepted = true
            }
        }

        DankDropdown {
            id: teamField

            width: parent.width
            text: "Team"
            enabled: !root.busy && root.teams.length > 0
            options: root.teamLabels
            emptyText: "Loading teams…"
            enableFuzzySearch: root.teams.length > 8
            onValueChanged: value => {
                const id = Linear.teamIdForLabel(root.teams, value)
                if (id !== "")
                    root.teamPicked(id)
            }
        }

        // Drawn like the workflow-state chips in the list so the popout keeps
        // one visual language for "small thing you toggle".
        Row {
            width: parent.width
            spacing: Theme.spacingXS

            Rectangle {
                id: assignChip

                readonly property bool on: root.draftAssignSelf && root.canAssign

                height: 26
                width: assignRow.implicitWidth + Theme.spacingS * 2
                radius: 13
                opacity: root.canAssign ? 1 : 0.5
                color: on ? Theme.withAlpha(Theme.primary, 0.22) : (assignArea.containsMouse ? Theme.surfaceHover : Theme.surfaceContainerHigh)
                border.width: on ? 1 : 0
                border.color: Theme.primary

                Row {
                    id: assignRow

                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: assignChip.on ? "person_check" : "person"
                        size: Theme.iconSizeSmall - 2
                        color: assignChip.on ? Theme.primary : Theme.surfaceTextSecondary
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Assign to me"
                        font.pixelSize: Theme.fontSizeSmall
                        color: assignChip.on ? Theme.surfaceText : Theme.surfaceTextMedium
                    }
                }

                MouseArea {
                    id: assignArea

                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !root.busy && root.canAssign
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.assignToggled(!root.draftAssignSelf)
                }
            }
        }

        Item {
            width: parent.width
            height: actions.implicitHeight

            StyledText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - actions.width - Theme.spacingS
                text: root.problem
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceTextSecondary
                elide: Text.ElideRight
                visible: root.problem !== "" && !root.busy
            }

            Row {
                id: actions

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DankButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cancel"
                    buttonHeight: 32
                    horizontalPadding: Theme.spacingM
                    backgroundColor: "transparent"
                    textColor: Theme.surfaceTextMedium
                    onClicked: root.cancelled()
                }

                DankButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.busy ? "Creating…" : "Create"
                    buttonHeight: 32
                    horizontalPadding: Theme.spacingM
                    backgroundColor: Theme.primary
                    textColor: Theme.onPrimary
                    opacity: root.problem === "" && !root.busy ? 1 : 0.5
                    onClicked: root.submitted()
                }
            }
        }
    }
}
