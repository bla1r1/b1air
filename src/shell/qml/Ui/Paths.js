.pragma library

// A local path as a file:// URL, each segment percent-encoded.
//
// "file://" + path is not a URL for every path: a "#" starts the fragment
// and a "%" an escape, so a folder named "C# notes" listed nothing and a
// photo named "100%.jpg" did not open. Already-URLs pass through.
function fileUrl(path) {
    if (!path) return "";
    path = String(path);
    if (path.indexOf("file:") === 0 || path.indexOf("image:") === 0 || path.indexOf("qrc:") === 0)
        return path;
    return "file://" + path.split("/").map(encodeURIComponent).join("/");
}
