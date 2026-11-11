module common.inventory;

import base.maybe : Maybe, MaybeIndex;
import base.numbers : lowerOf;
import common.biology.wild : WildGenes;
import common.items : Item;

enum uint HOTBAR_SLOTS = 12;
enum uint PACK_ROWS = 3;
enum uint SLOT_COUNT = HOTBAR_SLOTS * (PACK_ROWS + 1);
enum uint STACK_LIMIT = 64;
enum uint MOST_STRAINS = 8;
enum uint LOSS_DIVISOR = 3;

enum Cycle : ubyte {
    back,
    ahead,
}

enum Section : ubyte {
    hotbar,
    pack,
}

enum Sorting : ubyte {
    unsorted,
    sorted,
}

struct Strain {
    WildGenes genes;
    uint count;
}

struct Stack {
    Item item;
    uint count;
    Strain[MOST_STRAINS] strains;
    uint strainCount;
    Sorting sorting;

    static Stack ofLiving(Item item, uint count, WildGenes genes, Sorting sorting) {
        Stack made = Stack(item, count);
        made.strains[0] = Strain(genes, count);
        made.strainCount = 1;
        made.sorting = sorting;
        return made;
    }

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

    Maybe!WildGenes genes() const {
        if (strainCount == 0) {
            return Maybe!WildGenes.init;
        } else {
            return Maybe!WildGenes.of(strains[0].genes);
        }
    }

    Stack front() const {
        Stack made = Stack(item, 1);
        if (strainCount > 0) {
            made = Stack.ofLiving(item, 1, strains[0].genes, sorting);
        }
        return made;
    }

    MaybeIndex!uint runOf(WildGenes wanted) const {
        uint index = 0;
        while (index < strainCount && strains[index].genes.seeds != wanted.seeds) {
            index += 1;
        }
        if (index < strainCount) {
            return MaybeIndex!uint.of(index);
        } else {
            return MaybeIndex!uint.init;
        }
    }

    MaybeIndex!uint placeFor(WildGenes arriving) const {
        MaybeIndex!uint run = runOf(arriving);
        if (run.exists || strainCount == MOST_STRAINS) {
            return run;
        } else {
            return MaybeIndex!uint.of(strainCount);
        }
    }

    bool canJoin(ref const Stack other) const {
        bool alike = item == other.item && sorting == other.sorting && (strainCount > 0) == (other.strainCount > 0);
        return alike && (sorting == Sorting.unsorted || strainCount == 0 || strains[0].genes.seeds == other.strains[0].genes.seeds);
    }

    uint countLike(ref const Stack kind) const {
        if (isEmpty || item != kind.item || (strainCount > 0) != (kind.strainCount > 0)) {
            return 0;
        } else if (strainCount == 0) {
            return count;
        } else {
            MaybeIndex!uint run = runOf(kind.strains[0].genes);
            if (run.exists) {
                return strains[run.value].count;
            } else {
                return 0;
            }
        }
    }

    void addToRun(uint index, WildGenes arriving, uint amount) {
        if (index == strainCount) {
            strains[index] = Strain(arriving, 0);
            strainCount += 1;
        }
        strains[index].count += amount;
        count += amount;
    }

    void takeFromRun(uint index, uint amount) {
        strains[index].count -= amount;
        count -= amount;
        if (strains[index].count == 0) {
            foreach (later; index + 1 .. strainCount) {
                strains[later - 1] = strains[later];
            }
            strainCount -= 1;
            strains[strainCount] = Strain.init;
        }
        if (count == 0) {
            this = Stack.init;
        }
    }

    uint takeLike(ref const Stack kind, uint wanted) {
        uint taken = lowerOf(countLike(kind), wanted);
        if (taken > 0 && strainCount == 0) {
            draw(taken);
        } else if (taken > 0) {
            takeFromRun(runOf(kind.strains[0].genes).value, taken);
        }
        return taken;
    }

    uint kindCount() const {
        if (isEmpty) {
            return 0;
        } else if (strainCount == 0) {
            return 1;
        } else {
            return strainCount;
        }
    }

    Stack kindAt(uint index) const {
        if (strainCount == 0) {
            return Stack(item, 1);
        } else {
            return Stack.ofLiving(item, 1, strains[index].genes, sorting);
        }
    }

    Stack draw(uint wanted) {
        uint moved = lowerOf(wanted, count);
        Stack made = Stack(item, 0);
        made.sorting = sorting;
        if (strainCount == 0) {
            made.count = moved;
            count -= moved;
            if (count == 0) {
                this = Stack.init;
            }
        } else {
            while (made.count < moved) {
                uint part = lowerOf(moved - made.count, strains[0].count);
                made.addToRun(made.strainCount, strains[0].genes, part);
                takeFromRun(0, part);
            }
        }
        return made.emptied;
    }

    void pourInto(ref Stack target) {
        if (target.isEmpty) {
            target = draw(STACK_LIMIT);
        } else if (canJoin(target) && strainCount == 0) {
            uint moved = lowerOf(count, target.room);
            target.count += moved;
            draw(moved);
        } else if (canJoin(target)) {
            uint index = 0;
            while (index < strainCount) {
                uint moved = lowerOf(strains[index].count, target.room);
                MaybeIndex!uint place = target.placeFor(strains[index].genes);
                uint runs = strainCount;
                if (moved > 0 && place.exists) {
                    target.addToRun(place.value, strains[index].genes, moved);
                    takeFromRun(index, moved);
                }
                if (strainCount == runs) {
                    index += 1;
                }
            }
        }
    }
}

bool isSameKind(Stack a, Stack b) {
    return a.item == b.item && a.genes.exists == b.genes.exists && a.genes.stored.seeds == b.genes.stored.seeds;
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
            total += stack.countLike(kind);
        }
        return total;
    }

    bool spendKind(Stack kind) {
        uint slot = SLOT_COUNT;
        while (slot > 0 && slots[slot - 1].countLike(kind) == 0) {
            slot -= 1;
        }
        if (slot > 0) {
            slots[slot - 1].takeLike(kind, 1);
            return true;
        } else {
            return false;
        }
    }

    uint firstSlotHolding(Stack kind) const {
        uint slot = 0;
        while (slot < SLOT_COUNT && slots[slot].countLike(kind) == 0) {
            slot += 1;
        }
        return slot;
    }

    void takeKind(Stack kind, uint count) {
        uint left = count;
        uint slot = SLOT_COUNT;
        while (slot > 0 && left > 0) {
            slot -= 1;
            left -= slots[slot].takeLike(kind, left);
        }
    }

    uint loseShare() {
        Inventory before = this;
        uint lost = 0;
        foreach (slot; 0 .. SLOT_COUNT) {
            foreach (index; 0 .. before.slots[slot].kindCount) {
                Stack kind = before.slots[slot].kindAt(index);
                if (before.firstSlotHolding(kind) == slot) {
                    uint taken = before.countOfKind(kind) / LOSS_DIVISOR;
                    takeKind(kind, taken);
                    lost += taken;
                }
            }
        }
        return lost;
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
        Stack left = stack;
        pourWithin(0, SLOT_COUNT, left);
        return left.count;
    }

    void pour(Section section, ref Stack stack) {
        if (section == Section.pack) {
            pourWithin(HOTBAR_SLOTS, SLOT_COUNT, stack);
        } else {
            pourWithin(0, HOTBAR_SLOTS, stack);
        }
    }

    void joinWithin(uint first, uint end, ref Stack stack) {
        foreach (ref slot; slots[first .. end]) {
            if (!stack.isEmpty && !slot.isEmpty) {
                stack.pourInto(slot);
            }
        }
    }

    void pourWithin(uint first, uint end, ref Stack stack) {
        joinWithin(first, end, stack);
        foreach (ref slot; slots[first .. end]) {
            if (!stack.isEmpty && slot.isEmpty) {
                stack.pourInto(slot);
            }
        }
    }

    bool spendFrom(uint slot) {
        if (slots[slot].isEmpty) {
            return false;
        } else {
            slots[slot].draw(1);
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
                    left -= slots[slot].draw(left).count;
                }
            }
            return true;
        }
    }
}
