import QtQuick
import QtTest
import "../package/contents/ui/views/links.js" as Links

TestCase {
    name: "Links"

    function urls(text) {
        return Links.find(text).map(function (l) { return l.url }).join(" ")
    }

    function test_findsWebAddresses() {
        compare(urls("see https://example.com/a?b=1&c=2#d now"), "https://example.com/a?b=1&c=2#d")
        compare(urls("http://x.org ftp://files.x.org/f"), "http://x.org ftp://files.x.org/f")
        compare(urls("HTTPS://EXAMPLE.COM"), "HTTPS://EXAMPLE.COM")
    }

    function test_wwwGetsAScheme() {
        var l = Links.find("go to www.kde.org")
        compare(l.length, 1)
        compare(l[0].text, "www.kde.org")
        compare(l[0].url, "https://www.kde.org")
    }

    function test_emailBecomesMailto() {
        compare(urls("write to me.name+tag@mail.example.com please"), "mailto:me.name+tag@mail.example.com")
        compare(urls("mailto:a@b.cc"), "mailto:a@b.cc")
        compare(Links.address("mailto:a@b.cc"), "a@b.cc")
        compare(Links.address("https://a.b"), "https://a.b")
    }

    function test_positionsCoverTheLinkText() {
        var text = "a https://x.y/z, b"
        var l = Links.find(text)[0]
        compare(text.substring(l.start, l.end), "https://x.y/z")
        compare(l.text, "https://x.y/z")
    }

    function test_trailingPunctuationIsNotPartOfTheLink() {
        compare(urls("(see https://x.y/a)."), "https://x.y/a")
        compare(urls("https://en.wikipedia.org/wiki/Foo_(bar)"), "https://en.wikipedia.org/wiki/Foo_(bar)")
        compare(urls("\"https://x.y\"!"), "https://x.y")
        compare(urls("https://x.y?"), "https://x.y")
    }

    function test_noLinks() {
        compare(Links.find("").length, 0)
        compare(Links.find(undefined).length, 0)
        compare(Links.find("just text, a.b and @handle").length, 0)
        compare(Links.find("https:// and www.").length, 0)
    }

    function test_severalLinksAndRepeatedCalls() {
        var text = "a.b@c.de www.x.com https://y.z"
        compare(urls(text), "mailto:a.b@c.de https://www.x.com https://y.z")
        compare(urls(text), "mailto:a.b@c.de https://www.x.com https://y.z")
    }

    function test_styledTextEscapesAndLinks() {
        compare(Links.toStyledText("<b> & https://x.y/?a=1&b=2\nnext  two"),
                '&lt;b&gt; &amp; <a href="https://x.y/?a=1&amp;b=2">https://x.y/?a=1&amp;b=2</a><br>next &nbsp;two')
        compare(Links.toStyledText("plain"), "plain")
    }
}
