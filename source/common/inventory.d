module common.inventory;

import base.maybe : Maybe;
import base.numbers : lowerOf;
import common.biology.wild : WildGenes;
import common.items : Item;

enum uint HOTBAR_SLOTS = 12;
enum uint PACK_ROWS = 3;
enum uint SLOT_COUNT = HOTBAR_SLOTS * (PACK_ROWS + 1);
enum uint STACK_LIMIT = 64;

enum Cycle : ubyte {
    back,
    ahead,
}

enum Section : ubyte {
    hotbar,
    pack,
}

struct Stack {
    Item item;
    uint count;
    Maybe!WildGenes genes;

    bool isEmpty() const {
        return count == 0;
    }

    uint room() const {
        if (count >= STACK_LIMIT) {
            return 0;
        } else {
            return STACK_LIMIT - count;
        }
    }
}

bool isSameKind(Stack a, Stack b) {
    return a.item == b.item && a.genes.exists == b.genes.exists && a.genes.stored.seeds == b.genes.stored.seeds;
}

Stack taken(Stack stack, uint count) {
    return Stack(stack.item, count, stack.genes);
}

Stack emptied(Stack stack) {
    if (stack.count == 0) {
        return Stack.init;
    } else {
        return stack;
    }
}

Section sectionOf(uint slot) {
    if (slot < HOTBAR_SLOTS) {
        return Section.hotbar;
    } else {
        return Section.pack;
    }
}

bool isAmong(Item item, const(Item)[] options) {
    uint index = 0;
    while (index < options.length && options[index] != item) {
        index += 1;
    }
    return index < options.length;
}

struct Inventory {
    Stack[SLOT_COUNT] slots;
    uint selected;

    Item held() const {
        return slots[selected].item;
    }

    uint countOf(Item item) const {
        uint total = 0;
        foreach (ref stack; slots) {
            if (!stack.isEmpty && stack.item == item) {
                total += stack.count;
            }
        }
        return total;
    }

    uint countOfKind(Stack kind) const {
        uint total = 0;
        foreach (ref stack; slots) {
            if (!stack.isEmpty && stack.isSameKind(kind)) {
                total += stack.count;
            }
        }
        return total;
    }

    bool spendKind(Stack kind) {
        uint slot = SLOT_COUNT;
        while (slot > 0 && !(!slots[slot - 1].isEmpty && slots[slot - 1].isSameKind(kind))) {
            slot -= 1;
        }
        return slot > 0 && spendFrom(slot - 1);
    }

    uint countAmong(const(Item)[] options) const {
        uint total = 0;
        foreach (ref stack; slots) {
            if (!stack.isEmpty && stack.item.isAmong(options)) {
                total += stack.count;
            }
        }
        return total;
    }

    bool select(uint slot) {
        bool changed = slot < HOTBAR_SLOTS && slot != selected;
        if (changed) {
            selected = slot;
        }
        return changed;
    }

    void cycle(Cycle direction) {
        final switch (direction) {
            case Cycle.back:
                selected = (selected + HOTBAR_SLOTS - 1) % HOTBAR_SLOTS;
                break;
            case Cycle.ahead:
                selected = (selected + 1) % HOTBAR_SLOTS;
                break;
        }
    }

    uint gain(Stack stack) {
        return gainWithin(0, SLOT_COUNT, stack);
    }

    uint gainInto(Section section, Stack stack) {
        if (section == Section.pack) {
            return gainWithin(HOTBAR_SLOTS, SLOT_COUNT, stack);
        } else {
            return gainWithin(0, HOTBAR_SLOTS, stack);
        }
    }

    uint gainWithin(uint first, uint end, Stack stack) {
        uint left = stack.count;
        foreach (ref slot; slots[first .. end]) {
            if (left > 0 && !slot.isEmpty && slot.isSameKind(stack)) {
                uint moved = lowerOf(left, slot.room);
                slot.count += moved;
                left -= moved;
            }
        }
        foreach (ref slot; slots[first .. end]) {
            if (left > 0 && slot.isEmpty) {
                uint moved = lowerOf(left, STACK_LIMIT);
                slot = stack.taken(moved);
                left -= moved;
            }
        }
        return left;
    }

    bool spendFrom(uint slot) {
        if (slots[slot].isEmpty) {
            return false;
        } else {
            slots[slot].count -= 1;
            slots[slot] = slots[slot].emptied;
            return true;
        }
    }

    bool spendHeld() {
        return spendFrom(selected);
    }

    bool spend(Item item, uint count) {
        Item[1] options;
        options[0] = item;
        return spendAmong(options[], count);
    }

    bool spendAmong(const(Item)[] options, uint count) {
        if (countAmong(options) < count) {
            return false;
        } else {
            uint left = count;
            uint slot = SLOT_COUNT;
            while (slot > 0 && left > 0) {
                slot -= 1;
                if (!slots[slot].isEmpty && slots[slot].item.isAmong(options)) {
                    uint taken = lowerOf(left, slots[slot].count);
                    slots[slot].count -= taken;
                    slots[slot] = slots[slot].emptied;
                    left -= taken;
                }
            }
            return true;
        }
    }
}
