module common.items;

import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import common.content.content : content;
import common.material : ByteColor, materialColors, materialCount;
import plugins.api.api : Material;

enum string WARE_KIND = "ware";
enum string MATERIAL_KIND = "material";

struct WareInfo {
    const(char)[] name;
    ByteColor color;
}

__gshared Array!WareInfo wareTable;
__gshared Array!(const(char)[]) materialNames;

enum ItemKind : ubyte {
    nothing,
    block,
    ware,
}

struct Item {
    ushort id;

    ItemKind kind() const {
        if (id == 0) {
            return ItemKind.nothing;
        } else if (id < materialCount()) {
            return ItemKind.block;
        } else {
            return ItemKind.ware;
        }
    }

    Material block() const {
        assert(kind == ItemKind.block);
        return Material(cast(ubyte) id);
    }

    uint ware() const {
        assert(kind == ItemKind.ware);
        return id - materialCount();
    }
}

uint itemCount() {
    return materialCount() + cast(uint) wareTable.length;
}

uint wareCount() {
    return cast(uint) wareTable.length;
}

Item itemOf(Material material) {
    return Item(material.id);
}

Item wareItem(uint ware) {
    return Item(cast(ushort)(materialCount() + ware));
}

ByteColor colorOf(Item item) {
    final switch (item.kind) {
        case ItemKind.nothing:
            return ByteColor(0, 0, 0);
        case ItemKind.block:
            return materialColors.ptr[item.block.id];
        case ItemKind.ware:
            return wareTable.ptr[item.ware].color;
    }
}

Material placedBlock(Item item) {
    if (item.kind == ItemKind.block) {
        return item.block;
    } else {
        return Material.none;
    }
}

const(char)[] contentNameOf(Item item) {
    final switch (item.kind) {
        case ItemKind.nothing:
            return null;
        case ItemKind.block:
            return materialNames.ptr[item.block.id];
        case ItemKind.ware:
            return wareTable.ptr[item.ware].name;
    }
}

Maybe!Item itemNamed(const(char)[] name) {
    MaybeIndex!uint node = content().nodeNamed(name);
    if (!node.exists) {
        return Maybe!Item.init;
    } else {
        return itemOfNode(node.value);
    }
}

Maybe!Item itemOfNode(uint node) {
    if (content().isKind(node, MATERIAL_KIND)) {
        return Maybe!Item.of(Item(cast(ushort) content().ordinalOf(node)));
    } else if (content().isKind(node, WARE_KIND)) {
        return Maybe!Item.of(wareItem(content().ordinalOf(node)));
    } else {
        return Maybe!Item.init;
    }
}
