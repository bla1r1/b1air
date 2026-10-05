import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: input

    signal accepted

    property string placeholder: ""
    property alias input: textField
    property bool isPassword: false
    property bool splitBorderRadius: false
    property alias text: textField.text
    property string icon: ""
    property bool enabled: true
    // A password field gets an eye at its right end: a click shows what was
    // typed, another hides it again.
    property bool revealed: false

    width: Config.passwordInputWidth * Config.generalScale
    height: Config.passwordInputHeight * Config.generalScale

    TextField {
        id: textField
        anchors.fill: parent
        color: Config.passwordInputContentColor
        enabled: input.enabled
        echoMode: input.isPassword && !input.revealed ? TextInput.Password : TextInput.Normal
        passwordCharacter: Config.passwordInputMaskedCharacter
        activeFocusOnTab: true
        selectByMouse: true
        verticalAlignment: TextField.AlignVCenter
        font.family: Config.passwordInputFontFamily
        font.pixelSize: Math.max(8, Config.passwordInputFontSize * Config.generalScale)
        background: Rectangle {
            anchors.fill: parent
            color: Config.passwordInputBackgroundColor
            opacity: Config.passwordInputBackgroundOpacity
            topLeftRadius: Config.passwordInputBorderRadiusLeft * Config.generalScale
            bottomLeftRadius: Config.passwordInputBorderRadiusLeft * Config.generalScale
            topRightRadius: input.splitBorderRadius ? Config.passwordInputBorderRadiusRight * Config.generalScale : Config.passwordInputBorderRadiusLeft * Config.generalScale
            bottomRightRadius: input.splitBorderRadius ? Config.passwordInputBorderRadiusRight * Config.generalScale : Config.passwordInputBorderRadiusLeft * Config.generalScale
        }
        leftPadding: placeholderLabel.x
        rightPadding: input.isPassword ? eye.width + 4 : 10
        onAccepted: input.accepted()

        Item {
            id: eye
            visible: input.isPassword
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: height
            z: 2

            Image {
                id: eyeIcon
                source: Config.getIcon(input.revealed ? "eye-off" : "eye")
                anchors.centerIn: parent
                width: Math.max(1, Config.passwordInputIconSize * Config.generalScale)
                height: width
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectFit
                opacity: eyeArea.containsMouse || input.revealed ? 1.0 : 0.6
                visible: false
            }
            MultiEffect {
                source: eyeIcon
                anchors.fill: eyeIcon
                colorization: 1
                colorizationColor: textField.color
                opacity: eyeIcon.opacity
            }
            MouseArea {
                id: eyeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    input.revealed = !input.revealed;
                    textField.forceActiveFocus();
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            border.width: Config.passwordInputBorderSize * Config.generalScale
            border.color: Config.passwordInputBorderColor
            color: "transparent"
            topLeftRadius: Config.passwordInputBorderRadiusLeft * Config.generalScale
            bottomLeftRadius: Config.passwordInputBorderRadiusLeft * Config.generalScale
            topRightRadius: input.splitBorderRadius ? Config.passwordInputBorderRadiusRight * Config.generalScale : Config.passwordInputBorderRadiusLeft * Config.generalScale
            bottomRightRadius: input.splitBorderRadius ? Config.passwordInputBorderRadiusRight * Config.generalScale : Config.passwordInputBorderRadiusLeft * Config.generalScale
        }

        Row {
            anchors.fill: parent
            spacing: 0
            leftPadding: Config.passwordInputDisplayIcon ? 2 : 10

            Rectangle {
                id: iconContainer
                color: "transparent"
                visible: Config.passwordInputDisplayIcon
                height: parent.height
                width: height

                Image {
                    id: icon
                    source: input.icon
                    anchors.centerIn: parent
                    width: Math.max(1, Config.passwordInputIconSize * Config.generalScale)
                    height: width
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectFit
                    opacity: input.enabled ? 1.0 : 0.3
                    Behavior on opacity {
                        enabled: Config.enableAnimations
                        NumberAnimation {
                            duration: 250
                        }
                    }

                    MultiEffect {
                        source: parent
                        anchors.fill: parent
                        colorization: 1
                        colorizationColor: textField.color
                    }
                }
            }

            Text {
                id: placeholderLabel
                anchors {
                    verticalCenter: parent.verticalCenter
                }
                padding: 0
                visible: textField.text.length === 0 && (!textField.preeditText || textField.preeditText.length === 0)
                text: input.placeholder
                color: textField.color
                font.pixelSize: Math.max(8, textField.font.pixelSize || 12)
                font.family: textField.font.family || "sans-serif"
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: textField.verticalAlignment
                font.italic: true
            }
        }
    }
}
