import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "linearIssues"

    StyledText {
        width: parent.width
        text: "Create a personal API key at linear.app → Settings → Security & access → Personal API keys. A read-only key is enough to browse issues, but changing a status needs write access."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SecretSetting {
        settingKey: "apiKey"
        label: "Personal API key"
        description: "Stored in plugin_settings.json. Leave this empty if you use the key command below."
        placeholder: "lin_api_..."
        defaultValue: ""
    }

    StringSetting {
        settingKey: "apiKeyCommand"
        label: "API key command"
        description: "Optional. A shell command that prints the key on stdout, e.g. `pass show linear/api`. Takes precedence over the field above, so nothing secret has to sit on disk."
        placeholder: "pass show linear/api"
        defaultValue: ""
    }

    SelectionSetting {
        settingKey: "scope"
        label: "Issues to show"
        description: "Which of your issues appear in the popout"
        options: [
            {
                "label": "Assigned to me",
                "value": "assigned"
            },
            {
                "label": "Created by me",
                "value": "created"
            },
            {
                "label": "Assigned to or created by me",
                "value": "both"
            }
        ]
        defaultValue: "assigned"
    }

    ToggleSetting {
        settingKey: "includeBacklog"
        label: "Include backlog"
        description: "Show issues still sitting in the backlog alongside your todo and in-progress work"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "refreshMinutes"
        label: "Refresh interval"
        description: "How often to poll Linear for changes"
        options: [
            {
                "label": "1 minute",
                "value": "1"
            },
            {
                "label": "2 minutes",
                "value": "2"
            },
            {
                "label": "5 minutes",
                "value": "5"
            },
            {
                "label": "15 minutes",
                "value": "15"
            },
            {
                "label": "30 minutes",
                "value": "30"
            }
        ]
        defaultValue: "5"
    }

    SelectionSetting {
        settingKey: "maxIssues"
        label: "Maximum issues"
        description: "Upper bound on how many issues are fetched"
        options: [
            {
                "label": "25",
                "value": "25"
            },
            {
                "label": "50",
                "value": "50"
            },
            {
                "label": "100",
                "value": "100"
            },
            {
                "label": "250",
                "value": "250"
            }
        ]
        defaultValue: "50"
    }

    ToggleSetting {
        settingKey: "preferDesktopApp"
        label: "Open in the Linear app"
        description: "Use the linear:// deep link when the desktop app is installed, otherwise fall back to the browser"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showCount"
        label: "Show issue count in the bar"
        description: "Put the number of open issues next to the bar icon instead of just a dot"
        defaultValue: false
    }
}
