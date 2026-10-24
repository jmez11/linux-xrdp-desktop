import QtQuick 2.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root
    width: 184
    height: 184
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation

    property date now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.now = new Date();
            clockCanvas.requestPaint();
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: 26
        color: "#E5E5EA"
        border.color: "#28000000"
        border.width: 1

        Rectangle {
            id: dial
            anchors.fill: parent
            anchors.margins: 12
            radius: width / 2
            color: "#FFFFFF"

            Canvas {
                id: clockCanvas
                anchors.fill: parent
                antialiasing: true
                renderTarget: Canvas.Image

                onPaint: {
                    var ctx = getContext("2d");
                    var w = width;
                    var h = height;
                    var cx = w / 2;
                    var cy = h / 2;
                    var r = Math.min(cx, cy) - 4;

                    ctx.clearRect(0, 0, w, h);

                    // Draw minute/hour ticks
                    for (var i = 0; i < 60; i++) {
                        var angle = (i * 6) * Math.PI / 180;
                        var isHour = (i % 5 === 0);
                        var innerR = isHour ? r - 7 : r - 4;
                        ctx.beginPath();
                        ctx.moveTo(cx + innerR * Math.sin(angle), cy - innerR * Math.cos(angle));
                        ctx.lineTo(cx + r * Math.sin(angle), cy - r * Math.cos(angle));
                        ctx.lineWidth = isHour ? 1.8 : 1.0;
                        ctx.strokeStyle = isHour ? "#1C1C1E" : "#C7C7CC";
                        ctx.stroke();
                    }

                    // Draw numbers 1..12
                    ctx.fillStyle = "#1C1C1E";
                    ctx.font = "bold 13px Inter, sans-serif";
                    ctx.textAlign = "center";
                    ctx.textBaseline = "middle";
                    var numR = r - 18;
                    for (var n = 1; n <= 12; n++) {
                        var nAngle = (n * 30) * Math.PI / 180;
                        var nx = cx + numR * Math.sin(nAngle);
                        var ny = cy - numR * Math.cos(nAngle);
                        ctx.fillText(n.toString(), nx, ny);
                    }

                    var hrs = root.now.getHours() % 12;
                    var mins = root.now.getMinutes();
                    var secs = root.now.getSeconds();

                    // Hour hand
                    var hAngle = ((hrs + mins / 60.0) * 30) * Math.PI / 180;
                    ctx.save();
                    ctx.translate(cx, cy);
                    ctx.rotate(hAngle);
                    ctx.beginPath();
                    ctx.lineCap = "round";
                    ctx.lineWidth = 4.5;
                    ctx.strokeStyle = "#1C1C1E";
                    ctx.moveTo(0, 6);
                    ctx.lineTo(0, -(r * 0.52));
                    ctx.stroke();
                    ctx.restore();

                    // Minute hand
                    var mAngle = ((mins + secs / 60.0) * 6) * Math.PI / 180;
                    ctx.save();
                    ctx.translate(cx, cy);
                    ctx.rotate(mAngle);
                    ctx.beginPath();
                    ctx.lineCap = "round";
                    ctx.lineWidth = 3.2;
                    ctx.strokeStyle = "#1C1C1E";
                    ctx.moveTo(0, 8);
                    ctx.lineTo(0, -(r * 0.78));
                    ctx.stroke();
                    ctx.restore();

                    // Second hand (macOS orange)
                    var sAngle = (secs * 6) * Math.PI / 180;
                    ctx.save();
                    ctx.translate(cx, cy);
                    ctx.rotate(sAngle);
                    ctx.beginPath();
                    ctx.lineCap = "round";
                    ctx.lineWidth = 1.6;
                    ctx.strokeStyle = "#FF9500";
                    ctx.moveTo(0, 12);
                    ctx.lineTo(0, -(r * 0.85));
                    ctx.stroke();
                    ctx.restore();

                    // Center cap
                    ctx.beginPath();
                    ctx.arc(cx, cy, 4, 0, 2 * Math.PI);
                    ctx.fillStyle = "#1C1C1E";
                    ctx.fill();
                    ctx.beginPath();
                    ctx.arc(cx, cy, 2, 0, 2 * Math.PI);
                    ctx.fillStyle = "#FF9500";
                    ctx.fill();
                }
            }
        }
    }
}
