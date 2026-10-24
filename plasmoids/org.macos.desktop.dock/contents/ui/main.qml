import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.taskmanager 0.1 as TaskManager

Item {
    id: root
    width: 1120
    height: 116
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation

    property real mouseXPos: -1000
    property bool mouseInside: false
    property int baseIconSize: 44

    TaskManager.TasksModel {
        id: tasksModel
        groupMode: TaskManager.TasksModel.GroupApplications
    }

    PlasmaCore.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: {
            disconnectSource(sourceName);
        }
        function exec(cmd) {
            connectSource(cmd);
        }
    }

    ListModel {
        id: dockModel
        ListElement { name: "Dolphin"; appMatch: "dolphin"; iconName: "/usr/share/icons/breeze-dark/apps/48/system-file-manager.svg"; cmd: "dolphin"; isSeparatorBefore: false }
        ListElement { name: "Firefox"; appMatch: "firefox"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/firefox.svg"; cmd: "firefox"; isSeparatorBefore: false }
        ListElement { name: "Visual Studio Code"; appMatch: "code"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/vscode.svg"; cmd: "/usr/local/bin/vscode-launch"; isSeparatorBefore: false }
        ListElement { name: "Konsole"; appMatch: "konsole"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/utilities-terminal.svg"; cmd: "konsole"; isSeparatorBefore: false }
        ListElement { name: "Kate"; appMatch: "kate"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/kate.svg"; cmd: "kate"; isSeparatorBefore: false }
        ListElement { name: "Gwenview"; appMatch: "gwenview"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/gwenview.svg"; cmd: "gwenview"; isSeparatorBefore: false }
        ListElement { name: "Okular"; appMatch: "okular"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/okular.svg"; cmd: "okular"; isSeparatorBefore: false }
        ListElement { name: "GIMP"; appMatch: "gimp"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/gimp.svg"; cmd: "gimp"; isSeparatorBefore: false }
        ListElement { name: "Inkscape"; appMatch: "inkscape"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/inkscape.svg"; cmd: "inkscape"; isSeparatorBefore: false }
        ListElement { name: "Blender"; appMatch: "blender"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/blender.svg"; cmd: "blender"; isSeparatorBefore: false }
        ListElement { name: "VLC"; appMatch: "vlc"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/vlc.svg"; cmd: "vlc"; isSeparatorBefore: false }
        ListElement { name: "LibreOffice Writer"; appMatch: "writer"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/libreoffice-writer.svg"; cmd: "libreoffice --writer"; isSeparatorBefore: false }
        ListElement { name: "LibreOffice Calc"; appMatch: "calc"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/libreoffice-calc.svg"; cmd: "libreoffice --calc"; isSeparatorBefore: false }
        ListElement { name: "Calculator"; appMatch: "kcalc"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/accessories-calculator.svg"; cmd: "kcalc"; isSeparatorBefore: false }
        ListElement { name: "System Settings"; appMatch: "systemsettings"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/apps/systemsettings.svg"; cmd: "systemsettings5"; isSeparatorBefore: false }
        ListElement { name: "Shared Drives"; appMatch: "thinclient_drives"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/places/folder-blue.svg"; cmd: "dolphin ~/thinclient_drives"; isSeparatorBefore: true }
        ListElement { name: "Trash"; appMatch: "trash"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/places/user-trash-full.svg"; cmd: "dolphin trash:/"; isSeparatorBefore: false }
    }

    function findTaskIndex(matchKey) {
        if (!matchKey || matchKey === "thinclient_drives" || matchKey === "trash") return -1;
        var lowerKey = matchKey.toLowerCase();
        for (var i = 0; i < tasksModel.count; i++) {
            var idx = tasksModel.index(i, 0);
            var appId = (tasksModel.data(idx, TaskManager.AbstractTasksModel.AppId) || "").toString().toLowerCase();
            var appName = (tasksModel.data(idx, TaskManager.AbstractTasksModel.AppName) || "").toString().toLowerCase();
            if (appId.indexOf(lowerKey) !== -1 || appName.indexOf(lowerKey) !== -1) {
                return i;
            }
        }
        return -1;
    }

    // Keep the dock widget dynamically centered at the bottom middle of the desktop
    function centerOnDesktop() {
        if (root.parent && root.parent.parent && root.parent.parent.width > 200 && root.parent.parent.height > 200) {
            var deskItem = root.parent.parent;
            var targetX = Math.round((deskItem.width - root.parent.width) / 2);
            var targetY = Math.round(deskItem.height - root.parent.height - 4);
            if (Math.abs(root.parent.x - targetX) > 2) root.parent.x = targetX;
            if (Math.abs(root.parent.y - targetY) > 2) root.parent.y = targetY;
        }
    }

    Component.onCompleted: centerOnDesktop()

    Timer {
        interval: 600
        running: true
        repeat: true
        onTriggered: root.centerOnDesktop()
    }

    // Translucent rounded glass dock pill along the bottom
    Rectangle {
        id: dockBg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        width: dockRow.width + 26
        height: 60
        radius: 19
        color: "#6B242838"
        border.color: "#4DFFFFFF"
        border.width: 1

        Behavior on width {
            NumberAnimation { duration: 75; easing.type: Easing.OutQuad }
        }
    }

    Row {
        id: dockRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: dockBg.bottom
        anchors.bottomMargin: 8
        spacing: 8

        Repeater {
            id: dockRepeater
            model: dockModel

            Item {
                id: delegateRoot
                width: (model.isSeparatorBefore ? 13 : 0) + root.baseIconSize * magScale
                height: root.baseIconSize

                property real centerInRow: x + width / 2
                property real dist: root.mouseInside ? Math.abs(root.mouseXPos - centerInRow) : 1000
                property real magScale: {
                    if (!root.mouseInside || dist > 135) return 1.0;
                    var norm = dist / 135.0;
                    return 1.0 + 0.50 * Math.cos(norm * Math.PI / 2.0) * Math.cos(norm * Math.PI / 2.0);
                }

                property real bounceOffset: 0
                property bool launched: false

                Behavior on magScale {
                    NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                }

                function triggerBounce() {
                    bounceAnim.restart();
                }

                SequentialAnimation {
                    id: bounceAnim
                    NumberAnimation { target: delegateRoot; property: "bounceOffset"; to: -28; duration: 155; easing.type: Easing.OutQuad }
                    NumberAnimation { target: delegateRoot; property: "bounceOffset"; to: 0; duration: 175; easing.type: Easing.InQuad }
                    NumberAnimation { target: delegateRoot; property: "bounceOffset"; to: -16; duration: 135; easing.type: Easing.OutQuad }
                    NumberAnimation { target: delegateRoot; property: "bounceOffset"; to: 0; duration: 155; easing.type: Easing.InQuad }
                    NumberAnimation { target: delegateRoot; property: "bounceOffset"; to: -7; duration: 105; easing.type: Easing.OutQuad }
                    NumberAnimation { target: delegateRoot; property: "bounceOffset"; to: 0; duration: 115; easing.type: Easing.InQuad }
                }

                // Vertical divider before Shared Drives & Trash (like macOS Dock)
                Rectangle {
                    visible: model.isSeparatorBefore
                    width: 1
                    height: 36
                    color: "#45FFFFFF"
                    anchors.left: parent.left
                    anchors.leftMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Hover tooltip pill above the magnified icon
                Rectangle {
                    id: tooltipPill
                    visible: root.mouseInside && delegateRoot.dist < 25
                    anchors.horizontalCenter: iconItem.horizontalCenter
                    anchors.bottom: iconItem.top
                    anchors.bottomMargin: 8
                    width: tooltipText.implicitWidth + 18
                    height: 24
                    radius: 7
                    color: "#E81E1E28"
                    border.color: "#40FFFFFF"
                    border.width: 1
                    z: 20

                    Text {
                        id: tooltipText
                        anchors.centerIn: parent
                        text: model.name
                        font.family: "Inter"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: "#FFFFFF"
                    }
                }

                PlasmaCore.IconItem {
                    id: iconItem
                    width: root.baseIconSize * delegateRoot.magScale
                    height: width
                    anchors.right: parent.right
                    y: parent.height - height + delegateRoot.bounceOffset - (delegateRoot.magScale - 1.0) * 8
                    source: model.iconName
                    usesPlasmaTheme: false
                    active: root.mouseInside && delegateRoot.dist < 25
                }

                // Active indicator dot below icon
                Rectangle {
                    visible: delegateRoot.launched || root.findTaskIndex(model.appMatch) !== -1
                    width: 4
                    height: 4
                    radius: 2
                    color: "#E0FFFFFF"
                    anchors.horizontalCenter: iconItem.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -5
                }
            }
        }
    }

    MouseArea {
        id: dockMouse
        anchors.left: dockBg.left
        anchors.right: dockBg.right
        anchors.bottom: parent.bottom
        height: parent.height
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        onPositionChanged: {
            root.mouseInside = true;
            var pt = mapToItem(dockRow, mouse.x, mouse.y);
            root.mouseXPos = pt.x;
        }

        onExited: {
            root.mouseInside = false;
            root.mouseXPos = -1000;
        }

        onClicked: {
            var pt = mapToItem(dockRow, mouse.x, mouse.y);
            for (var i = 0; i < dockRepeater.count; i++) {
                var item = dockRepeater.itemAt(i);
                if (item && pt.x >= item.x && pt.x <= item.x + item.width) {
                    var entry = dockModel.get(i);
                    var runningIdx = root.findTaskIndex(entry.appMatch);
                    if (runningIdx !== -1) {
                        var modelIdx = tasksModel.index(runningIdx, 0);
                        tasksModel.requestActivate(modelIdx);
                        item.launched = true;
                    } else {
                        item.launched = true;
                        item.triggerBounce();
                        executable.exec(entry.cmd + " >/dev/null 2>&1 &");
                    }
                    break;
                }
            }
        }
    }
}
