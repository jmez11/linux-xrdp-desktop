import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.taskmanager 0.1 as TaskManager

Item {
    id: root
    anchors.fill: parent
    implicitWidth: 1040
    implicitHeight: 140
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.preferredRepresentation: Plasmoid.fullRepresentation

    property real mouseXPos: -1000
    property bool mouseInside: false
    property int baseIconSize: 44
    property int taskRevision: 0
    property int menuAppIndex: -1
    property var menuAppItem: null

    TaskManager.TasksModel {
        id: tasksModel
        groupMode: TaskManager.TasksModel.GroupApplications
        onCountChanged: root.taskRevision++
        onDataChanged: root.taskRevision++
        onRowsInserted: root.taskRevision++
        onRowsRemoved: root.taskRevision++
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

    // Helper DataSource for dock configuration (add / remove / dump)
    PlasmaCore.DataSource {
        id: dockHelper
        engine: "executable"
        connectedSources: []
        onNewData: {
            var out = data["stdout"];
            disconnectSource(sourceName);
            if (out && out.trim().length > 0) {
                try {
                    var parsed = JSON.parse(out.trim());
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        root.updateDockModel(parsed);
                    }
                } catch (e) {
                    // Ignore non-JSON output
                }
            }
        }
        function execCommand(cmd) {
            connectSource(cmd + " # " + Date.now());
        }
    }

    ListModel {
        id: dockModel
        // Pre-populated defaults so dock renders instantly without any delay
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
        ListElement { name: "Shared Drives"; appMatch: "thinclient_drives"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/devices/drive-harddisk.svg"; cmd: "dolphin ~/thinclient_drives"; isSeparatorBefore: true }
        ListElement { name: "Trash"; appMatch: "trash"; iconName: "/usr/share/icons/Mkos-Big-Sur/128x128/places/user-trash-full.svg"; cmd: "dolphin trash:/"; isSeparatorBefore: false }
    }

    function updateDockModel(appsList) {
        if (!appsList || appsList.length === 0) return;
        if (appsList.length === dockModel.count) {
            var diff = false;
            for (var k = 0; k < appsList.length; k++) {
                var cur = dockModel.get(k);
                if (cur.name !== appsList[k].name || cur.cmd !== appsList[k].cmd) {
                    diff = true;
                    break;
                }
            }
            if (!diff) return;
        }
        dockModel.clear();
        for (var i = 0; i < appsList.length; i++) {
            var it = appsList[i];
            dockModel.append({
                name: it.name || "App",
                appMatch: it.appMatch || "",
                iconName: it.iconName || "application-x-executable",
                cmd: it.cmd || "",
                isSeparatorBefore: it.isSeparatorBefore === true
            });
        }
    }

    function addAppToDock(target) {
        if (!target) return;
        var quoted = "'" + target.replace(/'/g, "'\\''") + "'";
        dockHelper.execCommand("/usr/local/bin/xrdp-dock-helper.py add " + quoted);
    }

    function removeAppFromDock(index) {
        dockHelper.execCommand("/usr/local/bin/xrdp-dock-helper.py remove " + index);
    }

    function findTaskIndex(matchKey, rev) {
        if (!matchKey || matchKey === "thinclient_drives" || matchKey === "trash") return -1;
        var lowerKey = matchKey.toLowerCase();
        for (var i = 0; i < tasksModel.count; i++) {
            var idx = tasksModel.index(i, 0);
            var appId = (tasksModel.data(idx, TaskManager.AbstractTasksModel.AppId) || "").toString().toLowerCase();
            var appName = (tasksModel.data(idx, TaskManager.AbstractTasksModel.AppName) || "").toString().toLowerCase();
            var winTitle = (tasksModel.data(idx, Qt.DisplayRole) || "").toString().toLowerCase();
            if (appId.indexOf(lowerKey) !== -1 || appName.indexOf(lowerKey) !== -1 || winTitle.indexOf(lowerKey) !== -1) {
                return i;
            }
        }
        return -1;
    }

    // Keep the dock applet dynamically centered at the bottom middle of the desktop
    function centerOnDesktop() {
        var appletItem = root.parent;
        if (!appletItem) return;
        var desk = appletItem.parent;
        if (!desk || desk.width < 500 || desk.height < 350) return;

        var targetW = Math.min(1040, Math.round(desk.width - 24));
        var targetH = 140;
        var targetX = Math.round((desk.width - targetW) / 2);
        var targetY = Math.round(desk.height - targetH - 4);

        if (Math.abs(appletItem.width - targetW) > 2) appletItem.width = targetW;
        if (Math.abs(appletItem.height - targetH) > 2) appletItem.height = targetH;
        if (Math.abs(appletItem.x - targetX) > 2) appletItem.x = targetX;
        if (Math.abs(appletItem.y - targetY) > 2) appletItem.y = targetY;
    }

    Component.onCompleted: {
        centerOnDesktop();
        dockHelper.execCommand("/usr/local/bin/xrdp-dock-helper.py dump");
    }

    Timer {
        interval: 500
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
        color: dockDropArea.containsDrag ? "#802A3048" : "#6B242838"
        border.color: dockDropArea.containsDrag ? "#99FFFFFF" : "#4DFFFFFF"
        border.width: dockDropArea.containsDrag ? 2 : 1

        Behavior on width {
            NumberAnimation { duration: 75; easing.type: Easing.OutQuad }
        }
        Behavior on color {
            ColorAnimation { duration: 150 }
        }
        Behavior on border.color {
            ColorAnimation { duration: 150 }
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
                property bool launching: false
                property bool isRunning: root.findTaskIndex(model.appMatch, root.taskRevision) !== -1

                onIsRunningChanged: {
                    if (isRunning) {
                        launching = false;
                        launchTimeout.stop();
                    }
                }

                Timer {
                    id: launchTimeout
                    interval: 4000
                    repeat: false
                    onTriggered: delegateRoot.launching = false
                }

                Behavior on magScale {
                    NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                }

                function triggerBounce() {
                    launching = true;
                    launchTimeout.restart();
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
                    visible: root.mouseInside && delegateRoot.dist < 25 && root.menuAppIndex < 0
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

                // Active indicator dot below icon (turns off automatically when app closes)
                Rectangle {
                    visible: delegateRoot.isRunning || delegateRoot.launching
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

    // Dismiss context menu when clicking outside
    MouseArea {
        anchors.fill: parent
        visible: root.menuAppIndex >= 0
        z: 100
        onClicked: {
            root.menuAppIndex = -1;
            root.menuAppItem = null;
        }
    }

    // macOS-style Right-Click Context Menu Popup
    Rectangle {
        id: contextMenuPopup
        visible: root.menuAppIndex >= 0
        z: 200
        width: 170
        height: menuCol.implicitHeight + 16
        radius: 10
        color: "#F01E1E28"
        border.color: "#50FFFFFF"
        border.width: 1

        x: {
            if (root.menuAppIndex < 0 || !dockRepeater.itemAt(root.menuAppIndex)) return 0;
            var it = dockRepeater.itemAt(root.menuAppIndex);
            var pos = it.mapToItem(root, 0, 0);
            var targetX = pos.x + (it.width - width) / 2;
            return Math.max(10, Math.min(root.width - width - 10, targetX));
        }
        y: {
            if (root.menuAppIndex < 0 || !dockRepeater.itemAt(root.menuAppIndex)) return 0;
            var it = dockRepeater.itemAt(root.menuAppIndex);
            var pos = it.mapToItem(root, 0, 0);
            return Math.max(8, pos.y - height - 10);
        }

        Column {
            id: menuCol
            anchors.centerIn: parent
            width: parent.width - 16
            spacing: 3

            Text {
                width: parent.width
                text: root.menuAppItem ? root.menuAppItem.name : ""
                font.family: "Inter"
                font.pixelSize: 12
                font.weight: Font.Bold
                color: "#A0FFFFFF"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                topPadding: 2
                bottomPadding: 3
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#25FFFFFF"
            }

            Rectangle {
                id: openBtn
                width: parent.width
                height: 26
                radius: 6
                color: openMouse.containsMouse ? "#30FFFFFF" : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: {
                        if (!root.menuAppItem) return "Open";
                        var isRunning = root.findTaskIndex(root.menuAppItem.appMatch, root.taskRevision) !== -1;
                        return isRunning ? "Bring to Front" : "Open";
                    }
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: "#FFFFFF"
                }
                MouseArea {
                    id: openMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (root.menuAppIndex >= 0 && root.menuAppItem) {
                            var entry = root.menuAppItem;
                            var runningIdx = root.findTaskIndex(entry.appMatch, root.taskRevision);
                            if (runningIdx !== -1) {
                                var modelIdx = tasksModel.index(runningIdx, 0);
                                tasksModel.requestActivate(modelIdx);
                            } else {
                                var it = dockRepeater.itemAt(root.menuAppIndex);
                                if (it) it.triggerBounce();
                                executable.exec(entry.cmd + " >/dev/null 2>&1 &");
                            }
                        }
                        root.menuAppIndex = -1;
                        root.menuAppItem = null;
                    }
                }
            }

            Rectangle {
                id: removeBtn
                visible: root.menuAppItem && root.menuAppItem.appMatch !== "trash" && root.menuAppItem.appMatch !== "thinclient_drives"
                width: parent.width
                height: 26
                radius: 6
                color: removeMouse.containsMouse ? "#40FF453A" : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "Remove from Dock"
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: removeMouse.containsMouse ? "#FF6961" : "#FF453A"
                }
                MouseArea {
                    id: removeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (root.menuAppIndex >= 0) {
                            root.removeAppFromDock(root.menuAppIndex);
                        }
                        root.menuAppIndex = -1;
                        root.menuAppItem = null;
                    }
                }
            }
        }
    }

    // Drag and Drop Area for adding apps to the dock (macOS style)
    DropArea {
        id: dockDropArea
        anchors.fill: dockBg
        anchors.margins: -14
        z: 30

        onEntered: function(drag) {
            drag.accept();
        }
        onPositionChanged: function(drag) {
            drag.accept();
        }
        onDropped: function(drop) {
            var target = "";
            if (drop.hasUrls && drop.urls.length > 0) {
                target = drop.urls[0].toString();
            } else if (drop.hasText && drop.text.length > 0) {
                target = drop.text;
            } else if (drop.getDataAsString) {
                target = drop.getDataAsString("text/uri-list") || drop.getDataAsString("text/plain");
            }
            if (target && target.trim().length > 0) {
                var lines = target.split(/[\r\n]+/);
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i].trim();
                    if (l.length > 0) {
                        root.addAppToDock(l);
                        break;
                    }
                }
            }
            drop.accept();
        }
    }

    MouseArea {
        id: dockMouse
        anchors.left: dockBg.left
        anchors.right: dockBg.right
        anchors.bottom: parent.bottom
        height: 70
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 20

        onPositionChanged: {
            root.mouseInside = true;
            var pt = mapToItem(dockRow, mouse.x, mouse.y);
            root.mouseXPos = pt.x;
        }

        onExited: {
            root.mouseInside = false;
            root.mouseXPos = -1000;
        }

        onClicked: function(mouse) {
            var pt = mapToItem(dockRow, mouse.x, mouse.y);
            for (var i = 0; i < dockRepeater.count; i++) {
                var item = dockRepeater.itemAt(i);
                if (item && pt.x >= item.x && pt.x <= item.x + item.width) {
                    var entry = dockModel.get(i);
                    if (mouse.button === Qt.RightButton) {
                        root.menuAppIndex = i;
                        root.menuAppItem = entry;
                    } else {
                        root.menuAppIndex = -1;
                        root.menuAppItem = null;
                        var runningIdx = root.findTaskIndex(entry.appMatch, root.taskRevision);
                        if (runningIdx !== -1) {
                            var modelIdx = tasksModel.index(runningIdx, 0);
                            tasksModel.requestActivate(modelIdx);
                        } else {
                            item.triggerBounce();
                            executable.exec(entry.cmd + " >/dev/null 2>&1 &");
                        }
                    }
                    return;
                }
            }
            root.menuAppIndex = -1;
            root.menuAppItem = null;
        }
    }
}
