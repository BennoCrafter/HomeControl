import TipKit

/// In a room, until a group exists: what groups are for and how to make one.
struct GroupTip: Tip {
    var title: Text { Text("Group lamps that belong together") }
    var message: Text? { Text("Hold the room's name and pick the items: they switch as one tile.") }
    var image: Image? { Image(systemName: "square.stack.3d.up.fill") }
}

/// On the + while arranging the dashboard, until a folder exists.
struct FolderTip: Tip {
    var title: Text { Text("Tidy up with folders") }
    var message: Text? { Text("Add a folder, open it and add cards inside. It switches nothing itself.") }
    var image: Image? { Image(systemName: "folder.fill") }
}
