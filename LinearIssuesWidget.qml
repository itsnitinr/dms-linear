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
    // Not a user-facing setting: the team you last filed into, so the form
    // opens where you left it.
    readonly property string rememberedTeamId: String(pluginData.lastTeamId || "").trim()
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

    // --- compose ----------------------------------------------------------
    // The draft lives here rather than in the form so closing the popout
    // mid-sentence does not throw it away.
    property bool composing: false
    property string draftTeamId: ""
    property string draftTitle: ""
    property string draftDescription: ""
    property int draftPriority: 0
    property bool draftAssignSelf: true
    property bool pendingAssignSelf: true
    property var teams: []
    property bool teamsLoaded: false
    property string viewerId: ""

    readonly property bool configured: configuredKey !== "" || keyCommand !== ""
    readonly property bool creating: createRequest.running
    readonly property string draftProblem: Linear.draftProblem({
        "teamId": root.draftTeamId,
        "title": root.draftTitle
    })
    readonly property bool fetching: issuesRequest.running || keyProc.running
    readonly property int openCount: issues.length
    readonly property int startedCount: Linear.countStarted(issues)

    // A solid glyph reads optically larger than the bar's outline icons at the
    // same pixel size, so the mark is drawn a little smaller to match them.
    readonly property int pillIconSize: Math.max(13, Math.round(widgetThickness * 0.46))
    readonly property int dotSize: Math.max(6, Math.round(pillIconSize * 0.38))
    readonly property bool dotVisible: lastError !== "" || openCount > 0
    readonly property color dotColor: lastError !== "" ? Theme.error : (startedCount > 0 ? Theme.primary : Theme.secondary)

    readonly property string statusLine: {
        if (!root.configured)
            return "No API key configured"
        if (root.composing && root.flashMessage === "")
            return "New issue"
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
        root.teamsLoaded = false
        root.viewerId = ""
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
        if (data.viewer) {
            root.viewerName = String(data.viewer.displayName || data.viewer.name || "")
            root.viewerId = String(data.viewer.id || "")
        }
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

    // The team list is only needed to file an issue, so it is fetched the
    // first time the form opens rather than on every poll.
    function fetchTeams() {
        if (root.teamsLoaded || teamsRequest.running)
            return
        // Composing before the first poll has resolved the key: kick the key
        // off and let onKeyResolvedChanged come back to this.
        if (root.apiKey === "") {
            root.refresh()
            return
        }
        teamsRequest.send(root.apiKey, Linear.buildTeamsQuery())
    }

    onKeyResolvedChanged: {
        if (root.keyResolved && root.composing)
            root.fetchTeams()
    }

    // --- compose ----------------------------------------------------------

    function startCompose() {
        if (!root.configured)
            return

        root.expandedIssueId = ""
        root.composing = true
        root.fetchTeams()
        root.pickDefaultTeam()
    }

    // Filing twice in a row almost always means the same team, so the last one
    // you chose is remembered. Failing that, the team you already have issues
    // in beats the first one alphabetically — and it is the only guess
    // available before the team list has landed.
    function pickDefaultTeam() {
        if (root.draftTeamId !== "")
            return

        const candidates = [root.rememberedTeamId].concat(root.issues.map(issue => issue.teamId))
        for (var i = 0; i < candidates.length; i++) {
            const id = String(candidates[i] || "")
            if (id === "")
                continue
            // Before the list lands a guess cannot be checked; after it lands,
            // a team you no longer belong to has to be skipped or the dropdown
            // would show nothing.
            if (root.teamsLoaded && !Linear.teamById(root.teams, id))
                continue
            root.draftTeamId = id
            return
        }

        if (root.teams.length > 0)
            root.draftTeamId = root.teams[0].id
    }

    function chooseTeam(teamId) {
        root.draftTeamId = teamId
        if (root.pluginService)
            root.pluginService.savePluginData(root.pluginId, "lastTeamId", teamId)
    }

    function cancelCompose() {
        root.composing = false
        root.clearDraft()
    }

    // The team survives: it is a preference, not part of what you just wrote.
    function clearDraft() {
        root.draftTitle = ""
        root.draftDescription = ""
        root.draftPriority = 0
    }

    function createIssue() {
        if (root.creating || root.draftProblem !== "" || root.apiKey === "")
            return

        const payload = Linear.buildCreateIssueMutation({
            "teamId": root.draftTeamId,
            "title": root.draftTitle,
            "description": root.draftDescription,
            "priority": root.draftPriority,
            "assigneeId": root.draftAssignSelf ? root.viewerId : ""
        })

        if (!createRequest.send(root.apiKey, payload))
            return

        root.pendingAssignSelf = root.draftAssignSelf
    }

    // A created issue only joins the list if it would have passed the filter
    // the list is showing — otherwise it is announced and left to Linear.
    function belongsInList(issue, assignedToMe) {
        if (issue.stateType === "completed" || issue.stateType === "canceled")
            return false
        if (!root.includeBacklog && issue.stateType === "backlog")
            return false
        if (root.scope === "assigned" && !assignedToMe)
            return false
        return true
    }

    function applyCreatedIssue(node) {
        const issue = Linear.normalizeIssue(node)
        if (!issue) {
            root.flash("Linear accepted the issue but described it oddly")
            return
        }

        root.composing = false
        root.clearDraft()

        if (root.belongsInList(issue, root.pendingAssignSelf)) {
            root.issues = [issue].concat(root.issues)
            root.sections = Linear.groupIssues(root.issues)
            // A first issue in a team the list has not seen needs that team's
            // workflow states before its status picker will work.
            root.fetchStates()
        }

        root.flash(issue.identifier + " created")
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

        // If the request refuses to start, the row must not be left spinning
        // with the whole list inert behind it.
        if (!mutationRequest.send(root.apiKey, Linear.buildSetStateMutation(issue.id, state.id)))
            return

        root.busyIssueId = issue.id
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
        id: teamsRequest

        onSucceeded: data => {
            root.teams = Linear.normalizeTeams(data)
            root.teamsLoaded = true
            if (root.viewerId === "" && data.viewer)
                root.viewerId = String(data.viewer.id || "")
            // A remembered or guessed team you no longer belong to would leave
            // the dropdown showing nothing, so it is dropped once the real
            // list arrives.
            if (root.draftTeamId !== "" && !Linear.teamById(root.teams, root.draftTeamId))
                root.draftTeamId = ""
            root.pickDefaultTeam()
        }
        onFailed: message => root.flash("Could not load teams: " + message)
    }

    GraphQlRequest {
        id: createRequest

        onSucceeded: data => {
            const result = data.issueCreate
            if (result && result.success)
                root.applyCreatedIssue(result.issue)
            else
                root.flash("Linear did not accept the new issue")
        }
        onFailed: message => root.flash(message)
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

                // The asset is already white; MultiEffect colorization keeps the
                // source's lightness, so tinting it would only ever grey it out.
                DankSVGIcon {
                    anchors.centerIn: parent
                    source: Qt.resolvedUrl("assets/linear-mark.svg")
                    size: root.pillIconSize
                    opacity: root.configured ? 1 : 0.45
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -2
                    anchors.topMargin: -2
                    width: root.dotSize
                    height: root.dotSize
                    radius: root.dotSize / 2
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

                // The asset is already white; MultiEffect colorization keeps the
                // source's lightness, so tinting it would only ever grey it out.
                DankSVGIcon {
                    anchors.centerIn: parent
                    source: Qt.resolvedUrl("assets/linear-mark.svg")
                    size: root.pillIconSize
                    opacity: root.configured ? 1 : 0.45
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -2
                    anchors.topMargin: -2
                    width: root.dotSize
                    height: root.dotSize
                    radius: root.dotSize / 2
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
                Row {
                    spacing: Theme.spacingXS

                    DankActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "add"
                        iconColor: Theme.surfaceText
                        enabled: root.configured && !root.composing
                        opacity: enabled ? 1 : 0.4
                        tooltipText: "New issue"
                        onClicked: root.startCompose()
                    }

                    DankActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "refresh"
                        iconColor: Theme.surfaceText
                        enabled: root.configured && !root.fetching && !root.composing
                        opacity: enabled ? 1 : 0.4
                        tooltipText: root.fetching ? "Refreshing…" : "Refresh issues"
                        onClicked: root.forceRefresh()
                    }
                }
            }

            // Reopening the popout after a while should not show stale work.
            Connections {
                target: popout.parentPopout
                ignoreUnknownSignals: true

                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout && popout.parentPopout.shouldBeVisible) {
                        root.refreshIfStale()
                        // The popout takes focus for its own Escape handling
                        // when it opens, so a draft in progress has to ask for
                        // the caret back.
                        if (root.composing)
                            Qt.callLater(composeForm.focusTitle)
                    } else {
                        root.expandedIssueId = ""
                    }
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

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        DankSVGIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            source: Qt.resolvedUrl("assets/linear-mark.svg")
                            size: Theme.iconSize
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Connect your Linear workspace"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }
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

                // ---- compose
                ComposeForm {
                    id: composeForm

                    width: body.innerWidth
                    visible: root.composing
                    teams: root.teams
                    draftTeamId: root.draftTeamId
                    draftTitle: root.draftTitle
                    draftDescription: root.draftDescription
                    draftPriority: root.draftPriority
                    draftAssignSelf: root.draftAssignSelf
                    canAssign: root.viewerId !== ""
                    busy: root.creating
                    problem: root.draftProblem

                    onTitleEdited: text => root.draftTitle = text
                    onDescriptionEdited: text => root.draftDescription = text
                    onTeamPicked: teamId => root.chooseTeam(teamId)
                    onPriorityPicked: priority => root.draftPriority = priority
                    onAssignToggled: on => root.draftAssignSelf = on
                    onSubmitted: root.createIssue()
                    onCancelled: root.cancelCompose()

                    onVisibleChanged: {
                        if (visible)
                            Qt.callLater(composeForm.focusTitle)
                    }

                    Component.onCompleted: {
                        if (visible)
                            Qt.callLater(composeForm.focusTitle)
                    }
                }

                // ---- error banner
                StyledRect {
                    width: body.innerWidth
                    implicitHeight: errorRow.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.error, 0.12)
                    visible: root.configured && root.lastError !== "" && !root.composing

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
                    visible: root.issues.length > 0 && !root.composing

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
                    visible: root.configured && root.issues.length === 0 && !root.fetching && root.lastError === "" && !root.composing

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
                    visible: root.fetching && root.issues.length === 0 && root.configured && !root.composing

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
