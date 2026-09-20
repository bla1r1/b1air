import QtQuick
import QtQuick.Layouts
import "../../Ui"
import "../../Services"

Card {
    id: section

    property string apiKey: ""
    property string cityId: ""
    property string unit: "metric"
    signal apiKeyChangedByUser(string value)
    signal cityIdChangedByUser(string value)
    signal unitChangedByUser(string value)

    title: "Weather"
    subtitle: "Used by the bar, the calendar and the lock screen. The key is kept in the encrypted secret store, not in the settings file."
    icon: "\u{f0590}"
    accentColor: Design.yellow

    // What the forecast is coming from right now. This used to test the key
    // field, which is always empty — the key is in the secret store, not the
    // settings file — so the page said wttr.in with a key saved. And the city
    // and the unit were saved and never read by the daemon, so OpenWeather
    // never ran from here and Fahrenheit changed nothing (both fixed there).
    readonly property bool usingOpenWeather: Settings.weatherKeyStored && section.cityId !== ""

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        role: "caption"
        dim: true
        text: section.usingOpenWeather
            ? "Using OpenWeather with your saved key: five days ahead. Remove the key or clear the city to go back to wttr.in."
            : Settings.weatherKeyStored
                ? "A key is saved. Add a city ID below and the forecast switches to OpenWeather."
                : "Optional. Right now the forecast comes from wttr.in, which needs no key and reaches three days ahead. Save an OpenWeather key and a city ID for five days."
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Design.s(Design.space.xs)

        Label { text: "OpenWeather API key"; role: "caption"; dim: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            // Saved on Enter only. It used to save on losing focus as well,
            // and the field is always empty, so clicking into it and away
            // again overwrote the stored key with nothing.
            Field {
                mono: true
                id: keyField
                Layout.fillWidth: true
                echoMode: TextInput.Password
                placeholder: Settings.weatherKeyStored
                    ? "Key saved — type a new one and press Enter to replace it"
                    : "32-character key from openweathermap.org, then Enter"
                onAccepted: v => {
                    if (v.trim() === "") return;
                    section.apiKeyChangedByUser(v.trim());
                    keyField.text = "";
                    refreshSoon.restart();
                }
            }

            ActionButton {
                Layout.fillWidth: false
                visible: Settings.weatherKeyStored
                icon: "\u{f01b4}"
                label: "Remove"
                destructive: true
                onActivated: {
                    section.apiKeyChangedByUser("");
                    refreshSoon.restart();
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Design.s(Design.space.xs)

        Label { text: "City ID"; role: "caption"; dim: true }

        Field {
            mono: true
            Layout.fillWidth: true
            text: section.cityId
            placeholder: "e.g. 703448 for Kyiv — the number in the city's openweathermap.org address"
            validator: RegularExpressionValidator { regularExpression: /[0-9]*/ }
            onCommitted: v => {
                if (v === section.cityId) return;
                section.cityIdChangedByUser(v);
                refreshSoon.restart();
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Design.s(Design.space.xs)

        Label { text: "Units"; role: "caption"; dim: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Repeater {
                model: [
                    { id: "metric", label: "Celsius" },
                    { id: "imperial", label: "Fahrenheit" }
                ]

                Pill {
                    required property var modelData
                    Layout.fillWidth: true
                    label: modelData.label
                    active: section.unit === modelData.id
                    onClicked: {
                        section.unitChangedByUser(modelData.id);
                        refreshSoon.restart();
                    }
                }
            }
        }
    }

    // After the write has landed (Settings.set is not visible to the next
    // read, and the key goes through a separate process), fetch again so the
    // bar and the calendar show the change instead of the cached forecast.
    Timer {
        id: refreshSoon
        interval: 800
        onTriggered: Weather.refresh(true)
    }
}
