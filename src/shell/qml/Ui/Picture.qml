import QtQuick

// A picture from a file or a URL: the one way an app shows one, so how
// pictures are decoded and scaled is decided here. Smooth by default, as a
// picture drawn at another size than its own should be.
Image {
    smooth: true
}
