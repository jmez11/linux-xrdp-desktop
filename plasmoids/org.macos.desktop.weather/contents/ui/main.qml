import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root
    width: 184
    height: 184
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation

    property string cityName: "Locating..."
    property string temperature: "--°"
    property string conditionText: "Loading"
    property string highLowText: "H:--°  L:--°"
    property string weatherGlyph: "⛅"
    property real latitude: 37.7749
    property real longitude: -122.4194
    property bool hasGeo: false

    function mapWeatherCode(code) {
        if (code === 0) return { text: "Clear", glyph: "☀" };
        if (code === 1 || code === 2) return { text: "Partly Cloudy", glyph: "⛅" };
        if (code === 3) return { text: "Cloudy", glyph: "☁" };
        if (code >= 45 && code <= 48) return { text: "Foggy", glyph: "🌫" };
        if (code >= 51 && code <= 67) return { text: "Rain", glyph: "🌧" };
        if (code >= 71 && code <= 77) return { text: "Snow", glyph: "❄" };
        if (code >= 80 && code <= 82) return { text: "Showers", glyph: "🌦" };
        if (code >= 95) return { text: "Thunderstorm", glyph: "⛈" };
        return { text: "Cloudy", glyph: "☁" };
    }

    function fetchWeatherForCoords(lat, lon) {
        var xhr = new XMLHttpRequest();
        var url = "https://api.open-meteo.com/v1/forecast?latitude=" + encodeURIComponent(lat) +
                  "&longitude=" + encodeURIComponent(lon) +
                  "&current_weather=true&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=auto";
        xhr.open("GET", url, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var res = JSON.parse(xhr.responseText);
                    if (res.current_weather) {
                        root.temperature = Math.round(res.current_weather.temperature) + "°";
                        var mapped = root.mapWeatherCode(res.current_weather.weathercode);
                        root.conditionText = mapped.text;
                        root.weatherGlyph = mapped.glyph;
                    }
                    if (res.daily && res.daily.temperature_2m_max && res.daily.temperature_2m_min) {
                        var hi = Math.round(res.daily.temperature_2m_max[0]);
                        var lo = Math.round(res.daily.temperature_2m_min[0]);
                        root.highLowText = "H:" + hi + "°  L:" + lo + "°";
                    }
                } catch (e) {}
            }
        };
        xhr.send();
    }

    function geolocateAndFetch() {
        var geoXhr = new XMLHttpRequest();
        geoXhr.open("GET", "https://get.geojs.io/v1/ip/geo.json", true);
        geoXhr.onreadystatechange = function() {
            if (geoXhr.readyState === XMLHttpRequest.DONE) {
                if (geoXhr.status === 200) {
                    try {
                        var geo = JSON.parse(geoXhr.responseText);
                        if (geo.city) root.cityName = geo.city;
                        if (geo.latitude && geo.longitude) {
                            root.latitude = parseFloat(geo.latitude);
                            root.longitude = parseFloat(geo.longitude);
                            root.hasGeo = true;
                        }
                    } catch (e) {}
                }
                if (root.hasGeo) {
                    root.fetchWeatherForCoords(root.latitude, root.longitude);
                } else {
                    root.geolocateFallback();
                }
            }
        };
        geoXhr.send();
    }

    function geolocateFallback() {
        var fbXhr = new XMLHttpRequest();
        fbXhr.open("GET", "https://ipwho.is/", true);
        fbXhr.onreadystatechange = function() {
            if (fbXhr.readyState === XMLHttpRequest.DONE) {
                if (fbXhr.status === 200) {
                    try {
                        var geo = JSON.parse(fbXhr.responseText);
                        if (geo.city) root.cityName = geo.city;
                        if (geo.latitude && geo.longitude) {
                            root.latitude = parseFloat(geo.latitude);
                            root.longitude = parseFloat(geo.longitude);
                            root.hasGeo = true;
                        }
                    } catch (e) {}
                }
                if (!root.cityName || root.cityName === "Locating...") {
                    root.cityName = "Local";
                }
                root.fetchWeatherForCoords(root.latitude, root.longitude);
            }
        };
        fbXhr.send();
    }

    Component.onCompleted: geolocateAndFetch()

    Timer {
        interval: 1800000
        running: true
        repeat: true
        onTriggered: root.geolocateAndFetch()
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: 24
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#728EA8" }
            GradientStop { position: 1.0; color: "#90A4B8" }
        }
        border.color: "#38FFFFFF"
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 2

            Text {
                text: root.cityName
                font.family: "Inter"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: "#FFFFFF"
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                text: root.temperature
                font.family: "Inter"
                font.pixelSize: 40
                font.weight: Font.Light
                color: "#FFFFFF"
            }

            Item { Layout.fillHeight: true }

            Text {
                text: root.weatherGlyph
                font.family: "Inter"
                font.pixelSize: 18
                color: "#FFFFFF"
            }

            Text {
                text: root.conditionText
                font.family: "Inter"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: "#FFFFFF"
            }

            Text {
                text: root.highLowText
                font.family: "Inter"
                font.pixelSize: 11
                font.weight: Font.Medium
                color: "#E5FFFFFF"
            }
        }
    }
}
