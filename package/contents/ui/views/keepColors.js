.pragma library

// Presentation of provider note colors. Keep's color names map to the pastel palette of the
// Keep apps; every other name (including "DEFAULT") means "no color" and uses the theme.
var _palette = {
    RED: "#f28b82", ORANGE: "#fbbc04", YELLOW: "#fff475", GREEN: "#ccff90",
    TEAL: "#a7ffeb", BLUE: "#cbf0f8", CERULEAN: "#aecbfa", PURPLE: "#d7aefb",
    PINK: "#fdcfe8", BROWN: "#e6c9a8", GRAY: "#e8eaed"
}

// Text on the pastel colors must be dark in light and dark themes alike.
var TEXT_ON_COLOR = "#202124"

function has(name) {
    return name in _palette
}

// "" when the color has no dedicated shade.
function background(name) {
    return has(name) ? _palette[name] : ""
}
