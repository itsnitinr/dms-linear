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
    property string draftDescription: ""
    property int draftPriority: 0
    property bool draftAssignSelf: true
    property bool canAssign: true
    property bool busy: false
    // Empty when the draft is fileable; otherwise what is missing.
    property string problem: ""

    signal titleEdited(string text)
    signal descriptionEdited(string text)
    signal teamPicked(string teamId)
    signal priorityPicked(int priority)
    signal assignToggled(bool on)
    signal submitted
    signal cancelled

    readonly property var teamLabels: (teams || []).map(team => Linear.teamLabel(team))

    // Deliberately computed on the spot rather than read off a derived
    // property: syncFromDraft runs from a property change handler, and a
    // handler fires alongside the bindings that depend on the same property,
    // not after them — so a derived property read there can still hold the
    // value from before the change.
    function teamLabelNow() {
        return Linear.teamLabel(Linear.teamById(root.teams, root.draftTeamId))
    }

    function priorityLabelNow() {
        return Linear.priorityMeta(root.draftPriority).label
    }

    function focusTitle() {
        titleField.forceActiveFocus()
    }

    // Both DankTextField and DankDropdown write to their own value property
    // when the user edits them, which would tear down a declarative binding to
    // the draft. So the draft is pushed into them by hand instead, and only
    // when it has actually drifted, which keeps the round trip from looping.
    function syncFromDraft() {
        // The draft can arrive while the form is still being built.
        if (!titleField || !teamField || !priorityField || !descriptionEdit)
            return
        if (titleField.text !== root.draftTitle)
            titleField.text = root.draftTitle
        if (descriptionEdit.text !== root.draftDescription)
            descriptionEdit.text = root.draftDescription
        const teamLabel = root.teamLabelNow()
        if (teamField.currentValue !== teamLabel)
            teamField.currentValue = teamLabel
        const priorityLabel = root.priorityLabelNow()
        if (priorityField.currentValue !== priorityLabel)
            priorityField.currentValue = priorityLabel
    }

    onDraftTitleChanged: syncFromDraft()
    onDraftDescriptionChanged: syncFromDraft()
    onDraftTeamIdChanged: syncFromDraft()
    onDraftPriorityChanged: syncFromDraft()
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
            keyNavigationTab: descriptionEdit
            onTextEdited: root.titleEdited(text)
            onAccepted: root.submitted()

            Keys.onEscapePressed: event => {
                root.cancelled()
                event.accepted = true
            }
        }

        // There is no multi-line field in the DMS widget set, so this is a
        // TextEdit dressed as one. It grows with what you type and starts
        // scrolling rather than pushing the buttons off the popout.
        StyledRect {
            id: descriptionBox

            readonly property real labelBandHeight: Math.round(Theme.fontSizeSmall * 1.4) + Theme.spacingXS * 2

            width: parent.width
            implicitHeight: labelBandHeight + Math.min(Math.max(44, descriptionEdit.implicitHeight), 120) + Theme.spacingS
            height: implicitHeight
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.color: descriptionEdit.activeFocus ? Theme.primary : Theme.outlineMedium
            border.width: descriptionEdit.activeFocus ? 2 : 1

            StyledText {
                id: descriptionLabel

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                anchors.topMargin: Theme.spacingXS
                text: "Description"
                font.pixelSize: Theme.fontSizeSmall
                color: descriptionEdit.activeFocus ? Theme.primary : Theme.surfaceVariantText
                elide: Text.ElideRight
            }

            Flickable {
                id: descriptionFlick

                // Keeps the caret in view once the text is taller than the box.
                function ensureVisible(rect) {
                    if (contentY >= rect.y)
                        contentY = rect.y
                    else if (contentY + height <= rect.y + rect.height)
                        contentY = rect.y + rect.height - height
                }

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                anchors.topMargin: descriptionBox.labelBandHeight
                anchors.bottomMargin: Theme.spacingS
                contentWidth: width
                contentHeight: descriptionEdit.implicitHeight
                clip: true
                interactive: contentHeight > height

                TextEdit {
                    id: descriptionEdit

                    width: descriptionFlick.width
                    enabled: !root.busy
                    font.pixelSize: Theme.fontSizeMedium
                    font.family: Theme.fontFamily
                    color: Theme.surfaceText
                    selectionColor: Theme.primaryContainer
                    selectedTextColor: Theme.primary
                    selectByMouse: true
                    activeFocusOnTab: true
                    wrapMode: TextEdit.Wrap
                    onTextChanged: root.descriptionEdited(text)
                    onCursorRectangleChanged: descriptionFlick.ensureVisible(cursorRectangle)

                    // Return belongs to the text here, so filing the issue from
                    // the description needs the modifier.
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.cancelled()
                            event.accepted = true
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                            root.submitted()
                            event.accepted = true
                        }
                    }

                    StyledText {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: "Anything worth writing down (optional). Ctrl+Enter files it."
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.outlineButton
                        visible: descriptionEdit.text === ""
                        elide: Text.ElideRight
                        width: descriptionEdit.width
                    }
                }
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

        DankDropdown {
            id: priorityField

            width: parent.width
            text: "Priority"
            enabled: !root.busy
            options: Linear.priorityLabels()
            optionIconMap: Linear.priorityIconMap()
            onValueChanged: value => root.priorityPicked(Linear.priorityForLabel(value))
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
