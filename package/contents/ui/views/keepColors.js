.pragma library

// Presentation of note colors. Provider color names (Keep's: DEFAULT, RED, ...) map to shades;
// DEFAULT and unknown names mean "no color" and use the theme. Two palettes are used, like the
// Keep apps: pastel on light themes, muted on dark themes.

var _light = {
    RED: "#f28b82", ORANGE: "#fbbc04", YELLOW: "#fff475", GREEN: "#ccff90",
    TEAL: "#a7ffeb", BLUE: "#cbf0f8", CERULEAN: "#aecbfa", PURPLE: "#d7aefb",
    PINK: "#fdcfe8", BROWN: "#e6c9a8", GRAY: "#e8eaed"
}

var _dark = {
    RED: "#5c2b29", ORANGE: "#614a19", YELLOW: "#635d19", GREEN: "#345920",
    TEAL: "#16504b", BLUE: "#2d555e", CERULEAN: "#1e3a5f", PURPLE: "#42275e",
    PINK: "#5b2245", BROWN: "#442f19", GRAY: "#3c3f43"
}

var TEXT_ON_LIGHT = "#202124"
var TEXT_ON_DARK = "#e8eaed"

// Kept for existing callers that only know the light palette.
var TEXT_ON_COLOR = TEXT_ON_LIGHT

// Display order of the swatches.
var NAMES = ["DEFAULT", "RED", "ORANGE", "YELLOW", "GREEN", "TEAL", "BLUE",
             "CERULEAN", "PURPLE", "PINK", "BROWN", "GRAY"]

function names() {
    return NAMES.slice()
}

// True when the color has a dedicated shade ("DEFAULT" and unknown names do not).
function has(name) {
    return name in _light
}

// Shade for `name`, "" when the theme color should be used.
function background(name, dark) {
    var palette = dark ? _dark : _light
    return name in palette ? palette[name] : ""
}

// Text color that is readable on background(name, dark).
function textOn(name, dark) {
    return dark ? TEXT_ON_DARK : TEXT_ON_LIGHT
}

// Relative luminance (WCAG) of a color given as "#rrggbb" or {r, g, b} in 0..1.
function luminance(color) {
    var c = _rgb(color)
    function lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
}

// WCAG contrast ratio between two colors.
function contrast(a, b) {
    var la = luminance(a)
    var lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// Whether a theme background color is dark (use the dark palette).
function isDark(color) {
    return luminance(color) < 0.4
}

function _rgb(color) {
    if (typeof color === "string") {
        var s = color.charAt(0) === "#" ? color.substring(1) : color
        return {
            r: parseInt(s.substring(0, 2), 16) / 255,
            g: parseInt(s.substring(2, 4), 16) / 255,
            b: parseInt(s.substring(4, 6), 16) / 255
        }
    }
    return { r: color.r, g: color.g, b: color.b }
}
