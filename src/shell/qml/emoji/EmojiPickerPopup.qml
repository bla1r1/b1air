import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../Ui"
import "../Services"

// =============================================================================
// Native Emoji Picker Popup (Super + .)
// =============================================================================

PopupShell {
    id: window

    padding: Design.space.md

    property string query: ""
    property int selectedIndex: 0

    readonly property var emojis: [
        // Smileys & Emotion
        { e: "😀", n: "grinning smile happy", c: "Smileys" },
        { e: "😃", n: "smiley happy joy", c: "Smileys" },
        { e: "😄", n: "smile laugh joy", c: "Smileys" },
        { e: "😁", n: "grin beaming", c: "Smileys" },
        { e: "😆", n: "laughing squint", c: "Smileys" },
        { e: "😅", n: "sweat smile relief", c: "Smileys" },
        { e: "😂", n: "joy tears laugh cry", c: "Smileys" },
        { e: "🤣", n: "rofl rolling laughing", c: "Smileys" },
        { e: "😊", n: "blush smile pleased", c: "Smileys" },
        { e: "😇", n: "innocent angel halo", c: "Smileys" },
        { e: "🙂", n: "slightly smiling", c: "Smileys" },
        { e: "🙃", n: "upside down sarcastic", c: "Smileys" },
        { e: "😉", n: "wink play flirt", c: "Smileys" },
        { e: "😌", n: "relieved calm peace", c: "Smileys" },
        { e: "😍", n: "heart eyes love crush", c: "Smileys" },
        { e: "🥰", n: "smiling hearts adore", c: "Smileys" },
        { e: "😘", n: "blow kiss love", c: "Smileys" },
        { e: "😋", n: "yum delicious taste", c: "Smileys" },
        { e: "😛", n: "tongue silly playful", c: "Smileys" },
        { e: "😜", n: "wink tongue crazy", c: "Smileys" },
        { e: "🤪", n: "zany wild goofy", c: "Smileys" },
        { e: "🤨", n: "raised eyebrow skeptic", c: "Smileys" },
        { e: "🧐", n: "monocle curious observe", c: "Smileys" },
        { e: "🤓", n: "nerd geek code tech", c: "Smileys" },
        { e: "😎", n: "sunglasses cool boss", c: "Smileys" },
        { e: "🥳", n: "party celebrate hat", c: "Smileys" },
        { e: "😏", n: "smirk smirk suggest", c: "Smileys" },
        { e: "😒", n: "unamused annoyed", c: "Smileys" },
        { e: "😞", n: "disappointed sad", c: "Smileys" },
        { e: "😔", n: "pensive thoughtful", c: "Smileys" },
        { e: "😟", n: "worried concern", c: "Smileys" },
        { e: "😕", n: "confused puzzled", c: "Smileys" },
        { e: "🙁", n: "slight frown", c: "Smileys" },
        { e: "😣", n: "persevering struggle", c: "Smileys" },
        { e: "😖", n: "confounded upset", c: "Smileys" },
        { e: "😫", n: "tired exhausted", c: "Smileys" },
        { e: "😩", n: "weary groan", c: "Smileys" },
        { e: "🥺", n: "pleading begging puppy", c: "Smileys" },
        { e: "😢", n: "crying tear sad", c: "Smileys" },
        { e: "😭", n: "sob loud cry scream", c: "Smileys" },
        { e: "😤", n: "triumph steam proud", c: "Smileys" },
        { e: "😠", n: "angry mad annoyed", c: "Smileys" },
        { e: "😡", n: "rage pouting furious", c: "Smileys" },
        { e: "🤬", n: "cursing swear angry", c: "Smileys" },
        { e: "🤯", n: "exploding head mind blown", c: "Smileys" },
        { e: "😳", n: "flushed shocked blush", c: "Smileys" },
        { e: "🥵", n: "hot sweating summer", c: "Smileys" },
        { e: "🥶", n: "cold freezing winter", c: "Smileys" },
        { e: "😱", n: "scream fear scared", c: "Smileys" },
        { e: "😨", n: "fearful anxious", c: "Smileys" },
        { e: "😰", n: "sweat anxious", c: "Smileys" },
        { e: "😥", n: "relieved sweat sad", c: "Smileys" },
        { e: "🤤", n: "drooling hungry", c: "Smileys" },
        { e: "😴", n: "sleeping tired zzz", c: "Smileys" },
        { e: "😷", n: "mask sick doctor", c: "Smileys" },
        { e: "🤒", n: "thermometer fever sick", c: "Smileys" },
        { e: "🤕", n: "bandage hurt injured", c: "Smileys" },
        { e: "🤢", n: "nausea gross green", c: "Smileys" },
        { e: "🤮", n: "vomit puking sick", c: "Smileys" },
        { e: "🤧", n: "sneezing tissue cold", c: "Smileys" },
        { e: "😵", n: "dizzy dead knocked out", c: "Smileys" },
        { e: "🤐", n: "zipper mouth quiet secret", c: "Smileys" },
        { e: "🥴", n: "woozy drunk groggy", c: "Smileys" },
        { e: "🤢", n: "nauseated ill", c: "Smileys" },
        { e: "🤡", n: "clown circus joke", c: "Smileys" },
        { e: "💩", n: "poop crap feces", c: "Smileys" },
        { e: "👻", n: "ghost spooky boo", c: "Smileys" },
        { e: "💀", n: "skull skeleton dead rip", c: "Smileys" },
        { e: "👽", n: "alien ufo space", c: "Smileys" },
        { e: "🤖", n: "robot bot ai tech", c: "Smileys" },

        // Gestures & Hands
        { e: "👍", n: "thumbs up approve ok good yes", c: "Gestures" },
        { e: "👎", n: "thumbs down dislike no bad", c: "Gestures" },
        { e: "👌", n: "ok hand perfect fine", c: "Gestures" },
        { e: "✌️", n: "victory peace two", c: "Gestures" },
        { e: "🤞", n: "crossed fingers luck hope", c: "Gestures" },
        { e: "🤟", n: "love you gesture rock", c: "Gestures" },
        { e: "🤘", n: "rock on metal horns", c: "Gestures" },
        { e: "🤙", n: "call me shaka phone", c: "Gestures" },
        { e: "👈", n: "point left", c: "Gestures" },
        { e: "👉", n: "point right", c: "Gestures" },
        { e: "👆", n: "point up", c: "Gestures" },
        { e: "👇", n: "point down", c: "Gestures" },
        { e: "☝️", n: "point up index one", c: "Gestures" },
        { e: "✋", n: "raised hand stop high five", c: "Gestures" },
        { e: "🤚", n: "backhand raised hand", c: "Gestures" },
        { e: "🖐️", n: "hand splayed fingers five", c: "Gestures" },
        { e: "🖖", n: "vulcan salute spock", c: "Gestures" },
        { e: "👋", n: "wave waving hello bye", c: "Gestures" },
        { e: "🤝", n: "handshake deal agreement", c: "Gestures" },
        { e: "🙏", n: "pray please thank you namaste", c: "Gestures" },
        { e: "✍️", n: "writing hand pen signature", c: "Gestures" },
        { e: "👏", n: "clap applause cheer bravo", c: "Gestures" },
        { e: "🙌", n: "raising hands celebrate praise", c: "Gestures" },
        { e: "👐", n: "open hands hug", c: "Gestures" },
        { e: "🤲", n: "palms up together offering", c: "Gestures" },
        { e: "💪", n: "flex bicep muscle strong power", c: "Gestures" },

        // Tech, Dev, Rockets & Work
        { e: "🔥", n: "fire hot lit trending burn lit", c: "Tech" },
        { e: "🚀", n: "rocket launch space fast ship", c: "Tech" },
        { e: "✨", n: "sparkles shiny clean magic new", c: "Tech" },
        { e: "💡", n: "lightbulb idea brainstorm insight", c: "Tech" },
        { e: "💻", n: "laptop computer tech dev coding", c: "Tech" },
        { e: "🖥️", n: "desktop computer monitor pc", c: "Tech" },
        { e: "📱", n: "mobile phone smartphone iphone", c: "Tech" },
        { e: "⌨️", n: "keyboard typing input hardware", c: "Tech" },
        { e: "🖱️", n: "computer mouse click cursor", c: "Tech" },
        { e: "💾", n: "floppy disk save storage retro", c: "Tech" },
        { e: "⚙️", n: "gear settings config mechanism", c: "Tech" },
        { e: "🔧", n: "wrench tool fix debug maintenance", c: "Tech" },
        { e: "🔨", n: "hammer build create work", c: "Tech" },
        { e: "📦", n: "package box deliver crate parcel", c: "Tech" },
        { e: "🔒", n: "lock secure privacy password safe", c: "Tech" },
        { e: "🔓", n: "unlock open access public", c: "Tech" },
        { e: "🔑", n: "key password secret auth token", c: "Tech" },
        { e: "🛡️", n: "shield defense security protect", c: "Tech" },
        { e: "⚡", n: "zap lightning fast power bolt", c: "Tech" },
        { e: "🌐", n: "globe internet web world network", c: "Tech" },
        { e: "📶", n: "antenna bars wifi signal cellular", c: "Tech" },
        { e: "🔋", n: "battery power energy charging", c: "Tech" },
        { e: "🎉", n: "party popper tada congrats celebrate", c: "Tech" },
        { e: "🎊", n: "confetti ball celebrate fiesta", c: "Tech" },
        { e: "🏆", n: "trophy winner award champion", c: "Tech" },
        { e: "🎯", n: "bullseye target goal accurate aim", c: "Tech" },
        { e: "🎨", n: "palette art design color ui theme", c: "Tech" },
        { e: "☕", n: "coffee tea caffeine espresso drink", c: "Tech" },
        { e: "❤️", n: "red heart love favorite passion", c: "Tech" },
        { e: "💜", n: "purple heart tokyo night aesthetic", c: "Tech" },
        { e: "💙", n: "blue heart sapphire trust", c: "Tech" },
        { e: "💚", n: "green heart safe verified success", c: "Tech" },
        { e: "💛", n: "yellow heart warm energy", c: "Tech" },
        { e: "🧡", n: "orange heart vibrant warm", c: "Tech" },
        { e: "🖤", n: "black heart dark gothic", c: "Tech" },
        { e: "🤍", n: "white heart pure clean", c: "Tech" },
        { e: "💯", n: "hundred percent perfect score", c: "Tech" },
        { e: "✅", n: "check mark done success approved", c: "Tech" },
        { e: "❌", n: "cross mark cancel error failed", c: "Tech" },
        { e: "⚠️", n: "warning caution alert attention", c: "Tech" }
    ]

    readonly property var filteredList: {
        const q = window.query.trim().toLowerCase();
        if (!q) return window.emojis;
        return window.emojis.filter(item => {
            return item.n.includes(q) || item.c.toLowerCase().includes(q);
        });
    }

    function selectEmoji(emojiStr) {
        Quickshell.execDetached(["b1air-clip", "copy", "--", emojiStr]);
        window.close();
    }

    Component.onCompleted: {
        searchInput.forceActiveFocus();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.sm)

        // ── Search Bar ───────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(40)
            radius: Design.s(Design.radius.ctl)
            color: Design.well
            border.color: searchInput.activeFocus ? Design.accent : Design.veilStrong
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.sm)
                anchors.rightMargin: Design.s(Design.space.sm)
                spacing: Design.s(Design.space.sm)

                Icon {
                    text: "\u{f002}"
                    role: "caption"
                    color: searchInput.activeFocus ? Design.accent : Design.textDim
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(14)
                    color: Design.text
                    selectByMouse: true
                    clip: true

                    text: window.query
                    onTextChanged: window.query = text

                    Keys.onEscapePressed: window.close()
                    Keys.onReturnPressed: {
                        if (window.filteredList.length > 0) {
                            window.selectEmoji(window.filteredList[0].e);
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Search emojis (e.g. fire, rocket, love, tech)...")
                        color: Design.textDim
                        role: "caption"
                        visible: !searchInput.text && !searchInput.activeFocus
                    }
                }

                IconButton {
                    visible: searchInput.text.length > 0
                    icon: "\u{f00d}"
                    role: "caption"
                    onClicked: {
                        searchInput.text = "";
                        searchInput.forceActiveFocus();
                    }
                }
            }
        }

        // ── Emojis Grid ──────────────────────────────────────────────────────
        GridView {
            id: emojiGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: Design.s(46)
            cellHeight: Design.s(46)
            model: window.filteredList
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: OverflowBar {}

            delegate: Rectangle {
                id: emojiCell
                required property var modelData
                required property int index

                width: Design.s(40)
                height: Design.s(40)
                radius: Design.s(Design.radius.ctl)
                color: cellHover.containsMouse ? Design.tint(Design.accent, 0.2) : "transparent"
                border.color: cellHover.containsMouse ? Design.accent : "transparent"
                border.width: 1

                scale: cellHover.containsMouse ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Easing.OutQuad } }

                Text {
                    anchors.centerIn: parent
                    text: emojiCell.modelData.e
                    font.pixelSize: Design.s(22)
                }

                Clickable {
                    id: cellHover
                    hoverEnabled: true
                    onClicked: window.selectEmoji(emojiCell.modelData.e)
                }
            }
        }

        // ── Bottom Status Bar ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Label {
                text: I18n.trn("%1 emoji", "%1 emojis", window.filteredList.length)
                role: "caption"
                dim: true
                Layout.fillWidth: true
            }

            Label {
                text: I18n.tr("Click or Enter to copy")
                role: "caption"
                dim: true
            }
        }
    }
}
