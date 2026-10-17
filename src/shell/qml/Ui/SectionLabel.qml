import QtQuick

// =============================================================================
// The small uppercase mono caption above a list — "OUTPUT DEVICES".
//
// Written out four times in the Control Center, each repeating the same four
// properties, and each free to disagree about the letter spacing.
// =============================================================================

Label {
    // The same small heading as the sidebars' SidebarHeading: sans,
    // semibold, dim. Monospace capitals read as a terminal, not a form.
    role: "caption"
    weight: Design.weight.semibold
    dim: true

    // In a SettingsGroup it heads the part below it, so the group gives it
    // more room above than below (see SettingsGroup._padChildren).
    readonly property bool sectionLabel: true
}
