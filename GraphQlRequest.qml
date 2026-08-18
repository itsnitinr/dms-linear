// One Linear GraphQL round trip over curl.
//
// Wraps the Process so callers get a single `succeeded`/`failed` pair instead
// of having to reconcile the stdout stream finishing and the process exiting,
// which arrive independently.
import QtQuick
import Quickshell.Io
import "Linear.js" as Linear

Item {
    id: root

    property int timeoutSeconds: 20
    readonly property bool running: proc.running

    signal succeeded(var data)
    signal failed(string message)

    property string _config: ""
    property string _body: ""
    property string _stderr: ""
    property int _exitCode: 0
    property bool _bodyDone: false
    property bool _exitDone: false

    visible: false
    width: 0
    height: 0

    function send(apiKey, payload) {
        if (proc.running)
            return false

        root._config = Linear.curlConfig(apiKey, payload, root.timeoutSeconds)
        root._body = ""
        root._stderr = ""
        root._exitCode = 0
        root._bodyDone = false
        root._exitDone = false

        proc.stdinEnabled = true
        proc.command = ["curl", "-K", "-"]
        proc.running = true
        return true
    }

    // Reports once both the stream and the exit code have landed, so a curl
    // transport failure is never mistaken for an empty Linear response.
    function _settle() {
        if (!root._bodyDone || !root._exitDone)
            return

        if (root._exitCode !== 0 && root._body === "") {
            root.failed(root._transportError())
            return
        }

        const result = Linear.parseResponse(root._body)
        if (result.ok)
            root.succeeded(result.data)
        else
            root.failed(result.error)
    }

    function _transportError() {
        const detail = String(root._stderr || "").trim().replace(/^curl:\s*\(\d+\)\s*/, "")
        if (root._exitCode === 28)
            return "Linear timed out"
        if (detail !== "")
            return detail
        return "Could not reach Linear"
    }

    Process {
        id: proc

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root._body = text
                root._bodyDone = true
                root._settle()
            }
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root._stderr = text
        }

        onStarted: {
            proc.write(root._config)
            proc.stdinEnabled = false
        }

        onExited: exitCode => {
            root._exitCode = exitCode
            root._exitDone = true
            root._settle()
        }
    }
}
