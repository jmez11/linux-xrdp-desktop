import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root
    width: 170
    height: 170
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation

    property string cityName: "New York"
    property string temperature: "79°"
    property string conditionText: "Cloudy"
    property string highLowText: "H:81°  L:66°"
    property string weatherGlyph: "☁"

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

    function fetchWeather() {
        var xhr = new XMLHttpRequest();
        var url = "https://api.open-meteo.com/v1/forecast?latitude=40.7128&longitude=-74.0060&current_weather=true&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&timezone=auto";
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

    Component.onCompleted: fetchWeather()

    Timer {
        interval: 1800000
        running: true
        repeat: true
        onTriggered: root.fetchWeather()
    }

    Rectangle {
        anchors.fill: parent
        radius: 22
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#728EA8" }
            GradientStop { position: 1.0; color: "#90A4B8" }
        }
        border.color: "#40FFFFFF"
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 2

            Text {
                text: root.cityName
                font.family: "Inter"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: "#FFFFFF"
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
