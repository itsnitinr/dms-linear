// ---------------------------------------------------------------------------
// Linear Issues — GraphQL payloads, response shaping and display helpers
//
// Everything here is pure (no Qt/Quickshell), so it is testable from plain
// node. Functions are declared at top level: QML `import "Linear.js" as Linear`
// exposes them directly.
// ---------------------------------------------------------------------------

var ENDPOINT = "https://api.linear.app/graphql"

// Linear's own ordering: the board reads top-to-bottom in this order, so the
// popout does too. "triage" only exists on teams that enabled it.
var STATE_TYPE_ORDER = ["started", "unstarted", "triage", "backlog", "completed", "canceled"]

var STATE_TYPE_LABEL = {
    "triage": "Triage",
    "backlog": "Backlog",
    "unstarted": "Todo",
    "started": "In Progress",
    "completed": "Done",
    "canceled": "Canceled"
}

// --- small helpers ---------------------------------------------------------

function trimmed(value) {
    return String(value === undefined || value === null ? "" : value).trim()
}

function truncate(text, max) {
    const s = String(text || "")
    if (s.length <= max)
        return s
    return s.slice(0, Math.max(0, max - 1)).trimEnd() + "…"
}

function uniq(list) {
    const seen = {}
    const out = []
    for (var i = 0; i < list.length; i++) {
        const key = String(list[i])
        if (!key || seen[key])
            continue
        seen[key] = true
        out.push(list[i])
    }
    return out
}

// --- curl plumbing ---------------------------------------------------------

// curl parses a quoted config value with backslash escapes, so both the API key
// and the JSON body survive intact as long as \ and " are escaped first.
function escapeCurlValue(value) {
    return String(value === undefined || value === null ? "" : value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\r/g, "\\r").replace(/\n/g, "\\n").replace(/\t/g, "\\t")
}

// The API key is a credential, so it must never appear in a process argument
// list where every local user can read it via /proc. curl gets the whole
// request — URL, auth header and body — over stdin as a `-K -` config instead.
function curlConfig(apiKey, body, timeoutSeconds) {
    const lines = ["url = \"" + escapeCurlValue(ENDPOINT) + "\"", "request = \"POST\"", "header = \"Content-Type: application/json\"", "header = \"Authorization: " + escapeCurlValue(apiKey) + "\"", "data-binary = \"" + escapeCurlValue(JSON.stringify(body)) + "\"", "max-time = \"" + Math.max(1, Math.round(timeoutSeconds || 20)) + "\"", "silent", "show-error", "location"]
    return lines.join("\n") + "\n"
}

// --- queries ---------------------------------------------------------------

var ISSUE_FIELDS = "\n    id\n    identifier\n    title\n    url\n    priority\n    dueDate\n    updatedAt\n    branchName\n    state { id name type color position }\n    team { id key name }\n    project { id name }\n    labels(first: 4) { nodes { id name color } }\n"

// `scope` is one of "assigned", "created", "both". Linear has no OR across
// two root filters in a single connection, so "both" runs two aliased
// connections in one request and the results are merged client side.
function buildIssuesQuery(options) {
    const opts = options || {}
    const scope = opts.scope === "created" || opts.scope === "both" ? opts.scope : "assigned"
    const first = Math.max(1, Math.min(250, opts.maxIssues || 50))

    const excluded = ["completed", "canceled"]
    if (!opts.includeBacklog)
        excluded.push("backlog")

    const stateFilter = "state: { type: { nin: $excludedTypes } }"
    const assigned = "assigned: issues(first: $first, orderBy: updatedAt, filter: { assignee: { isMe: { eq: true } }, " + stateFilter + " }) { nodes {" + ISSUE_FIELDS + "} }"
    const created = "created: issues(first: $first, orderBy: updatedAt, filter: { creator: { isMe: { eq: true } }, " + stateFilter + " }) { nodes {" + ISSUE_FIELDS + "} }"

    var connections = assigned
    if (scope === "created")
        connections = created
    else if (scope === "both")
        connections = assigned + "\n  " + created

    return {
        "query": "query DmsLinearIssues($first: Int!, $excludedTypes: [String!]) {\n  viewer { id name displayName }\n  " + connections + "\n}",
        "variables": {
            "first": first,
            "excludedTypes": excluded
        }
    }
}

function buildStatesQuery(teamIds) {
    return {
        "query": "query DmsLinearStates($teamIds: [ID!]) {\n  workflowStates(first: 250, filter: { team: { id: { in: $teamIds } } }) {\n    nodes { id name type color position team { id } }\n  }\n}",
        "variables": {
            "teamIds": teamIds || []
        }
    }
}

function buildSetStateMutation(issueId, stateId) {
    return {
        "query": "mutation DmsLinearSetState($id: String!, $stateId: String!) {\n  issueUpdate(id: $id, input: { stateId: $stateId }) {\n    success\n    issue { id identifier state { id name type color position } }\n  }\n}",
        "variables": {
            "id": issueId,
            "stateId": stateId
        }
    }
}

// --- response handling -----------------------------------------------------

// Linear answers GraphQL-level problems with HTTP 200 and an `errors` array,
// so a non-empty body still has to be inspected before it can be trusted.
function parseResponse(raw) {
    const text = trimmed(raw)
    if (!text)
        return {
            "ok": false,
            "error": "No response from Linear"
        }

    var json = null
    try {
        json = JSON.parse(text)
    } catch (e) {
        return {
            "ok": false,
            "error": "Unexpected response from Linear"
        }
    }

    if (json && json.errors && json.errors.length > 0) {
        const message = trimmed(json.errors[0].message) || "Linear rejected the request"
        return {
            "ok": false,
            "error": friendlyError(message),
            "raw": json
        }
    }

    if (!json || !json.data)
        return {
            "ok": false,
            "error": "Linear returned no data"
        }

    return {
        "ok": true,
        "data": json.data
    }
}

function friendlyError(message) {
    const lower = String(message || "").toLowerCase()
    if (lower.indexOf("authentication") !== -1 || lower.indexOf("not authenticated") !== -1)
        return "API key rejected — check it in settings"
    if (lower.indexOf("rate limit") !== -1)
        return "Rate limited by Linear — try again shortly"
    return message
}

function normalizeIssue(node) {
    if (!node || !node.id)
        return null

    const state = node.state || {}
    const team = node.team || {}
    const labelNodes = node.labels && node.labels.nodes ? node.labels.nodes : []

    return {
        "id": node.id,
        "identifier": trimmed(node.identifier),
        "title": trimmed(node.title) || "Untitled",
        "url": trimmed(node.url),
        "branchName": trimmed(node.branchName),
        "priority": typeof node.priority === "number" ? node.priority : 0,
        "dueDate": trimmed(node.dueDate),
        "updatedAt": trimmed(node.updatedAt),
        "stateId": trimmed(state.id),
        "stateName": trimmed(state.name) || "Unknown",
        "stateType": trimmed(state.type) || "unstarted",
        "stateColor": trimmed(state.color) || "#8a8f98",
        "teamId": trimmed(team.id),
        "teamKey": trimmed(team.key),
        "teamName": trimmed(team.name),
        "projectName": node.project ? trimmed(node.project.name) : "",
        "labels": labelNodes.map(label => ({
                    "id": trimmed(label.id),
                    "name": trimmed(label.name),
                    "color": trimmed(label.color) || "#8a8f98"
                })).filter(label => label.name !== "")
    }
}

// Merges the aliased `assigned` / `created` connections, dropping the overlap
// that shows up when you filed an issue and it is also assigned to you.
function normalizeIssues(data) {
    const buckets = [data && data.assigned ? data.assigned.nodes : null, data && data.created ? data.created.nodes : null]
    const seen = {}
    const out = []

    for (var b = 0; b < buckets.length; b++) {
        const nodes = buckets[b] || []
        for (var i = 0; i < nodes.length; i++) {
            const issue = normalizeIssue(nodes[i])
            if (!issue || seen[issue.id])
                continue
            seen[issue.id] = true
            out.push(issue)
        }
    }
    return out
}

function normalizeStates(data) {
    const nodes = data && data.workflowStates ? data.workflowStates.nodes || [] : []
    const byTeam = {}

    for (var i = 0; i < nodes.length; i++) {
        const node = nodes[i]
        const teamId = node.team ? trimmed(node.team.id) : ""
        if (!teamId)
            continue
        if (!byTeam[teamId])
            byTeam[teamId] = []
        byTeam[teamId].push({
            "id": trimmed(node.id),
            "name": trimmed(node.name),
            "type": trimmed(node.type),
            "color": trimmed(node.color) || "#8a8f98",
            "position": typeof node.position === "number" ? node.position : 0
        })
    }

    const teamIds = Object.keys(byTeam)
    for (var t = 0; t < teamIds.length; t++)
        byTeam[teamIds[t]].sort(compareStates)

    return byTeam
}

function compareStates(a, b) {
    const typeDelta = stateTypeRank(a.type) - stateTypeRank(b.type)
    if (typeDelta !== 0)
        return typeDelta
    return a.position - b.position
}

function stateTypeRank(type) {
    const index = STATE_TYPE_ORDER.indexOf(String(type || ""))
    return index === -1 ? STATE_TYPE_ORDER.length : index
}

function stateTypeLabel(type) {
    return STATE_TYPE_LABEL[String(type || "")] || "Other"
}

function teamIdsOf(issues) {
    return uniq((issues || []).map(issue => issue.teamId)).filter(id => id !== "")
}

// --- ordering and grouping -------------------------------------------------

// Linear treats 0 as "no priority" rather than the most urgent, so it sorts
// below Low instead of above Urgent.
function prioritySortKey(priority) {
    return priority === 0 ? 5 : priority
}

function compareIssues(a, b) {
    const priorityDelta = prioritySortKey(a.priority) - prioritySortKey(b.priority)
    if (priorityDelta !== 0)
        return priorityDelta
    return String(b.updatedAt).localeCompare(String(a.updatedAt))
}

function sortIssues(issues) {
    return (issues || []).slice().sort(compareIssues)
}

// One section per state type, in board order, each already sorted.
function groupIssues(issues) {
    const byType = {}
    const list = issues || []

    for (var i = 0; i < list.length; i++) {
        const type = list[i].stateType
        if (!byType[type])
            byType[type] = []
        byType[type].push(list[i])
    }

    const sections = []
    for (var t = 0; t < STATE_TYPE_ORDER.length; t++) {
        const type = STATE_TYPE_ORDER[t]
        if (!byType[type])
            continue
        sections.push({
            "type": type,
            "label": stateTypeLabel(type),
            "issues": sortIssues(byType[type])
        })
    }
    return sections
}

function countStarted(issues) {
    return (issues || []).filter(issue => issue.stateType === "started").length
}

// --- display ---------------------------------------------------------------

var PRIORITY_META = [{
        "label": "No priority",
        "icon": "remove",
        "urgent": false
    }, {
        "label": "Urgent",
        "icon": "priority_high",
        "urgent": true
    }, {
        "label": "High",
        "icon": "keyboard_double_arrow_up",
        "urgent": false
    }, {
        "label": "Medium",
        "icon": "keyboard_arrow_up",
        "urgent": false
    }, {
        "label": "Low",
        "icon": "keyboard_arrow_down",
        "urgent": false
    }]

function priorityMeta(priority) {
    const index = typeof priority === "number" && priority >= 0 && priority < PRIORITY_META.length ? priority : 0
    return PRIORITY_META[index]
}

// Linear draws each state type as a distinct glyph; these Material Symbols are
// the closest read-at-a-glance equivalents.
function stateIcon(type) {
    switch (String(type || "")) {
    case "started":
        return "timelapse"
    case "completed":
        return "check_circle"
    case "canceled":
        return "cancel"
    case "triage":
        return "error"
    case "backlog":
        return "circle"
    default:
        return "radio_button_unchecked"
    }
}

// The desktop app registers the linear:// scheme and mirrors the web path, so
// the deep link is the web URL with the scheme swapped.
function deepLink(url) {
    const web = trimmed(url)
    if (web.indexOf("https://linear.app/") !== 0)
        return ""
    return "linear://" + web.slice("https://linear.app/".length)
}

function formatRelative(then, now) {
    if (!then)
        return ""
    const thenMs = then instanceof Date ? then.getTime() : new Date(then).getTime()
    const nowMs = now instanceof Date ? now.getTime() : (now || Date.now())
    if (isNaN(thenMs))
        return ""

    const seconds = Math.round((nowMs - thenMs) / 1000)
    if (seconds < 45)
        return "just now"
    const minutes = Math.round(seconds / 60)
    if (minutes < 60)
        return minutes + "m ago"
    const hours = Math.round(minutes / 60)
    if (hours < 24)
        return hours + "h ago"
    const days = Math.round(hours / 24)
    if (days < 7)
        return days + "d ago"
    return Math.round(days / 7) + "w ago"
}

// Linear due dates are plain calendar days (YYYY-MM-DD) with no timezone, so
// they are compared as days rather than instants.
function formatDueDate(dueDate, now) {
    const raw = trimmed(dueDate)
    if (!raw)
        return {
            "label": "",
            "overdue": false,
            "soon": false
        }

    const parts = raw.split("-")
    if (parts.length < 3)
        return {
            "label": raw,
            "overdue": false,
            "soon": false
        }

    const due = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    const today = now instanceof Date ? new Date(now.getTime()) : new Date(now || Date.now())
    today.setHours(0, 0, 0, 0)

    const days = Math.round((due.getTime() - today.getTime()) / 86400000)
    if (days < 0)
        return {
            "label": days === -1 ? "1d overdue" : Math.abs(days) + "d overdue",
            "overdue": true,
            "soon": false
        }
    if (days === 0)
        return {
            "label": "Due today",
            "overdue": false,
            "soon": true
        }
    if (days === 1)
        return {
            "label": "Due tomorrow",
            "overdue": false,
            "soon": true
        }
    if (days <= 7)
        return {
            "label": "Due in " + days + "d",
            "overdue": false,
            "soon": true
        }

    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return {
        "label": "Due " + months[due.getMonth()] + " " + due.getDate(),
        "overdue": false,
        "soon": false
    }
}
