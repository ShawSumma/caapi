module client.screens;

import core.stdc.math : ceilf, floorf;
import base.maybe : Maybe, MaybeIndex;
import base.names : ENUM_NAMES;
import base.numbers : LN_TWO, higherOf, lowerOf;
import base.stdio : printed;
import base.units : Ratio;
import common.biology.air : AirMix, GAS_COUNT, GAS_NAMES, airOf;
import common.biology.breeding : expressionIn, productOf;
import common.biology.genome : GeneKind, MOST_GENES, enzymeOf;
import common.biology.kinetics : Route, clearanceOf;
import common.biology.metabolism : Operation;
import common.biology.molecule : Molecule;
import common.biology.organism : Organism;
import common.crafting : Crafting, HAND, IdSet, Insight, Product, Reaction, Recipe, Station, Synthesis, SynthesisRule, Taken, actsOnCompounds, canCraft, doseRoutes, insights, recipes, stationOf, syntheses, synthesized, timeOf;
import common.inventory : HOTBAR_SLOTS, PACK_ROWS, SLOT_COUNT, Sorting, Stack;
import common.material : isPlant, materialCount;
import common.worldgen.climate : Climate;
import client.bindings : ACTIONS, ACTION_COUNT, Action, Rules;
import client.game : CHOSEN_PLANTS, COLLECTION_RATE, Compound, DOSE_SIZE, Deleting, Game, MOST_COLLECTED_SECONDS, RAW_PER_DOSE, RecipePlan, Saving, Screen, Sheet, SHEET_COUNT, UiAction, UiKind, isCatalogued, sheetsFor, toolFor;
import common.items : Item, itemCount;
import client.hud : BAR_SHARE, Box, CYAN, Column, DIM, Effect, FIRST_HALF_NAME, FrameMeter, GOLD, Hud, LINE_CAPACITY, NAME_CAPACITY, PANEL, PLOT_SHARE, Panel, RAISED, RED, RIM, SOLID, STRIP_CELLS, WHITE, actsOnAny, bindsOf, craftLabel, craftSwatch, effectsOf, faded, itemName, letterColor, materialName, moleculeName, receptorName, stackMake, stackName, stationName, swatchOf;
import client.input : Controls, keyLabel;
import client.plugins : worldCount, worldNameAt;
import common.perception : Channel;
import plugins.api.api : Material;
import plugins.api.flags : Flags;

enum float LEAST_CELL_LINES = 1.4f;
enum uint CRAFT_COLUMNS = 34;
enum uint WINDOW_COLUMNS = 80;
enum uint BENCH_FIXED_ROWS = 4;
enum uint BUTTON_COUNT = 3;
enum uint CONTROL_COLUMNS = 34;
enum uint CONTROL_LABEL_COLUMNS = 22;
enum uint LABEL_COLUMNS = 10;
enum uint TWO_COLUMNS = 60;
enum float WAITING_SHADE = 0.35f;
enum size_t JOURNAL_CAPACITY = 1024;
enum float WARM = 0.3f;
enum float WET = 0.3f;
enum uint MENU_FIXED_ROWS = 3;
enum uint WORLDS_FIRST_ROW = 1;
immutable string[SHEET_COUNT] SHEET_NAMES = ["inventory", "body", "chemistry", "surroundings", "catalog"];

void buildScreen(ref Hud hud, ref const Game game, ref const Controls controls, ref const FrameMeter meter, Box area) {
    final switch (game.screen) {
        case Screen.none:
            break;
        case Screen.character:
            buildCharacter(hud, game, meter, area);
            break;
        case Screen.journal:
            buildJournal(hud, game, area);
            break;
        case Screen.menu:
            buildMenu(hud, game, area);
            break;
        case Screen.controls:
            buildControls(hud, game, controls, area);
            break;
        case Screen.bench:
            buildBench(hud, game, area);
            break;
        case Screen.collector:
            buildCollector(hud, game, area);
            break;
        case Screen.station:
            buildStation(hud, game, area);
            break;
    }
}

Box centered(Box area, float w, float h) {
    return Box(floorf(area.x + (area.w - w) / 2), floorf(area.y + (area.h - h) / 2), w, h);
}

void frame(ref Hud hud, Box box) {
    hud.rect(box.x, box.y, box.w, box.h, SOLID);
    hud.outline(box, hud.scale, RIM);
}

void tooltip(ref Hud hud, const(char)[] shown) {
    float pad = hud.padding();
    const(char)[] line = hud.fitting(shown, hud.width - 2 * hud.margin() - 2 * pad);
    float w = hud.textWidth(line) + 2 * pad;
    float h = hud.rowHeight() + pad;
    float x = lowerOf(hud.cursor.x + 2 * hud.margin(), hud.width - hud.margin() - w);
    float y = lowerOf(hud.cursor.y + 2 * hud.margin(), hud.height - hud.margin() - h);
    hud.rect(x, y, w, h, RAISED);
    hud.outline(Box(x, y, w, h), hud.scale, RIM);
    hud.text(x + pad, y + pad, line, WHITE);
}

void heading(ref Hud hud, ref Panel panel, const(char)[] shown) {
    hud.row(panel, shown, GOLD);
}

void barRow(ref Hud hud, ref Panel panel, const(char)[] label, float share, uint color, const(char)[] after) {
    if (panel.takes(1)) {
        float labelWidth = hud.columns(LABEL_COLUMNS + 4);
        float bar = higherOf(lowerOf(BAR_SHARE * hud.height, panel.width - labelWidth - hud.columns(12)), 0.0f);
        hud.put(panel, 0, label, WHITE);
        hud.fillBar(panel.x + labelWidth, panel.y, bar, share, color);
        hud.put(panel, labelWidth + bar + hud.padding(), after, DIM);
        panel.advance();
    }
}

void buttonRow(ref Hud hud, ref Panel panel, const(char)[] label, Maybe!UiAction action) {
    if (panel.takes(1)) {
        hud.button(Box(panel.x, panel.y, panel.width, panel.row - hud.scale), label, action);
        panel.advance();
    }
}

Box window(ref Hud hud, Box area) {
    float w = lowerOf(area.w, hud.columns(WINDOW_COLUMNS) + 2 * hud.padding());
    Box box = centered(area, w, area.h);
    frame(hud, box);
    return box;
}

float titleButton(ref const Hud hud, const(char)[] label, float room) {
    return lowerOf(hud.columns(cast(uint) label.length + 2), room / 3);
}

Box titled(ref Hud hud, Box area, const(char)[] title, const(char)[] label, UiAction action) {
    float pad = hud.padding();
    float row = hud.rowHeight();
    Box box = window(hud, area);
    float wide = titleButton(hud, label, box.w);
    hud.clippedText(box.x + pad, box.y + pad, box.w - wide - 3 * pad, title, GOLD);
    hud.button(Box(box.x + box.w - pad - wide, box.y + pad, wide, row), label, Maybe!UiAction.of(action));
    return Box(box.x + pad, box.y + row + 3 * pad, box.w - 2 * pad, box.h - row - 4 * pad);
}

void buildMenu(ref Hud hud, ref const Game game, Box area) {
    char[LINE_CAPACITY] buffer;
    char[LINE_CAPACITY] playBuffer;
    char[LINE_CAPACITY] deleteBuffer;
    float pad = hud.padding();
    float row = hud.rowHeight();
    UiAction resume = {kind: UiKind.close};
    Box content = titled(hud, area, "click any empty spot to play", "resume", resume);
    UiAction controls = {kind: UiKind.open, index: Screen.controls};
    float beside = titleButton(hud, "resume", content.w + 2 * pad);
    float wide = titleButton(hud, "controls", content.w + 2 * pad);
    hud.button(Box(content.x + content.w - beside - pad - wide, content.y - row - 2 * pad, wide, row), "controls", Maybe!UiAction.of(controls));
    final switch (game.worlds.saving) {
        case Saving.enabled:
            hud.clippedText(content.x, content.y + (WORLDS_FIRST_ROW - 1) * row, content.w, "worlds: * has a save, the one you are in is outlined", DIM);
            break;
        case Saving.refused:
            hud.clippedText(content.x, content.y + (WORLDS_FIRST_ROW - 1) * row, content.w, "this world's save is from another version: nothing is saved until you delete it", RED);
            break;
    }
    uint count = worldCount();
    uint rows = cast(uint) higherOf(floorf(content.h / row), MENU_FIXED_ROWS + 1.0f) - MENU_FIXED_ROWS;
    uint columnCount = higherOf(cast(uint) ceilf(cast(float) count / rows), 1u);
    float columnWidth = (content.w - (columnCount - 1) * pad) / columnCount;
    foreach (index; 0 .. count) {
        const(char)[] name = worldNameAt(index);
        char mark = ' ';
        if (game.worlds.saved.has(index)) {
            mark = '*';
        }
        Box cell = Box(content.x + (index / rows) * (columnWidth + pad), content.y + (WORLDS_FIRST_ROW + index % rows) * row, columnWidth, row - hud.scale);
        UiAction pick = {kind: UiKind.pickWorld, index: index};
        hud.button(cell, printed(buffer[], "%c %.*s", mark, cast(int) name.length, name.ptr), Maybe!UiAction.of(pick));
        if (game.worlds.picked == MaybeIndex!uint.of(index)) {
            hud.outline(cell, 2 * hud.scale, GOLD);
        } else if (index == game.worlds.current) {
            hud.outline(cell, hud.scale, CYAN);
        }
    }
    Maybe!UiAction play;
    Maybe!UiAction remove;
    const(char)[] playLabel = "pick a world to play";
    const(char)[] deleteLabel = "pick a world to delete";
    if (game.worlds.picked.exists) {
        uint picked = game.worlds.picked.value;
        const(char)[] name = worldNameAt(picked);
        playLabel = printed(playBuffer[], "you are in %.*s", cast(int) name.length, name.ptr);
        deleteLabel = printed(deleteBuffer[], "%.*s has no save", cast(int) name.length, name.ptr);
        if (picked != game.worlds.current) {
            UiAction made = {kind: UiKind.playWorld, index: picked};
            play = Maybe!UiAction.of(made);
            playLabel = printed(playBuffer[], "play %.*s", cast(int) name.length, name.ptr);
        }
        if (game.worlds.saved.has(picked) && game.worlds.deleting == Deleting.asked) {
            UiAction made = {kind: UiKind.deleteWorld, index: picked};
            remove = Maybe!UiAction.of(made);
            deleteLabel = printed(deleteBuffer[], "click again: %.*s is lost for good", cast(int) name.length, name.ptr);
        } else if (game.worlds.saved.has(picked)) {
            UiAction made = {kind: UiKind.askDelete, index: picked};
            remove = Maybe!UiAction.of(made);
            deleteLabel = printed(deleteBuffer[], "delete %.*s and start it over", cast(int) name.length, name.ptr);
        }
    }
    float half = (content.w - pad) / 2;
    float bottom = content.y + content.h - row;
    hud.button(Box(content.x, bottom, half, row - hud.scale), playLabel, play);
    hud.button(Box(content.x + half + pad, bottom, half, row - hud.scale), deleteLabel, remove);
}

void buildCharacter(ref Hud hud, ref const Game game, ref const FrameMeter meter, Box area) {
    float pad = hud.padding();
    float row = hud.rowHeight();
    Box box = window(hud, area);
    uint sheets = sheetsFor(game.rules);
    float tab = (box.w - (sheets + 1) * pad) / sheets;
    foreach (index; 0 .. sheets) {
        Box button = Box(box.x + pad + index * (tab + pad), box.y + pad, tab, row);
        UiAction choose = {kind: UiKind.sheet, index: cast(uint) index};
        hud.button(button, SHEET_NAMES[index], Maybe!UiAction.of(choose));
        if (index == game.sheet) {
            hud.outline(button, 2 * hud.scale, GOLD);
        }
    }
    Box content = Box(box.x + pad, box.y + row + 3 * pad, box.w - 2 * pad, box.h - row - 4 * pad);
    final switch (game.sheet) {
        case Sheet.items:
            buildItems(hud, game, content, HAND);
            break;
        case Sheet.body:
            buildBody(hud, game, content);
            break;
        case Sheet.chemistry:
            buildChemistry(hud, game, content);
            break;
        case Sheet.surroundings:
            buildSurroundings(hud, game, meter, content);
            break;
        case Sheet.catalog:
            buildCatalog(hud, game, content);
            break;
    }
}

void wrappedRows(ref Hud hud, ref Panel panel, const(char)[] text, uint color) {
    size_t room = cast(size_t) higherOf(floorf(panel.width / hud.atlas.advance), 1.0f);
    size_t start = 0;
    while (start < text.length) {
        size_t end = lowerOf(start + room, text.length);
        if (end < text.length) {
            size_t space = end;
            while (space > start && text[space] != ' ') {
                space -= 1;
            }
            if (space > start) {
                end = space;
            }
        }
        hud.row(panel, text[start .. end], color);
        start = end;
        while (start < text.length && text[start] == ' ') {
            start += 1;
        }
    }
}

void buildJournal(ref Hud hud, ref const Game game, Box area) {
    char[LINE_CAPACITY] buffer;
    char[LINE_CAPACITY] storage;
    UiAction closing = {kind: UiKind.close};
    Box content = titled(hud, area, "journal", "close", closing);
    Panel panel = hud.scrollPanel(content, Column.first);
    IdSet known = game.knowledge();
    uint unknown = 0;
    heading(hud, panel, "what you have noticed");
    foreach (index, ref rule; insights()) {
        if (known.has(cast(uint) index)) {
            hud.row(panel, rule.title, CYAN);
            wrappedRows(hud, panel, rule.notice, WHITE);
            char[JOURNAL_CAPACITY] opens;
            size_t length = printed(opens[], "opens:").length;
            foreach (recipe, ref made; recipes()) {
                if (made.insight.exists && made.insight.value.id == index) {
                    Crafting shown = Crafting(Taken.init, Molecule.init, made.time, cast(uint) recipe);
                    const(char)[] label = craftLabel(shown, storage[]);
                    char[NAME_CAPACITY] place;
                    const(char)[] where = stationName(made.station, place[]);
                    length += printed(opens[length .. $], " %.*s at the %.*s;", cast(int) label.length, label.ptr, cast(int) where.length, where.ptr).length;
                }
            }
            wrappedRows(hud, panel, opens[0 .. length], DIM);
        } else {
            unknown += 1;
        }
    }
    if (unknown == insights().length) {
        hud.row(panel, "nothing yet; look closely at what you mine and make", WHITE);
    }
    if (unknown > 0) {
        hud.row(panel, printed(buffer[], "%u more things to notice", unknown), DIM);
    }
    hud.closeScroll(panel, content, Column.first);
}

uint columnsFor(ref const Hud hud, Box content, float cell) {
    return cast(uint) higherOf(floorf((content.w + hud.padding()) / (cell + hud.padding())), 1.0f);
}

bool isCatalogFitting(ref const Hud hud, Box content, uint shown, float cell) {
    uint columns = columnsFor(hud, content, cell);
    uint rows = (shown + columns - 1) / columns + PACK_ROWS + 1;
    return columns >= HOTBAR_SLOTS && hud.rowHeight() + rows * (cell + hud.padding()) + 2 * hud.padding() <= content.h;
}

void buildCatalog(ref Hud hud, ref const Game game, Box content) {
    float pad = hud.padding();
    float row = hud.rowHeight();
    uint shown = 0;
    foreach (id; 1 .. itemCount()) {
        if (isCatalogued(Item(cast(ushort) id))) {
            shown += 1;
        }
    }
    float least = hud.atlas.lineHeight * LEAST_CELL_LINES;
    float cell = hud.hotbarSide();
    while (cell > least && !isCatalogFitting(hud, content, shown, cell)) {
        cell -= hud.scale;
    }
    uint columns = columnsFor(hud, content, cell);
    hud.clippedText(content.x, content.y, content.w, "click takes a stack, right click takes one; put it in a slot below", DIM);
    Maybe!Item hovered;
    uint placed = 0;
    foreach (id; 1 .. itemCount()) {
        Item item = Item(cast(ushort) id);
        if (isCatalogued(item)) {
            Box box = Box(content.x + (placed % columns) * (cell + pad), content.y + row + (placed / columns) * (cell + pad), cell, cell);
            hud.stackCell(box, Stack(item, 1), RAISED);
            UiAction take = {kind: UiKind.takeItem, index: id};
            hud.hotspot(box, take);
            if (hud.isUnderCursor(box)) {
                hud.outline(box, hud.scale, GOLD);
                hovered = Maybe!Item.of(item);
            }
            placed += 1;
        }
    }
    Maybe!Stack slotHovered;
    float gridTop = content.y + row + ((placed + columns - 1) / columns) * (cell + pad) + pad;
    slotGrid(hud, game, content.x, gridTop, cell, slotHovered);
    char[NAME_CAPACITY] storage;
    if (hovered.exists) {
        tooltip(hud, itemName(hovered.value, storage[]));
    } else if (slotHovered.exists && !slotHovered.value.isEmpty) {
        char[LINE_CAPACITY] buffer;
        tooltip(hud, stackName(game, slotHovered.value, buffer[]));
    }
}

void buildStation(ref Hud hud, ref const Game game, Box area) {
    char[NAME_CAPACITY] place;
    UiAction closing = {kind: UiKind.close};
    Box content = titled(hud, area, stationName(game.workstation, place[]), "close", closing);
    if (hasSyntheses(game.workstation)) {
        buildSynthesisStation(hud, game, content, game.workstation);
    } else {
        buildItems(hud, game, content, game.workstation);
    }
}

bool hasSyntheses(Station station) {
    uint index = 0;
    while (index < syntheses().length && syntheses()[index].station != station) {
        index += 1;
    }
    return index < syntheses().length;
}

void slotGrid(ref Hud hud, ref const Game game, float x, float y, float cell, ref Maybe!Stack hovered) {
    float pad = hud.padding();
    foreach (row; 0 .. PACK_ROWS + 1) {
        foreach (column; 0 .. HOTBAR_SLOTS) {
            uint slot = cast(uint)(HOTBAR_SLOTS * (row + 1) + column);
            float top = y + row * (cell + pad);
            if (row == PACK_ROWS) {
                slot = cast(uint) column;
                top += pad;
            }
            Box box = Box(x + column * (cell + pad), top, cell, cell);
            hud.stackCell(box, game.inventory.slots[slot], RAISED);
            UiAction click = {kind: UiKind.slot, index: slot};
            hud.hotspot(box, click);
            if (slot == game.inventory.selected) {
                hud.outline(box, hud.scale, GOLD);
            }
            if (hud.isUnderCursor(box)) {
                hud.outline(box, hud.scale, WHITE);
                hovered = Maybe!Stack.of(game.inventory.slots[slot]);
            }
        }
    }
}

void buildItems(ref Hud hud, ref const Game game, Box content, Station station) {
    float pad = hud.padding();
    float row = hud.rowHeight();
    float least = hud.atlas.lineHeight * LEAST_CELL_LINES;
    float craftWidth = hud.columns(CRAFT_COLUMNS);
    uint gridRows = PACK_ROWS + 1;
    float beside = (content.w - craftWidth - 2 * pad) / HOTBAR_SLOTS - pad;
    float cell = lowerOf(hud.hotbarSide(), (content.h - 2 * row - pad) / gridRows - pad);
    Box crafting;
    if (lowerOf(beside, cell) >= least) {
        cell = lowerOf(beside, cell);
        float gridWidth = HOTBAR_SLOTS * (cell + pad);
        crafting = Box(content.x + gridWidth + pad, content.y, content.w - gridWidth - pad, content.h);
    } else {
        cell = higherOf(lowerOf(cell, (content.w / HOTBAR_SLOTS) - pad), least);
        float gridHigh = 2 * row + gridRows * (cell + pad) + pad;
        crafting = Box(content.x, content.y + gridHigh + pad, content.w, content.h - gridHigh - pad);
    }
    char[NAME_CAPACITY] storage;
    char[LINE_CAPACITY] buffer;
    float gridWidth = HOTBAR_SLOTS * (cell + pad);
    hud.clippedText(content.x, content.y, gridWidth, "inventory", GOLD);
    const(char)[] tool = toolFor(game.miningTier());
    hud.clippedText(content.x, content.y + row, gridWidth, printed(buffer[], "mining with %.*s", cast(int) tool.length, tool.ptr), DIM);
    Maybe!Stack hovered;
    slotGrid(hud, game, content.x, content.y + 2 * row, cell, hovered);
    Panel panel = hud.scrollPanel(crafting, Column.first);
    buildQueue(hud, game, panel);
    Maybe!uint recipe = buildRecipes(hud, game, panel, station);
    if (station == HAND) {
        hud.row(panel, "more at placed stations", DIM);
    }
    hud.closeScroll(panel, crafting, Column.first);
    if (hovered.exists && !hovered.value.isEmpty) {
        char[LINE_CAPACITY] named;
        const(char)[] name = stackName(game, hovered.value, named[]);
        tooltip(hud, printed(buffer[], "%.*s x%u", cast(int) name.length, name.ptr, hovered.value.count));
    } else if (recipe.exists) {
        recipeTooltip(hud, game, recipe.value);
    }
}

void recipeTooltip(ref Hud hud, ref const Game game, uint recipe) {
    char[LINE_CAPACITY] buffer;
    RecipePlan plan = game.planOf(recipe);
    double time = recipes()[recipe].time.value;
    if (plan.shortfall.count > 0) {
        tooltip(hud, printed(buffer[], "takes %.1fs; short %u %.*s", time, plan.shortfall.count, cast(int) plan.shortfall.label.length, plan.shortfall.label.ptr));
    } else if (plan.steps > 1) {
        tooltip(hud, printed(buffer[], "takes %.1fs; queues %u steps first", time, plan.steps - 1));
    } else {
        tooltip(hud, printed(buffer[], "takes %.1fs", time));
    }
}

string ownership(ref const Game game, ref const Recipe recipe) {
    if (game.owned.has(recipe.upgrade.id)) {
        return "have it";
    } else {
        return "queued";
    }
}

Maybe!uint buildRecipes(ref Hud hud, ref const Game game, ref Panel panel, Station station) {
    float swatch = hud.atlas.lineHeight;
    Maybe!uint hovered;
    foreach (index, ref recipe; recipes()) {
        if (recipe.station == station && game.isKnownRecipe(cast(uint) index) && panel.takes(2)) {
            char[LINE_CAPACITY] storage;
            char[LINE_CAPACITY] buffer;
            Box line = Box(panel.x, panel.y, panel.width, 2 * panel.row);
            Crafting shown = Crafting(Taken.init, Molecule.init, recipe.time, cast(uint) index);
            const(char)[] title = craftLabel(shown, storage[]);
            RecipePlan plan = game.planOf(cast(uint) index);
            uint color = DIM;
            if (game.isRepeatedUpgrade(cast(uint) index)) {
                string owned = ownership(game, recipe);
                title = printed(buffer[], "%.*s, %.*s", cast(int) title.length, title.ptr, cast(int) owned.length, owned.ptr);
            } else if (plan.shortfall.count == 0) {
                color = WHITE;
                hud.rect(line.x, line.y, line.w, line.h - hud.scale, RAISED);
            }
            hud.rect(panel.x, panel.y, swatch, swatch, craftSwatch(shown));
            hud.put(panel, swatch + hud.padding(), title, color);
            panel.advance();
            size_t length = 0;
            foreach (need; 0 .. recipe.needed) {
                const(char)[] separator = "";
                if (need > 0) {
                    separator = ", ";
                }
                uint held = game.inventory.countAmong(recipe.needs[need].accepted);
                length += printed(buffer[length .. $], "%.*s%u/%u %.*s", cast(int) separator.length, separator.ptr, lowerOf(held, recipe.needs[need].count), recipe.needs[need].count, cast(int) recipe.needs[need].label.length, recipe.needs[need].label.ptr).length;
            }
            uint needColor = RED;
            if (game.inventory.canCraft(recipe)) {
                needColor = DIM;
            } else if (plan.shortfall.count == 0) {
                needColor = CYAN;
            }
            hud.put(panel, swatch + hud.padding(), buffer[0 .. length], needColor);
            panel.advance();
            if (!game.isRepeatedUpgrade(cast(uint) index)) {
                UiAction make = {kind: UiKind.craft, index: cast(uint) index};
                hud.hotspot(line, make);
                if (hud.isUnderCursor(line)) {
                    hud.outline(line, hud.scale, GOLD);
                    hovered = Maybe!uint.of(cast(uint) index);
                }
            }
        }
    }
    return hovered;
}

void buildQueue(ref Hud hud, ref const Game game, ref Panel panel) {
    if (panel.takes(1)) {
        float side = panel.row - hud.scale;
        float label = hud.columns(6);
        hud.put(panel, 0, "queue", GOLD);
        if (game.crafts.length == 0) {
            hud.put(panel, label, "empty; click a recipe", DIM);
        }
        MaybeIndex!uint active = game.activeCraft();
        foreach (index, ref crafting; game.crafts.slice()) {
            Box slot = Box(panel.x + label + index * (side + hud.padding()), panel.y, side, side);
            if (slot.x + side <= panel.x + panel.width) {
                uint swatch = craftSwatch(crafting);
                if (!game.isWorkable(crafting)) {
                    swatch = faded(swatch, WAITING_SHADE);
                }
                hud.rect(slot.x, slot.y, slot.w, slot.h, RAISED);
                hud.rect(slot.x + hud.padding(), slot.y + hud.padding(), side - 2 * hud.padding(), side - 2 * hud.padding(), swatch);
                if (active == MaybeIndex!uint.of(cast(uint) index)) {
                    float done = 1 - (crafting.left / timeOf(crafting)).value;
                    hud.rect(slot.x, slot.y + side - hud.padding(), side * done, hud.padding(), GOLD);
                }
                UiAction cancel = {kind: UiKind.cancelCraft, index: cast(uint) index};
                hud.hotspot(slot, cancel);
                if (hud.isUnderCursor(slot)) {
                    hud.outline(slot, hud.scale, GOLD);
                    queueTooltip(hud, game, cast(uint) index, active);
                }
            }
        }
        panel.advance();
    }
}

void queueTooltip(ref Hud hud, ref const Game game, uint index, MaybeIndex!uint active) {
    char[LINE_CAPACITY] storage;
    char[LINE_CAPACITY] buffer;
    const(Crafting)* crafting = &game.crafts.ptr[index];
    const(char)[] name = craftLabel(*crafting, storage[]);
    Station station = stationOf(*crafting);
    char[NAME_CAPACITY] place;
    const(char)[] where = stationName(station, place[]);
    if (active == MaybeIndex!uint.of(index)) {
        tooltip(hud, printed(buffer[], "making %.*s; click to cancel", cast(int) name.length, name.ptr));
    } else if (!game.isStationReady(station)) {
        tooltip(hud, printed(buffer[], "%.*s waits for you at a %.*s; click to cancel", cast(int) name.length, name.ptr, cast(int) where.length, where.ptr));
    } else {
        tooltip(hud, printed(buffer[], "%.*s waits for ingredients; click to cancel", cast(int) name.length, name.ptr));
    }
}

void compoundList(ref Hud hud, ref const Game game, ref Panel panel) {
    char[NAME_CAPACITY] storage;
    char[LINE_CAPACITY] buffer;
    heading(hud, panel, "compounds you hold");
    if (game.compounds.length == 0) {
        hud.row(panel, "none; a press squeezes extract out of living blocks", WHITE);
    }
    foreach (index, ref compound; game.compounds.slice()) {
        if (panel.takes(1)) {
            Box line = Box(panel.x, panel.y, panel.width, panel.row);
            bool chosen = game.chosenCompound.exists && game.chosenCompound.value == index;
            if (chosen) {
                hud.rect(line.x, line.y, line.w, line.h - hud.scale, RAISED);
            }
            const(char)[] name = moleculeName(compound.molecule, storage[]);
            hud.put(panel, 0, printed(buffer[], "%-8.*s extract %4.1f  doses %.0f", cast(int) name.length, name.ptr, cast(double) compound.raw, cast(double) compound.doses), CYAN);
            UiAction choose = {kind: UiKind.chooseCompound, index: cast(uint) index};
            hud.hotspot(line, choose);
            if (chosen || hud.isUnderCursor(line)) {
                hud.outline(line, hud.scale, GOLD);
            }
            panel.advance();
        }
    }
}

const(Compound)* chosenOf(ref const Game game) {
    if (game.chosenCompound.exists && game.chosenCompound.value < game.compounds.length) {
        return &game.compounds.ptr[game.chosenCompound.value];
    } else {
        return null;
    }
}

void compoundDetail(ref Hud hud, ref const Game game, ref Panel panel) {
    char[NAME_CAPACITY] storage;
    char[LINE_CAPACITY] buffer;
    const(Compound)* compound = chosenOf(game);
    if (compound is null) {
        heading(hud, panel, "choose a compound");
        hud.row(panel, "press extract into doses at a press", DIM);
        hud.row(panel, "change compounds at a lab", DIM);
    } else {
        const(char)[] name = moleculeName(compound.molecule, storage[]);
        heading(hud, panel, name);
        float half = LN_TWO / clearanceOf(compound.molecule).value;
        hud.row(panel, printed(buffer[], "leaves the blood by half every %.0fs", cast(double) half), WHITE);
        if (game.hasAssay()) {
            hud.row(panel, bindsOf(DOSE_SIZE, compound.affinity[0 .. compound.receptors], compound.efficacy[0 .. compound.receptors], game.organism.receptors.slice(), buffer[]), DIM);
        } else {
            hud.row(panel, "an assay kit from a lab shows what it does", DIM);
        }
    }
}

void compoundPlot(ref Hud hud, ref const Game game, ref Panel panel) {
    const(Compound)* compound = chosenOf(game);
    if (compound !is null && game.hasAssay()) {
        const(Ratio)[] affinity = compound.affinity[0 .. compound.receptors];
        float plot = PLOT_SHARE * hud.height;
        uint plotRows = cast(uint)(plot / hud.rowHeight()) + 1;
        if (actsOnAny(DOSE_SIZE, affinity) && panel.takes(plotRows)) {
            hud.assayPlot(panel.x, panel.y, panel.width, plot, affinity, compound.efficacy[0 .. compound.receptors]);
            foreach (_; 0 .. plotRows) {
                panel.advance();
            }
        }
    }
}

void buildChemistry(ref Hud hud, ref const Game game, Box content) {
    if (content.w >= hud.columns(TWO_COLUMNS)) {
        Box first = firstHalf(hud, content);
        Box second = secondHalf(hud, content);
        Panel left = hud.scrollPanel(first, Column.first);
        Panel right = hud.scrollPanel(second, Column.second);
        chemistryColumns(hud, game, left, right);
        hud.closeScroll(left, first, Column.first);
        hud.closeScroll(right, second, Column.second);
    } else {
        Panel panel = hud.scrollPanel(content, Column.first);
        chemistryColumns(hud, game, panel, panel);
        hud.closeScroll(panel, content, Column.first);
    }
}

Box firstHalf(ref const Hud hud, Box content) {
    return Box(content.x, content.y, (content.w - hud.padding()) / 2, content.h);
}

Box secondHalf(ref const Hud hud, Box content) {
    float half = (content.w - hud.padding()) / 2;
    return Box(content.x + half + hud.padding(), content.y, half, content.h);
}

void chemistryColumns(ref Hud hud, ref const Game game, ref Panel left, ref Panel right) {
    char[LINE_CAPACITY] buffer;
    compoundList(hud, game, left);
    compoundDetail(hud, game, right);
    compoundPlot(hud, game, right);
    const(Compound)* compound = chosenOf(game);
    if (compound !is null) {
        heading(hud, right, "take a dose");
        if (compound.doses < 1) {
            hud.row(right, printed(buffer[], "no doses: a press makes one from %.0f extract", cast(double) RAW_PER_DOSE), DIM);
        }
        foreach (index, ref route; doseRoutes()) {
            Maybe!UiAction take;
            if (compound.doses >= 1) {
                UiAction made = {kind: UiKind.takeDose, index: cast(uint) index};
                take = Maybe!UiAction.of(made);
            }
            buttonRow(hud, right, route.title, take);
        }
    }
}

void buildSynthesisStation(ref Hud hud, ref const Game game, Box content, Station station) {
    Box first = firstHalf(hud, content);
    Box second = secondHalf(hud, content);
    Panel left = hud.scrollPanel(first, Column.first);
    Panel right = hud.scrollPanel(second, Column.second);
    compoundList(hud, game, left);
    compoundDetail(hud, game, left);
    const(Compound)* compound = chosenOf(game);
    if (compound !is null) {
        foreach (index, ref rule; syntheses()) {
            if (rule.station == station && rule.actsOnCompounds) {
                synthesisButton(hud, game, left, *compound, Synthesis(cast(ubyte) index));
            }
        }
    }
    if (game.extractionAt(station).exists) {
        livingList(hud, game, left);
    }
    buildQueue(hud, game, right);
    Maybe!uint recipe = buildRecipes(hud, game, right, station);
    hud.closeScroll(left, first, Column.first);
    hud.closeScroll(right, second, Column.second);
    if (recipe.exists) {
        recipeTooltip(hud, game, recipe.value);
    }
}

void livingList(ref Hud hud, ref const Game game, ref Panel panel) {
    char[LINE_CAPACITY] storage;
    char[LINE_CAPACITY] buffer;
    heading(hud, panel, "press a living block for 1 extract");
    uint listed = 0;
    foreach (slot; 0 .. SLOT_COUNT) {
        if (game.isPressable(slot)) {
            const(char)[] name = stackName(game, game.inventory.slots[slot], storage[]);
            UiAction press = {kind: UiKind.pressLiving, index: slot};
            buttonRow(hud, panel, printed(buffer[], "%.*s x%u", cast(int) name.length, name.ptr, game.inventory.slots[slot].count), Maybe!UiAction.of(press));
            listed += 1;
        }
    }
    if (listed == 0) {
        hud.row(panel, "nothing living; break leaves, plants or cactus", DIM);
    }
}

void synthesisButton(ref Hud hud, ref const Game game, ref Panel panel, ref const Compound compound, Synthesis synthesis) {
    char[NAME_CAPACITY] storage;
    char[NAME_CAPACITY] reagentStorage;
    char[LINE_CAPACITY] buffer;
    const(SynthesisRule)* rule = &syntheses()[synthesis.id];
    const(char)[] label = rule.title;
    Maybe!Molecule product = synthesized(compound.molecule, synthesis);
    UiAction made = {kind: UiKind.synthesize, index: synthesis.id};
    Maybe!UiAction action = Maybe!UiAction.of(made);
    const(char)[] shown;
    if (rule.reaction == Reaction.press) {
        shown = printed(buffer[], "%.*s from %.0f extract", cast(int) label.length, label.ptr, cast(double) RAW_PER_DOSE);
    } else if (!product.exists || product.value == compound.molecule) {
        shown = printed(buffer[], "%.*s: no effect on it", cast(int) label.length, label.ptr);
        action = Maybe!UiAction.init;
    } else {
        const(char)[] name = moleculeName(product.value, storage[]);
        const(char)[] reagent = itemName(rule.reagent, reagentStorage[]);
        uint held = game.inventory.countOf(rule.reagent);
        shown = printed(buffer[], "%.*s -> %.*s, %u/1 %.*s", cast(int) label.length, label.ptr, cast(int) name.length, name.ptr, lowerOf(held, 1u), cast(int) reagent.length, reagent.ptr);
    }
    buttonRow(hud, panel, shown, action);
}

void buildBody(ref Hud hud, ref const Game game, Box content) {
    if (content.w >= hud.columns(TWO_COLUMNS)) {
        Box first = firstHalf(hud, content);
        Box second = secondHalf(hud, content);
        Panel left = hud.scrollPanel(first, Column.first);
        Panel right = hud.scrollPanel(second, Column.second);
        bodyFeelings(hud, game, left);
        bodyReceptors(hud, game, right);
        hud.closeScroll(left, first, Column.first);
        hud.closeScroll(right, second, Column.second);
    } else {
        Panel panel = hud.scrollPanel(content, Column.first);
        bodyFeelings(hud, game, panel);
        bodyReceptors(hud, game, panel);
        hud.closeScroll(panel, content, Column.first);
    }
}

void bodyFeelings(ref Hud hud, ref const Game game, ref Panel panel) {
    char[LINE_CAPACITY] buffer;
    heading(hud, panel, "how you feel");
    Effect[Channel.max + 1] effects;
    uint count = effectsOf(game, effects[]);
    if (count == 0) {
        hud.row(panel, "normal", WHITE);
    }
    foreach (ref effect; effects[0 .. count]) {
        barRow(hud, panel, effect.label, effect.share, CYAN, "");
    }
    heading(hud, panel, "in your body");
    const(Organism)* organism = &game.organism;
    if (organism.body.count == 0) {
        hud.row(panel, "nothing; eat, breathe or take a dose", WHITE);
    }
    foreach (held; 0 .. organism.body.count) {
        char[NAME_CAPACITY] storage;
        const(char)[] name = moleculeName(organism.body.species[held].molecule, storage[]);
        float total = organism.body.species[held].gut.value + organism.body.species[held].lung.value + organism.body.species[held].blood.value;
        float half = LN_TWO / clearanceOf(organism.body.species[held].molecule).value;
        string where = "blood";
        if (organism.body.species[held].gut.value > organism.body.species[held].blood.value) {
            where = "stomach";
        } else if (organism.body.species[held].lung.value > organism.body.species[held].blood.value) {
            where = "lungs";
        }
        barRow(hud, panel, name, total / 2, GOLD, printed(buffer[], "%.*s %.0fs", cast(int) where.length, where.ptr, cast(double) half));
    }
}

void bodyReceptors(ref Hud hud, ref const Game game, ref Panel panel) {
    char[LINE_CAPACITY] buffer;
    const(Organism)* organism = &game.organism;
    heading(hud, panel, "receptors held");
    foreach (index, occupied; organism.occupancy.slice()) {
        char[2] name;
        receptorName(organism.receptors.ptr[index], name[]);
        barRow(hud, panel, name[], occupied.value, CYAN, printed(buffer[], "%.0f%%", cast(double) occupied.value * 100));
    }
    heading(hud, panel, "genome");
    size_t length = printed(buffer[], "receptors").length;
    char half = FIRST_HALF_NAME;
    foreach (ref gene; organism.genome.slice()) {
        if (gene.kind == GeneKind.receptorHalf) {
            length += printed(buffer[length .. $], " %c", half).length;
            half += 1;
        }
    }
    hud.row(panel, buffer[0 .. length], WHITE);
    length = printed(buffer[], "enzymes").length;
    foreach (ref gene; organism.genome.slice()) {
        if (gene.kind == GeneKind.enzyme) {
            string operation = ENUM_NAMES!Operation[enzymeOf(gene).operation];
            length += printed(buffer[length .. $], " %.*s", cast(int) operation.length, operation.ptr).length;
        }
    }
    hud.row(panel, buffer[0 .. length], WHITE);
}

string warmthWord(float warmth) {
    if (warmth > WARM) {
        return "warm";
    } else if (warmth < -WARM) {
        return "cold";
    } else {
        return "mild";
    }
}

string wetnessWord(float wetness) {
    if (wetness > WET) {
        return "wet";
    } else if (wetness < -WET) {
        return "dry";
    } else {
        return "neither wet nor dry";
    }
}

void buildSurroundings(ref Hud hud, ref const Game game, ref const FrameMeter meter, Box content) {
    Panel panel = hud.scrollPanel(content, Column.first);
    char[LINE_CAPACITY] buffer;
    uint slot = game.world.graph.slotOf(game.characterState.position.node).value;
    heading(hud, panel, "here");
    if (!game.world.graph.nodeAt(slot).hasState) {
        hud.row(panel, "still being explored", WHITE);
    } else {
        Climate climate = game.world.graph.stateAt(slot).climate.climate();
        string warmth = warmthWord(climate.warmth());
        string wetness = wetnessWord(climate.wetness);
        hud.row(panel, printed(buffer[], "%.*s and %.*s, %.2f above the ground", cast(int) warmth.length, warmth.ptr, cast(int) wetness.length, wetness.ptr, cast(double) game.altitude.value), WHITE);
        heading(hud, panel, "the air");
        AirMix air = airOf(climate);
        foreach (gas; 0 .. GAS_COUNT) {
            barRow(hud, panel, GAS_NAMES[gas], air.fractions[gas].value, CYAN, printed(buffer[], "%.0f%%", cast(double) air.fractions[gas].value * 100));
        }
        heading(hud, panel, "plants that grow well here");
        foreach (id; 1 .. materialCount()) {
            Material plant = Material(cast(ubyte) id);
            if (isPlant(plant)) {
                char[NAME_CAPACITY] storage;
                float fit = expressionIn(plant, climate);
                barRow(hud, panel, materialName(plant, storage[]), fit, GOLD, printed(buffer[], "%.0f%%", cast(double) fit * 100));
            }
        }
        hud.row(panel, printed(buffer[], "crossing seeds here mutates %.0f%%", cast(double) game.mutationOddsAt(slot).value * 100), WHITE);
    }
    hud.row(panel, printed(buffer[], "%u nodes deep, %.0f frames a second", game.world.graph.depthOf(slot), cast(double) meter.fps), DIM);
    hud.closeScroll(panel, content, Column.first);
}

bool isListed(Action action, Rules rules) {
    return ACTIONS[action].needs == Rules.survival || rules == Rules.creative;
}

void buildControls(ref Hud hud, ref const Game game, ref const Controls controls, Box area) {
    float pad = hud.padding();
    float row = hud.rowHeight();
    UiAction back = {kind: UiKind.open, index: Screen.menu};
    Box content = titled(hud, area, "controls", "back", back);
    uint listed = 0;
    foreach (index; 0 .. ACTION_COUNT) {
        if (isListed(cast(Action) index, game.rules)) {
            listed += 1;
        }
    }
    uint rows = cast(uint) higherOf(floorf((content.h - 2 * row) / row), 1.0f);
    uint columnCount = higherOf(cast(uint) ceilf(cast(float) listed / rows), 1u);
    float columnWidth = (content.w - (columnCount - 1) * pad) / columnCount;
    hud.clippedText(content.x, content.y, content.w, "click a key, then press the new one; Esc cancels", DIM);
    uint shown = 0;
    foreach (index; 0 .. ACTION_COUNT) {
        Action action = cast(Action) index;
        if (isListed(action, game.rules)) {
            float x = content.x + (shown / rows) * (columnWidth + pad);
            float y = content.y + row + (shown % rows) * row;
            float label = lowerOf(hud.columns(CONTROL_LABEL_COLUMNS), columnWidth / 2);
            hud.clippedText(x, y, label, ACTIONS[index].label, WHITE);
            Box key = Box(x + label, y, columnWidth - label, row - hud.scale);
            const(char)[] name = keyLabel(controls.bindings.keys[index].slice());
            if (controls.awaiting.exists && controls.awaiting.value == action) {
                name = "press a key";
            }
            UiAction rebind = {kind: UiKind.rebind, index: cast(uint) index};
            hud.button(key, name, Maybe!UiAction.of(rebind));
            shown += 1;
        }
    }
    UiAction reset = {kind: UiKind.resetBindings};
    hud.button(Box(content.x, content.y + content.h - row, lowerOf(content.w, hud.columns(24)), row - hud.scale), "reset to defaults", Maybe!UiAction.of(reset));
}

char markOf(ref const Game game, uint slot) {
    char mark = ' ';
    foreach (index; 0 .. CHOSEN_PLANTS) {
        if (game.chosen[index] == MaybeIndex!uint.of(slot)) {
            mark = cast(char)('1' + index);
        }
    }
    return mark;
}

float stripLeft(ref const Hud hud, const(char)[] label, float room, float cell) {
    float strip = STRIP_CELLS * cell;
    if (hud.textWidth(label) + hud.padding() + strip <= room) {
        return room - strip;
    } else {
        return room;
    }
}

void buildBench(ref Hud hud, ref const Game game, Box area) {
    float pad = hud.padding();
    float row = hud.rowHeight();
    float inner = lowerOf(area.w - 2 * pad, hud.columns(WINDOW_COLUMNS));
    float half = (inner - pad) / 2;
    float cell = hud.atlas.lineHeight / 2;
    uint fit = cast(uint) higherOf(floorf((area.h - 3 * pad) / row), 0.0f);
    uint listRows = 0;
    if (fit > BENCH_FIXED_ROWS) {
        listRows = fit - BENCH_FIXED_ROWS;
    }
    uint plants = 0;
    foreach (slot; 0 .. SLOT_COUNT) {
        if (game.isBreedable(slot)) {
            plants += 1;
        }
    }
    uint plantRows = lowerOf(plants, listRows);
    uint geneRows = lowerOf(game.organism.genome.count, listRows);
    uint body = higherOf(higherOf(plantRows, geneRows), 1u);
    Box box = centered(area, inner + 2 * pad, (BENCH_FIXED_ROWS + body) * row + 3 * pad);
    frame(hud, box);
    float x = box.x + pad;
    float y = box.y + pad;
    char[LINE_CAPACITY] buffer;
    MaybeIndex!uint bench = game.world.graph.slotOf(game.machine.node);
    if (bench.exists) {
        float odds = game.mutationOddsAt(bench.value).value;
        hud.clippedText(x, y, inner, printed(buffer[], "bench: crossing here mutates %.0f%%", cast(double) odds * 100), GOLD);
    }
    y += row;
    hud.clippedText(x, y, half, "your plants: click two", DIM);
    hud.clippedText(x + half + pad, y, half, "your genome", DIM);
    y += row;
    if (plants == 0) {
        hud.clippedText(x, y, half, "none; break a plant to carry one", WHITE);
    }
    uint listed = 0;
    foreach (slot; 0 .. SLOT_COUNT) {
        if (game.isBreedable(slot) && listed < plantRows) {
            Box line = Box(x, y + listed * row, half, row);
            if (listed + 1 == plantRows && plants > plantRows) {
                hud.clippedText(line.x, line.y, half, printed(buffer[], "+%u more plants", plants - plantRows + 1), DIM);
            } else {
                plantRow(hud, game, line, slot, cell);
            }
            listed += 1;
        }
    }
    char halfName = FIRST_HALF_NAME;
    foreach (shown, ref gene; game.organism.genome.slice()) {
        const(char)[] label;
        final switch (gene.kind) {
            case GeneKind.receptorHalf:
                label = printed(buffer[], "receptor %c", halfName);
                halfName += 1;
                break;
            case GeneKind.enzyme:
                string operation = ENUM_NAMES!Operation[enzymeOf(gene).operation];
                label = printed(buffer[], "enzyme, %.*s", cast(int) operation.length, operation.ptr);
                break;
        }
        if (shown < geneRows) {
            float top = y + shown * row;
            float left = stripLeft(hud, label, half, cell);
            hud.clippedText(x + half + pad, top, left, label, WHITE);
            if (left < half) {
                foreach (letter; 0 .. lowerOf(cast(uint) gene.length, STRIP_CELLS)) {
                    hud.rect(x + half + pad + left + letter * cell, top, cell - hud.scale, hud.atlas.lineHeight, letterColor(gene.letters[letter]));
                }
            }
        }
    }
    y += body * row + pad;
    float wide = (inner - (BUTTON_COUNT - 1) * pad) / BUTTON_COUNT;
    Maybe!UiAction cross;
    if (game.isChosenBreedable(0) && game.isChosenBreedable(1)) {
        UiAction made = {kind: UiKind.cross};
        cross = Maybe!UiAction.of(made);
    }
    Maybe!UiAction splice;
    if (game.isChosenBreedable(0) && game.organism.genome.count < MOST_GENES) {
        UiAction made = {kind: UiKind.splice};
        splice = Maybe!UiAction.of(made);
    }
    UiAction closing = {kind: UiKind.close};
    hud.button(Box(x, y, wide, row), "cross 1 with 2", cross);
    hud.button(Box(x + wide + pad, y, wide, row), "splice 1 into you", splice);
    hud.button(Box(x + 2 * (wide + pad), y, wide, row), "close", Maybe!UiAction.of(closing));
}

void plantRow(ref Hud hud, ref const Game game, Box line, uint slot, float cell) {
    Stack stack = game.inventory.slots[slot];
    char mark = markOf(game, slot);
    if (mark != ' ') {
        hud.rect(line.x, line.y, line.w, line.h - hud.scale, RAISED);
    }
    char[NAME_CAPACITY] plantStorage;
    char[NAME_CAPACITY] productStorage;
    char[LINE_CAPACITY] buffer;
    const(char)[] plant = itemName(stack.item, plantStorage[]);
    const(char)[] make = stackMake(game, stack, productStorage[]);
    const(char)[] text = printed(buffer[], "%c %-9.*s x%-2u %.*s", mark, cast(int) plant.length, plant.ptr, stack.count, cast(int) make.length, make.ptr);
    float left = line.w;
    if (stack.sorting == Sorting.sorted) {
        left = stripLeft(hud, text, line.w, cell);
    }
    hud.clippedText(line.x, line.y, left, text, CYAN);
    if (left < line.w) {
        hud.geneStrip(line.x + left, line.y, cell, stack.genes.value);
    }
    UiAction choose = {kind: UiKind.choosePlant, index: slot};
    hud.hotspot(line, choose);
    if (hud.isUnderCursor(line)) {
        hud.outline(line, hud.scale, GOLD);
    }
}

void buildCollector(ref Hud hud, ref const Game game, Box area) {
    float pad = hud.padding();
    float row = hud.rowHeight();
    float inner = lowerOf(area.w - 2 * pad, hud.columns(CRAFT_COLUMNS + 16));
    Box box = centered(area, inner + 2 * pad, (GAS_COUNT + 5) * row + 3 * pad);
    frame(hud, box);
    Panel panel = Panel(box.x + pad, box.y + pad, row, inner, GAS_COUNT + 4);
    char[LINE_CAPACITY] buffer;
    heading(hud, panel, "collector");
    hud.row(panel, "fills with the air around it", DIM);
    barRow(hud, panel, "full", game.machineFill.value, GOLD, printed(buffer[], "%.0f%%", cast(double) game.machineFill.value * 100));
    float most = (COLLECTION_RATE * MOST_COLLECTED_SECONDS).value;
    float total = 0;
    foreach (gas; 0 .. GAS_COUNT) {
        float amount = game.machineAir[gas].value;
        total += amount;
        barRow(hud, panel, GAS_NAMES[gas], amount / most, CYAN, printed(buffer[], "%.2f", cast(double) amount));
    }
    float wide = (inner - pad) / 2;
    float y = box.y + pad + (GAS_COUNT + 4) * row;
    Maybe!UiAction breathe;
    if (total > 0) {
        UiAction made = {kind: UiKind.breathe};
        breathe = Maybe!UiAction.of(made);
    }
    UiAction closing = {kind: UiKind.close};
    hud.button(Box(box.x + pad, y, wide, row), "breathe it in", breathe);
    hud.button(Box(box.x + 2 * pad + wide, y, wide, row), "close", Maybe!UiAction.of(closing));
}
