// StringSetting with the value masked. Same storage contract — it walks up to
// the enclosing PluginSettings for saveValue/loadValue — but an API key should
// not sit in plain sight in the settings tab.
import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: root

    required property string settingKey
    required property string label
    property string description: ""
    property string placeholder: ""
    property string defaultValue: ""
    property string value: defaultValue
    property bool isInitialized: false

    width: parent.width
    spacing: Theme.spacingS

    function findSettings() {
        let item = parent
        while (item) {
            if (item.saveValue !== undefined && item.loadValue !== undefined)
                return item
            item = item.parent
        }
        return null
    }

    function loadValue() {
        const settings = findSettings()
        if (!settings || !settings.pluginService)
            return
        const loaded = settings.loadValue(settingKey, defaultValue)
        if (textField.activeFocus && isInitialized)
            return
        value = loaded
        textField.text = loaded
        isInitialized = true
    }

    function commit() {
        if (!isInitialized)
            return
        if (textField.text === value)
            return
        value = textField.text
        const settings = findSettings()
        if (settings)
            settings.saveValue(settingKey, value)
    }

    Component.onCompleted: Qt.callLater(loadValue)

    StyledText {
        text: root.label
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.description
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
        visible: root.description !== ""
    }

    DankTextField {
        id: textField

        width: parent.width
        placeholderText: root.placeholder
        echoMode: passwordVisible ? TextInput.Normal : TextInput.Password
        showPasswordToggle: true
        onEditingFinished: root.commit()
        onActiveFocusChanged: {
            if (!activeFocus)
                root.commit()
        }
    }
}
