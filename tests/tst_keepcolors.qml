import QtQuick
import QtTest
import "../package/contents/ui/views/keepColors.js" as KeepColors
import "../package/contents/code/providers/keep/nodes.js" as Nodes

TestCase {
    name: "KeepColors"

    function test_namesMatchProviderColorsInOrder() {
        compare(KeepColors.names().join(), Nodes.COLORS.join())
        compare(KeepColors.names()[0], "DEFAULT")
        compare(KeepColors.names().length, 12)
    }

    function test_everyNamedColorHasAShadeInBothPalettes() {
        KeepColors.names().forEach(function (name) {
            if (name === "DEFAULT")
                return
            verify(KeepColors.background(name, false) !== "", name + " light")
            verify(KeepColors.background(name, true) !== "", name + " dark")
            verify(KeepColors.has(name), name)
        })
    }

    function test_defaultAndUnknownUseTheTheme() {
        compare(KeepColors.background("DEFAULT", false), "")
        compare(KeepColors.background("DEFAULT", true), "")
        compare(KeepColors.background("NO_SUCH_COLOR", false), "")
        verify(!KeepColors.has("DEFAULT"))
        verify(!KeepColors.has("NO_SUCH_COLOR"))
    }

    function test_paletteDiffersBetweenThemes() {
        KeepColors.names().slice(1).forEach(function (name) {
            verify(KeepColors.background(name, false) !== KeepColors.background(name, true), name)
        })
    }

    function test_textIsReadableOnEveryShade() {
        [false, true].forEach(function (dark) {
            KeepColors.names().slice(1).forEach(function (name) {
                var ratio = KeepColors.contrast(KeepColors.textOn(name, dark), KeepColors.background(name, dark))
                verify(ratio >= 4.5, name + (dark ? " dark" : " light") + " contrast " + ratio.toFixed(2))
            })
        })
    }

    function test_darkPaletteIsActuallyDark() {
        KeepColors.names().slice(1).forEach(function (name) {
            verify(KeepColors.luminance(KeepColors.background(name, true)) < 0.2, name)
            verify(KeepColors.luminance(KeepColors.background(name, false)) > 0.3, name)
        })
    }

    function test_luminanceAndContrast() {
        fuzzyCompare(KeepColors.luminance("#000000"), 0, 0.001)
        fuzzyCompare(KeepColors.luminance("#ffffff"), 1, 0.001)
        fuzzyCompare(KeepColors.contrast("#000000", "#ffffff"), 21, 0.01)
        fuzzyCompare(KeepColors.contrast("#777777", "#777777"), 1, 0.001)
        fuzzyCompare(KeepColors.luminance({ r: 1, g: 1, b: 1 }), 1, 0.001)
    }

    function test_isDarkFollowsThemeBackground() {
        verify(KeepColors.isDark("#1b1e20"))        // Breeze Dark window background
        verify(KeepColors.isDark("#232629"))
        verify(!KeepColors.isDark("#eff0f1"))       // Breeze Light window background
        verify(!KeepColors.isDark("#ffffff"))
    }
}
