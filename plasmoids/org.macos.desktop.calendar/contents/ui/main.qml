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

    property date now: new Date()
    property int currentYear: now.getFullYear()
    property int currentMonth: now.getMonth()
    property int currentDay: now.getDate()
    property var monthNames: ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
    property var dayHeaders: ["S", "M", "T", "W", "T", "F", "S"]

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }

    function firstWeekday(year, month) {
        return new Date(year, month, 1).getDay();
    }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: "#F2FFFFFF"
        border.color: "#30000000"
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 4

            Text {
                text: root.monthNames[root.currentMonth]
                font.family: "Inter"
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0.6
                color: "#FF3B30"
                Layout.alignment: Qt.AlignLeft
            }

            GridLayout {
                columns: 7
                rowSpacing: 2
                columnSpacing: 2
                Layout.fillWidth: true
                Layout.fillHeight: true

                Repeater {
                    model: 7
                    Item {
                        Layout.fillWidth: true
                        height: 16
                        Text {
                            anchors.centerIn: parent
                            text: root.dayHeaders[index]
                            font.family: "Inter"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: (index === 0 || index === 6) ? "#8E8E93" : "#3A3A3C"
                        }
                    }
                }

                Repeater {
                    model: 42
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        property int offset: index - root.firstWeekday(root.currentYear, root.currentMonth) + 1
                        property int totalDays: root.daysInMonth(root.currentYear, root.currentMonth)
                        property bool validDay: offset >= 1 && offset <= totalDays
                        property bool isToday: validDay && offset === root.currentDay

                        Rectangle {
                            anchors.centerIn: parent
                            width: 19
                            height: 19
                            radius: 9.5
                            color: parent.isToday ? "#FF3B30" : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: parent.validDay
                            text: parent.validDay ? parent.offset : ""
                            font.family: "Inter"
                            font.pixelSize: 10
                            font.weight: parent.isToday ? Font.Bold : Font.Medium
                            color: parent.isToday ? "#FFFFFF" : ((index % 7 === 0 || index % 7 === 6) ? "#8E8E93" : "#1C1C1E")
                        }
                    }
                }
            }
        }
    }
}
