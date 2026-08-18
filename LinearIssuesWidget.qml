// DankBar pill for Linear: a dot when you have open issues, and a popout that
// lists them by status so one click opens an issue and one more moves it.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Widgets
import "Linear.js" as Linear

PluginComponent {
    id: root

    pluginId: "linearIssues"

    popoutWidth: 460
    popoutHeight: 320

    // --- settings ---------------------------------------------------------
    readonly property string configuredKey: String(pluginData.apiKey || "").trim()
    readonly property string keyCommand: String(pluginData.apiKeyCommand || "").trim()
    readonly property string scope: String(pluginData.scope || "assigned")
    readonly property bool includeBacklog: pluginData.includeBacklog !== false
    readonly property bool preferDesktopApp: pluginData.preferDesktopApp !== false
    readonly property bool showCount: pluginData.showCount === true
    readonly property int refreshMinutes: Math.max(1, parseInt(pluginData.refreshMinutes || "5") || 5)
    readonly property int maxIssues: Math.max(1, parseInt(pluginData.maxIssues || "50") || 50)

    // --- state ------------------------------------------------------------
    property string apiKey: ""
    property bool keyResolved: false
    property bool fetchAfterKey: false
    property var issues: []
    property var sections: []
    property var statesByTeam: ({})
    property string loadedStatesKey: ""
    property string pendingStatesKey: ""
    property string lastError: ""
    property string flashMessage: ""
    property string viewerName: ""
    property var lastUpdated: null
    property bool hasDesktopApp: false
    property string busyIssueId: ""
    property string expandedIssueId: ""
    // Ticks so the "updated 3m ago" line ages while the popout stays open.
    property real nowTick: Date.now()

    readonly property bool configured: configuredKey !== "" || keyCommand !== ""
    readonly property bool fetching: issuesRequest.running || keyProc.running
    readonly property int openCount: issues.length
    readonly property int startedCount: Linear.countStarted(issues)

    readonly property int pillIconSize: Math.max(16, Math.round(widgetThickness * 0.6))
    readonly property color pillColor: configured ? Theme.surfaceText : Theme.surfaceTextMedium
    readonly property bool dotVisible: lastError !== "" || openCount > 0
    readonly property color dotColor: lastError !== "" ? Theme.error : (startedCount > 0 ? Theme.primary : Theme.secondary)

    readonly property string statusLine: {
        if (!root.configured)
            return "No API key configured"
        if (root.lastError !== "")
            return root.lastError
        if (root.flashMessage !== "")
            return root.flashMessage
        if (root.fetching && root.lastUpdated === null)
            return "Loading issues…"
        const who = root.viewerName !== "" ? root.viewerName : ""
        const stamp = Linear.formatRelative(root.lastUpdated, root.nowTick)
        if (who !== "" && stamp !== "")
            return who + " · updated " + stamp
        return stamp !== "" ? "Updated " + stamp : who
    }

    // --- credential -------------------------------------------------------

    // The key command is only re-run on demand: it may prompt a password
    // manager, which would be obnoxious on every poll.
    function resolveKey() {
        if (keyProc.running)
            return

        if (root.keyCommand === "") {
            root.apiKey = root.configuredKey
            root.keyResolved = root.apiKey !== ""
            if (!root.keyResolved && root.configured)
                root.lastError = "API key is empty"
            root.drainKeyWaiters()
            return
        }

        keyProc.command = ["sh", "-c", root.keyCommand]
        keyProc.running = true
    }

    function drainKeyWaiters() {
        if (!root.fetchAfterKey)
            return
        root.fetchAfterKey = false
        if (root.keyResolved)
            root.fetchIssues()
    }

    function invalidateKey() {
        root.apiKey = ""
        root.keyResolved = false
        root.lastError = ""
        root.loadedStatesKey = ""
        Qt.callLater(root.refresh)
    }

    onConfiguredKeyChanged: invalidateKey()
    onKeyCommandChanged: invalidateKey()

    // --- fetching ---------------------------------------------------------

    function refresh() {
        if (!root.configured) {
            root.issues = []
            root.sections = []
            return
        }
        if (!root.keyResolved) {
            root.fetchAfterKey = true
            root.resolveKey()
            return
        }
        root.fetchIssues()
    }

    function forceRefresh() {
        root.lastError = ""
        root.keyResolved = false
        root.refresh()
    }

    function refreshIfStale() {
        if (!root.configured || root.fetching)
            return
        if (root.lastUpdated === null || Date.now() - root.lastUpdated.getTime() > 60000)
            root.refresh()
    }

    function fetchIssues() {
        if (root.apiKey === "" || issuesRequest.running)
            return
        issuesRequest.send(root.apiKey, Linear.buildIssuesQuery({
            "scope": root.scope,
            "includeBacklog": root.includeBacklog,
            "maxIssues": root.maxIssues
        }))
    }

    function applyIssues(data) {
        root.issues = Linear.normalizeIssues(data)
        root.sections = Linear.groupIssues(root.issues)
        root.viewerName = data.viewer ? String(data.viewer.displayName || data.viewer.name || "") : ""
        root.lastUpdated = new Date()
        root.lastError = ""
        root.fetchStates()
    }

    // Workflow states are per team and rarely change, so they are only
    // refetched when the set of teams in the list actually moves.
    function fetchStates() {
        const ids = Linear.teamIdsOf(root.issues)
        if (ids.length === 0 || statesRequest.running)
            return

        const key = ids.slice().sort().join(",")
        if (key === root.loadedStatesKey)
            return

        root.pendingStatesKey = key
        statesRequest.send(root.apiKey, Linear.buildStatesQuery(ids))
    }

    function statesFor(issue) {
        if (!issue || !issue.teamId)
            return []
        return root.statesByTeam[issue.teamId] || []
    }

    // --- actions ----------------------------------------------------------

    function openIssue(issue) {
        if (!issue || issue.url === "")
            return

        const deep = Linear.deepLink(issue.url)
        if (root.preferDesktopApp && root.hasDesktopApp && deep !== "")
            Quickshell.execDetached(["xdg-open", deep])
        else
            Quickshell.execDetached(["xdg-open", issue.url])
    }

    function toggleStatusPicker(issue) {
        if (!issue)
            return
        root.expandedIssueId = root.expandedIssueId === issue.id ? "" : issue.id
    }

    function setIssueState(issue, state) {
        if (!issue || !state)
            return

        root.expandedIssueId = ""
        if (state.id === issue.stateId || root.busyIssueId !== "" || root.apiKey === "")
            return

        root.busyIssueId = issue.id
        mutationRequest.send(root.apiKey, Linear.buildSetStateMutation(issue.id, state.id))
    }

    // Rewrites the one issue in place. An issue moved to a state the current
    // filter excludes — done, canceled, or backlog when it is hidden — drops
    // off the list, which is what the equivalent move in Linear would do.
    function applyIssueState(updated) {
        if (!updated || !updated.state)
            return

        const state = updated.state
        const dropped = state.type === "completed" || state.type === "canceled" || (!root.includeBacklog && state.type === "backlog")
        const next = []
        var label = ""

        for (var i = 0; i < root.issues.length; i++) {
            const issue = root.issues[i]
            if (issue.id !== updated.id) {
                next.push(issue)
                continue
            }
            label = issue.identifier + " → " + String(state.name || "")
            if (dropped)
                continue
            next.push(Object.assign({}, issue, {
                "stateId": String(state.id || ""),
                "stateName": String(state.name || ""),
                "stateType": String(state.type || ""),
                "stateColor": String(state.color || "#8a8f98")
            }))
        }

        root.issues = next
        root.sections = Linear.groupIssues(next)
        if (label !== "")
            root.flash(label)
    }

    function flash(message) {
        root.flashMessage = message
        flashTimer.restart()
    }

    Component.onCompleted: {
        handlerProc.running = true
        Qt.callLater(root.refresh)
    }

    // --- processes --------------------------------------------------------

    Process {
        id: keyProc

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const key = String(text || "").split("\n")[0].trim()
                if (key !== "") {
                    root.apiKey = key
                    root.keyResolved = true
                    root.lastError = ""
                }
            }
        }

        onExited: exitCode => {
            if (!root.keyResolved) {
                root.apiKey = ""
                root.lastError = exitCode === 0 ? "Key command printed nothing" : "Key command failed (exit " + exitCode + ")"
            }
            root.drainKeyWaiters()
        }
    }

    // Whether the Linear desktop app is installed decides if linear:// links
    // go anywhere. Checked once; a missing xdg-mime just means "browser".
    Process {
        id: handlerProc

        command: ["xdg-mime", "query", "default", "x-scheme-handler/linear"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.hasDesktopApp = String(text || "").trim() !== ""
        }
    }

    GraphQlRequest {
        id: issuesRequest

        onSucceeded: data => root.applyIssues(data)
        onFailed: message => {
            root.lastError = message
            if (message.indexOf("API key") !== -1)
                root.keyResolved = false
        }
    }

    GraphQlRequest {
        id: statesRequest

        onSucceeded: data => {
            root.statesByTeam = Linear.normalizeStates(data)
            root.loadedStatesKey = root.pendingStatesKey
        }
        onFailed: message => root.flash("Could not load workflow states: " + message)
    }

    GraphQlRequest {
        id: mutationRequest

        onSucceeded: data => {
            const result = data.issueUpdate
            if (result && result.success)
                root.applyIssueState(result.issue)
            else
                root.flash("Linear did not accept the status change")
            root.busyIssueId = ""
        }
        onFailed: message => {
            root.flash(message)
            root.busyIssueId = ""
        }
    }

    Timer {
        id: flashTimer

        interval: 4000
        onTriggered: root.flashMessage = ""
    }

    Timer {
        interval: root.refreshMinutes * 60000
        running: root.configured
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 30000
        running: root.lastUpdated !== null
        repeat: true
        onTriggered: root.nowTick = Date.now()
    }

    // --- bar pills --------------------------------------------------------

    pillRightClickAction: () => root.forceRefresh()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: root.pillIconSize
                height: root.pillIconSize

                DankSVGIcon {
                    anchors.fill: parent
                    source: Qt.resolvedUrl("assets/linear.svg")
                    size: root.pillIconSize
                    colorOverride: root.pillColor
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -2
                    anchors.topMargin: -1
                    width: 7
                    height: 7
                    radius: 3.5
                    color: root.dotColor
                    visible: root.dotVisible && !root.showCount
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.showCount && root.openCount > 0
                text: root.openCount
                font.pixelSize: Theme.fontSizeSmall
                color: root.startedCount > 0 ? Theme.primary : Theme.surfaceText
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 0

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.pillIconSize
                height: root.pillIconSize

                DankSVGIcon {
                    anchors.fill: parent
                    source: Qt.resolvedUrl("assets/linear.svg")
                    size: root.pillIconSize
                    colorOverride: root.pillColor
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -2
                    anchors.topMargin: -1
                    width: 7
                    height: 7
                    radius: 3.5
                    color: root.dotColor
                    visible: root.dotVisible && !root.showCount
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.showCount && root.openCount > 0
                text: root.openCount
                font.pixelSize: Theme.fontSizeSmall
                color: root.startedCount > 0 ? Theme.primary : Theme.surfaceText
            }
        }
    }

    // --- popout -----------------------------------------------------------

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Linear"
            detailsText: root.statusLine
            showCloseButton: true

            headerActions: Component {
                DankActionButton {
                    iconName: "refresh"
                    iconColor: Theme.surfaceText
                    enabled: root.configured && !root.fetching
                    opacity: enabled ? 1 : 0.4
                    tooltipText: root.fetching ? "Refreshing…" : "Refresh issues"
                    onClicked: root.forceRefresh()
                }
            }

            // Reopening the popout after a while should not show stale work.
            Connections {
                target: popout.parentPopout
                ignoreUnknownSignals: true

                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout && popout.parentPopout.shouldBeVisible)
                        root.refreshIfStale()
                    else
                        root.expandedIssueId = ""
                }
            }

            Column {
                id: body

                readonly property real innerWidth: width - leftPadding - rightPadding

                width: parent.width
                leftPadding: Theme.spacingS
                rightPadding: Theme.spacingS
                spacing: Theme.spacingM

                // ---- unconfigured: setup instructions
                Column {
                    width: body.innerWidth
                    spacing: Theme.spacingS
                    visible: !root.configured

                    StyledText {
                        width: parent.width
                        text: "Connect your Linear workspace"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        model: ["1.  In Linear: Settings → Security & access → Personal API keys", "2.  Create a key and copy it", "3.  Paste it into this plugin's settings (Settings → Plugins → Linear Issues)"]

                        StyledText {
                            required property string modelData

                            width: body.innerWidth
                            text: modelData
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                            wrapMode: Text.WordWrap
                        }
                    }

                    StyledText {
                        width: parent.width
                        topPadding: Theme.spacingXS
                        text: "Prefer to keep it out of a config file? Point the \"API key command\" setting at your password manager instead."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextSecondary
                        wrapMode: Text.WordWrap
                    }
                }

                // ---- error banner
                StyledRect {
                    width: body.innerWidth
                    implicitHeight: errorRow.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.error, 0.12)
                    visible: root.configured && root.lastError !== ""

                    Row {
                        id: errorRow

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        spacing: Theme.spacingS

                        DankIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "error_outline"
                            size: Theme.iconSizeSmall
                            color: Theme.error
                        }

                        StyledText {
                            width: parent.width - Theme.iconSizeSmall - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.lastError
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.error
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // ---- the list
                // Capped so a long queue scrolls instead of growing a popout
                // taller than the screen.
                DankFlickable {
                    width: body.innerWidth
                    height: Math.min(listColumn.implicitHeight, 420)
                    contentHeight: listColumn.implicitHeight
                    contentWidth: width
                    clip: true
                    visible: root.issues.length > 0

                    Column {
                        id: listColumn

                        width: parent.width
                        spacing: Theme.spacingS

                        Repeater {
                            model: root.sections

                            Column {
                                id: section

                                required property var modelData

                                width: listColumn.width
                                spacing: 2

                                Row {
                                    height: 22
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: section.modelData.label
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Bold
                                        color: Theme.surfaceTextMedium
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: section.modelData.issues.length
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceTextSecondary
                                    }
                                }

                                Repeater {
                                    model: section.modelData.issues

                                    IssueRow {
                                        required property var modelData

                                        width: section.width
                                        issue: modelData
                                        states: root.statesFor(modelData)
                                        expanded: root.expandedIssueId === modelData.id
                                        busy: root.busyIssueId === modelData.id
                                        interactive: root.busyIssueId === ""

                                        onActivated: root.openIssue(modelData)
                                        onStatusToggled: root.toggleStatusPicker(modelData)
                                        onStatusPicked: picked => root.setIssueState(modelData, picked)
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- nothing to show
                Column {
                    width: body.innerWidth
                    spacing: Theme.spacingXS
                    visible: root.configured && root.issues.length === 0 && !root.fetching && root.lastError === ""

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Nothing on your plate"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceTextMedium
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.scope === "created" ? "No open issues you created." : "No open issues assigned to you."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextSecondary
                    }
                }

                // ---- first load
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingS
                    visible: root.fetching && root.issues.length === 0 && root.configured

                    DankSpinner {
                        anchors.verticalCenter: parent.verticalCenter
                        size: Theme.iconSizeSmall
                        color: Theme.primary
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Loading your issues…"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                    }
                }
            }
        }
    }
}
