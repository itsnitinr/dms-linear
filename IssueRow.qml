// One issue in the popout list: click the row to open it, click the state
// glyph on the left to reveal that team's workflow states and move it.
import QtQuick
import qs.Common
import qs.Widgets
import "Linear.js" as Linear

Item {
    id: root

    required property var issue
    property var states: []
    property bool expanded: false
    property bool busy: false
    property bool interactive: true
    property bool showPriority: true

    signal activated
    signal statusToggled
    signal statusPicked(var picked)

    readonly property var due: Linear.formatDueDate(issue.dueDate, new Date())
    readonly property var priority: Linear.priorityMeta(issue.priority)
    // Linear hands back colours as hex strings; a color-typed property is what
    // converts them, and Theme.withAlpha needs the converted value.
    readonly property color stateColor: issue.stateColor
    readonly property string metaText: {
        const parts = []
        if (issue.teamKey !== "")
            parts.push(issue.teamKey)
        if (issue.projectName !== "")
            parts.push(issue.projectName)
        if (due.label !== "")
            parts.push(due.label)
        return parts.join("  ·  ")
    }

    implicitHeight: column.implicitHeight
    width: parent ? parent.width : 0
    height: implicitHeight

    Column {
        id: column

        width: parent.width
        spacing: 0

        StyledRect {
            id: card

            width: parent.width
            implicitHeight: Math.max(44, contentRow.implicitHeight + Theme.spacingS)
            height: implicitHeight
            radius: Theme.cornerRadius
            color: rowArea.containsMouse ? Theme.surfaceHover : "transparent"

            MouseArea {
                id: rowArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (root.interactive)
                        root.activated()
                }
            }

            Row {
                id: contentRow

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingXS
                anchors.rightMargin: Theme.spacingXS
                spacing: Theme.spacingXS

                // State glyph doubles as the button that opens the picker.
                Rectangle {
                    id: stateButton

                    width: 28
                    height: 28
                    radius: 14
                    anchors.verticalCenter: parent.verticalCenter
                    color: stateArea.containsMouse || root.expanded ? Theme.withAlpha(root.stateColor, 0.18) : "transparent"

                    DankIcon {
                        anchors.centerIn: parent
                        name: Linear.stateIcon(root.issue.stateType)
                        size: Theme.iconSizeSmall
                        color: root.stateColor
                        visible: !root.busy
                    }

                    DankSpinner {
                        anchors.centerIn: parent
                        size: Theme.iconSizeSmall
                        color: root.stateColor
                        running: root.busy
                        visible: root.busy
                    }

                    MouseArea {
                        id: stateArea

                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.interactive && !root.busy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.statusToggled()
                    }
                }

                Column {
                    id: textColumn

                    width: contentRow.width - stateButton.width - priorityIcon.width - contentRow.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            id: identifier

                            anchors.verticalCenter: parent.verticalCenter
                            text: root.issue.identifier
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.monoFontFamily
                            color: Theme.surfaceTextSecondary
                        }

                        StyledText {
                            width: parent.width - identifier.width - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.issue.title
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: root.metaText !== "" || root.issue.labels.length > 0

                        StyledText {
                            id: meta

                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width)
                            text: root.metaText
                            font.pixelSize: Theme.fontSizeSmall - 2
                            color: root.due.overdue ? Theme.error : (root.due.soon ? Theme.warning : Theme.surfaceTextSecondary)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            visible: root.metaText !== ""
                        }

                        Repeater {
                            model: root.issue.labels.slice(0, 2)

                            Rectangle {
                                id: labelChip

                                required property var modelData

                                readonly property color labelColor: modelData.color

                                anchors.verticalCenter: parent.verticalCenter
                                width: labelText.implicitWidth + Theme.spacingS
                                height: labelText.implicitHeight + 2
                                radius: height / 2
                                color: Theme.withAlpha(labelColor, 0.16)

                                StyledText {
                                    id: labelText

                                    anchors.centerIn: parent
                                    text: labelChip.modelData.name
                                    font.pixelSize: Theme.fontSizeSmall - 2
                                    color: labelChip.labelColor
                                }
                            }
                        }
                    }
                }

                DankIcon {
                    id: priorityIcon

                    anchors.verticalCenter: parent.verticalCenter
                    name: root.priority.icon
                    size: Theme.iconSizeSmall
                    color: root.priority.urgent ? Theme.error : Theme.surfaceTextSecondary
                    visible: root.showPriority && root.issue.priority !== 0
                    width: visible ? Theme.iconSizeSmall : 0
                }
            }
        }

        // Workflow states for this issue's team, revealed in place so the list
        // never has to fight a floating menu for z-order.
        Item {
            id: picker

            width: parent.width
            height: root.expanded ? pickerFlow.implicitHeight + Theme.spacingS : 0
            clip: true
            visible: height > 0

            Behavior on height {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Easing.OutCubic
                }
            }

            Flow {
                id: pickerFlow

                x: 28 + Theme.spacingXS * 2
                y: Theme.spacingXS
                width: parent.width - x
                spacing: Theme.spacingXS

                Repeater {
                    model: root.states

                    Rectangle {
                        id: chip

                        required property var modelData

                        readonly property bool current: modelData.id === root.issue.stateId
                        readonly property color chipColor: modelData.color

                        width: chipRow.implicitWidth + Theme.spacingS * 2
                        height: 26
                        radius: 13
                        color: current ? Theme.withAlpha(chipColor, 0.22) : (chipArea.containsMouse ? Theme.surfaceHover : Theme.surfaceContainerHigh)
                        border.width: current ? 1 : 0
                        border.color: chipColor

                        Row {
                            id: chipRow

                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            DankIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: Linear.stateIcon(chip.modelData.type)
                                size: Theme.iconSizeSmall - 2
                                color: chip.chipColor
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.modelData.name
                                font.pixelSize: Theme.fontSizeSmall
                                color: chip.current ? Theme.surfaceText : Theme.surfaceTextMedium
                            }
                        }

                        MouseArea {
                            id: chipArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.statusPicked(chip.modelData)
                        }
                    }
                }

                StyledText {
                    text: "No workflow states loaded for this team yet."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceTextSecondary
                    visible: root.states.length === 0
                }
            }
        }
    }
}
