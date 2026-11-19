module plugins.game.screens;

import core.stdc.math : ceilf, floorf;
import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : higherOf, lowerOf;
import base.stdio : printed;
import common.worldgen.climate : Climate;
import common.worldgen.structure : edgeCells, edgeLength;
import client.plugins : sceneCount, sceneNameAt, worldCount, worldNameAt;
import plugins.crafting.crafting : HAND, Recipe, Station, Taken, canCraft, insights, recipes;
import plugins.crafting.inventory : HOTBAR_SLOTS, PACK_ROWS, Stack;
import plugins.crafting.items : Item, itemCount;
import plugins.game.bindings : Bound, Rules, boundCount, infoOf, isAllowed;
import plugins.game.game : Crafting, Deleting, FEW_CRAFTS, Game, PickKind, RecipePlan, Saving, Screen, UiAction, UiKind, WorldPick, isCatalogued, stationOf, timeOf, toolFor;
import plugins.game.hud : BAR_SHARE, Box, CYAN, Column, DIM, FrameMeter, GOLD, Hud, LINE_CAPACITY, NAME_CAPACITY, Panel, RAISED, RED, RIM, SOLID, STRIP_CELLS, WHITE, craftLabel, craftSwatch, displayName, displays, faded, geneStrip, itemName, lineEnd, nextLineStart, stackName, stationName, strainColor;
import plugins.game.input : Controls, keyLabel;

enum float LEAST_CELL_LINES = 1.4f;
enum uint CRAFT_COLUMNS = 34;
enum uint WINDOW_COLUMNS = 80;
enum uint CONTROL_COLUMNS = 34;
enum uint LABEL_COLUMNS = 10;
enum float WAITING_SHADE = 0.35f;
enum float WARM = 0.3f;
enum float WET = 0.3f;
enum uint MENU_FIXED_ROWS = 3;
enum uint WORLDS_FIRST_ROW = 1;
enum char SCENE_MARK = '~';
enum string INVENTORY_SHEET = "inventory";
enum string SURROUNDINGS_SHEET = "surroundings";
enum string CATALOG_SHEET = "catalog";
enum uint SHEETS_AFTER_EXTRA = 2;
enum uint RUN_COUNT_COLUMNS = 4;

alias SheetBuild = void function(ref Hud hud, ref const Game game, Box content);
alias MachineBuild = void function(ref Hud hud, ref const Game game, Box area);

struct Sheet {
    string name;
    SheetBuild build;
}

__gshared Array!Sheet extraSheets;
__gshared Array!MachineBuild machineScreens;

uint addMachineScreen(MachineBuild build) {
    machineScreens.append(build);
    return cast(uint) machineScreens.length - 1;
}

uint sheetCount(Rules rules) {
    uint always = cast(uint) extraSheets.length + SHEETS_AFTER_EXTRA;
    final switch (rules) {
        case Rules.survival:
            return always;
        case Rules.creative:
            return always + 1;
    }
}

string sheetName(uint sheet) {
    uint extra = cast(uint) extraSheets.length;
    if (sheet == 0) {
        return INVENTORY_SHEET;
    } else if (sheet <= extra) {
        return extraSheets.ptr[sheet - 1].name;
    } else if (sheet == extra + 1) {
        return SURROUNDINGS_SHEET;
    } else {
        return CATALOG_SHEET;
    }
}

uint sheetNamed(const(char)[] name) {
    uint last = cast(uint) extraSheets.length + SHEETS_AFTER_EXTRA;
    uint sheet = 0;
    while (sheet < last && sheetName(sheet) != name) {
        sheet += 1;
    }
    return sheet;
}

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
        case Screen.machine:
            machineScreens.ptr[game.machineScreen](hud, game, area);
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

Box tooltipBox(ref Hud hud, float w, float h) {
    float x = lowerOf(hud.cursor.x + 2 * hud.margin(), hud.width - hud.margin() - w);
    float y = lowerOf(hud.cursor.y + 2 * hud.margin(), hud.height - hud.margin() - h);
    hud.rect(x, y, w, h, RAISED);
    hud.outline(Box(x, y, w, h), hud.scale, RIM);
    return Box(x, y, w, h);
}

void tooltip(ref Hud hud, const(char)[] shown) {
    float pad = hud.padding();
    const(char)[] line = hud.fitting(shown, hud.width - 2 * hud.margin() - 2 * pad);
    Box box = tooltipBox(hud, hud.textWidth(line) + 2 * pad, hud.rowHeight() + pad);
    hud.text(box.x + pad, box.y + pad, line, WHITE);
}

void stackTooltip(ref Hud hud, ref const Game game, Stack stack) {
    char[LINE_CAPACITY] named;
    char[LINE_CAPACITY] buffer;
    const(char)[] name = stackName(game, stack, named[]);
    const(char)[] title = printed(buffer[], "%.*s x%u", cast(int) name.length, name.ptr, stack.count);
    if (stack.isBundle) {
        float pad = hud.padding();
        float row = hud.rowHeight();
        float cell = hud.atlas.lineHeight / 2;
        float strip = STRIP_CELLS * cell;
        const(char)[] line = hud.fitting(title, hud.width - 2 * hud.margin() - 2 * pad);
        float runs = row + strip + pad + hud.columns(RUN_COUNT_COLUMNS);
        Box box = tooltipBox(hud, higherOf(hud.textWidth(line), runs) + 2 * pad, (stack.strainCount + 1) * row + pad);
        hud.text(box.x + pad, box.y + pad, line, WHITE);
        foreach (index, ref run; stack.strains[0 .. stack.strainCount]) {
            char[LINE_CAPACITY] counted;
            float top = box.y + pad + (index + 1) * row;
            hud.rect(box.x + pad, top, hud.atlas.lineHeight, hud.atlas.lineHeight, strainColor(run.genes));
            geneStrip(hud, box.x + pad + row, top, cell, run.genes);
            hud.text(box.x + pad + row + strip + pad, top, printed(counted[], "x%u", run.count), DIM);
        }
    } else {
        tooltip(hud, title);
    }
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

uint listedScenes(Rules rules) {
    final switch (rules) {
        case Rules.survival:
            return 0;
        case Rules.creative:
            return sceneCount();
    }
}

const(char)[] pickName(WorldPick pick) {
    final switch (pick.kind) {
        case PickKind.world:
            return worldNameAt(pick.index);
        case PickKind.scene:
            return sceneNameAt(pick.index);
    }
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
            if (listedScenes(game.rules) > 0) {
                hud.clippedText(content.x, content.y + (WORLDS_FIRST_ROW - 1) * row, content.w, "worlds: * has a save, ~ is a scene, the one you are in is outlined", DIM);
            } else {
                hud.clippedText(content.x, content.y + (WORLDS_FIRST_ROW - 1) * row, content.w, "worlds: * has a save, the one you are in is outlined", DIM);
            }
            break;
        case Saving.refused:
            hud.clippedText(content.x, content.y + (WORLDS_FIRST_ROW - 1) * row, content.w, "this world's save is from another version: nothing is saved until you delete it", RED);
            break;
        case Saving.scene:
            hud.clippedText(content.x, content.y + (WORLDS_FIRST_ROW - 1) * row, content.w, "you are in a scene (~): one structure alone, and nothing is saved", DIM);
            break;
    }
    uint worlds = worldCount();
    uint count = worlds + listedScenes(game.rules);
    uint rows = cast(uint) higherOf(floorf(content.h / row), MENU_FIXED_ROWS + 1.0f) - MENU_FIXED_ROWS;
    uint columnCount = higherOf(cast(uint) ceilf(cast(float) count / rows), 1u);
    float columnWidth = (content.w - (columnCount - 1) * pad) / columnCount;
    foreach (index; 0 .. count) {
        WorldPick listed = WorldPick(index, PickKind.world);
        UiAction pick = {kind: UiKind.pickWorld, index: index};
        char mark = ' ';
        if (index >= worlds) {
            listed = WorldPick(index - worlds, PickKind.scene);
            pick = UiAction(index - worlds, UiKind.pickScene);
            mark = SCENE_MARK;
        } else if (game.worlds.saved.has(index)) {
            mark = '*';
        }
        const(char)[] name = pickName(listed);
        Box cell = Box(content.x + (index / rows) * (columnWidth + pad), content.y + (WORLDS_FIRST_ROW + index % rows) * row, columnWidth, row - hud.scale);
        hud.button(cell, printed(buffer[], "%c %.*s", mark, cast(int) name.length, name.ptr), Maybe!UiAction.of(pick));
        if (game.worlds.picked == Maybe!WorldPick.of(listed)) {
            hud.outline(cell, 2 * hud.scale, GOLD);
        } else if (listed == game.worlds.current) {
            hud.outline(cell, hud.scale, CYAN);
        }
    }
    Maybe!UiAction play;
    Maybe!UiAction remove;
    const(char)[] playLabel = "pick a world to play";
    const(char)[] deleteLabel = "pick a world to delete";
    if (game.worlds.picked.exists && game.worlds.picked.value.kind == PickKind.scene) {
        WorldPick picked = game.worlds.picked.value;
        const(char)[] name = pickName(picked);
        playLabel = printed(playBuffer[], "you are in the scene %.*s", cast(int) name.length, name.ptr);
        deleteLabel = "a scene is never saved";
        if (picked != game.worlds.current) {
            UiAction made = {kind: UiKind.playScene, index: picked.index};
            play = Maybe!UiAction.of(made);
            playLabel = printed(playBuffer[], "look at %.*s alone", cast(int) name.length, name.ptr);
        }
    } else if (game.worlds.picked.exists) {
        uint picked = game.worlds.picked.value.index;
        const(char)[] name = worldNameAt(picked);
        playLabel = printed(playBuffer[], "you are in %.*s", cast(int) name.length, name.ptr);
        deleteLabel = printed(deleteBuffer[], "%.*s has no save", cast(int) name.length, name.ptr);
        if (game.worlds.picked.value != game.worlds.current) {
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
    uint sheets = sheetCount(game.rules);
    uint extra = cast(uint) extraSheets.length;
    float tab = (box.w - (sheets + 1) * pad) / sheets;
    foreach (index; 0 .. sheets) {
        Box button = Box(box.x + pad + index * (tab + pad), box.y + pad, tab, row);
        UiAction choose = {kind: UiKind.sheet, index: index};
        hud.button(button, sheetName(index), Maybe!UiAction.of(choose));
        if (index == game.sheet) {
            hud.outline(button, 2 * hud.scale, GOLD);
        }
    }
    Box content = Box(box.x + pad, box.y + row + 3 * pad, box.w - 2 * pad, box.h - row - 4 * pad);
    if (game.sheet == 0) {
        buildItems(hud, game, content, HAND);
    } else if (game.sheet <= extra) {
        extraSheets.ptr[game.sheet - 1].build(hud, game, content);
    } else if (game.sheet == extra + 1) {
        buildSurroundings(hud, game, meter, content);
    } else {
        buildCatalog(hud, game, content);
    }
}

void wrappedRows(ref Hud hud, ref Panel panel, const(char)[] text, uint color) {
    size_t room = hud.charactersIn(panel.width);
    size_t start = 0;
    while (start < text.length) {
        size_t end = lineEnd(text, start, room);
        hud.row(panel, text[start .. end], color);
        start = nextLineStart(text, end);
    }
}

void buildJournal(ref Hud hud, ref const Game game, Box area) {
    char[LINE_CAPACITY] buffer;
    UiAction closing = {kind: UiKind.close};
    Box content = titled(hud, area, "journal", "close", closing);
    Panel panel = hud.scrollPanel(content, Column.first);
    uint unknown = 0;
    heading(hud, panel, "what you have noticed");
    foreach (index, ref rule; insights()) {
        if (game.noticed.has(cast(uint) index)) {
            hud.row(panel, rule.title, CYAN);
            wrappedRows(hud, panel, rule.notice, WHITE);
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

bool isCatalogFitting(ref const Hud hud, Box content, uint shown, float itemCell, float slotCell) {
    uint columns = columnsFor(hud, content, itemCell);
    uint itemRows = (shown + columns - 1) / columns;
    float items = itemRows * (itemCell + hud.padding());
    float slots = (PACK_ROWS + 1) * (slotCell + hud.padding());
    return columnsFor(hud, content, slotCell) >= HOTBAR_SLOTS && hud.rowHeight() + items + slots + 2 * hud.padding() <= content.h;
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
    while (cell > least && !isCatalogFitting(hud, content, shown, cell, cell)) {
        cell -= hud.scale;
    }
    float itemCell = cell;
    while (itemCell > hud.scale && !isCatalogFitting(hud, content, shown, itemCell, cell)) {
        itemCell -= hud.scale;
    }
    uint columns = columnsFor(hud, content, itemCell);
    hud.clippedText(content.x, content.y, content.w, "click takes a stack, right click takes one; put it in a slot below", DIM);
    Maybe!Item hovered;
    uint placed = 0;
    foreach (id; 1 .. itemCount()) {
        Item item = Item(cast(ushort) id);
        if (isCatalogued(item)) {
            Box box = Box(content.x + (placed % columns) * (itemCell + pad), content.y + row + (placed / columns) * (itemCell + pad), itemCell, itemCell);
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
    float gridTop = content.y + row + ((placed + columns - 1) / columns) * (itemCell + pad) + pad;
    slotGrid(hud, game, content.x, gridTop, cell, slotHovered);
    char[NAME_CAPACITY] storage;
    if (hovered.exists) {
        tooltip(hud, itemName(hovered.value, storage[]));
    } else if (slotHovered.exists && !slotHovered.value.isEmpty) {
        stackTooltip(hud, game, slotHovered.value);
    }
}

void buildStation(ref Hud hud, ref const Game game, Box area) {
    char[NAME_CAPACITY] place;
    UiAction closing = {kind: UiKind.close};
    Box content = titled(hud, area, stationName(game.workstation, place[]), "close", closing);
    uint built = 0;
    foreach (ref display; displays.slice()) {
        if (built == 0 && display.station(hud, game, content, game.workstation)) {
            built += 1;
        }
    }
    if (built == 0) {
        buildItems(hud, game, content, game.workstation);
    }
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
        stackTooltip(hud, game, hovered.value);
    } else if (recipe.exists) {
        recipeTooltip(hud, game, recipe.value);
    }
}

void recipeTooltip(ref Hud hud, ref const Game game, uint recipe) {
    char[LINE_CAPACITY] buffer;
    RecipePlan plan = game.planOf(recipe);
    double time = recipes()[recipe].time.value;
    if (plan.shortfall.count > 0) {
        char[NAME_CAPACITY] storage;
        const(char)[] missing = displayName(plan.shortfall.label, storage[]);
        tooltip(hud, printed(buffer[], "takes %.1fs; short %u %.*s", time, plan.shortfall.count, cast(int) missing.length, missing.ptr));
    } else if (plan.steps > 1) {
        tooltip(hud, printed(buffer[], "takes %.1fs; queues %u steps first; right click makes %u, crouch click all it can", time, plan.steps - 1, FEW_CRAFTS));
    } else {
        tooltip(hud, printed(buffer[], "takes %.1fs; right click makes %u, crouch click all it can", time, FEW_CRAFTS));
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
        if (recipe.station == station && panel.takes(2)) {
            char[LINE_CAPACITY] storage;
            char[LINE_CAPACITY] buffer;
            Box line = Box(panel.x, panel.y, panel.width, 2 * panel.row);
            Crafting shown = Crafting(Taken.init, recipe.time, cast(uint) index);
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
                char[NAME_CAPACITY] named;
                const(char)[] label = displayName(recipe.needs[need].label, named[]);
                length += printed(buffer[length .. $], "%.*s%u/%u %.*s", cast(int) separator.length, separator.ptr, lowerOf(held, recipe.needs[need].count), recipe.needs[need].count, cast(int) label.length, label.ptr).length;
            }
            uint needColor = RED;
            if (game.isRepeatedUpgrade(cast(uint) index) || game.inventory.canCraft(recipe)) {
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
        float across = label;
        uint first = 0;
        while (first < game.crafts.length && panel.takes(1)) {
            uint length = runLength(game, first);
            if (across + side > panel.width && across > label) {
                panel.advance();
                across = label;
            } else {
                queueSlot(hud, game, Box(panel.x + across, panel.y, side, side), Run(first, length), active);
                across += side + hud.padding();
                first += length;
            }
        }
        panel.advance();
    }
}

struct Run {
    uint first;
    uint length;

    bool holds(MaybeIndex!uint index) const {
        return index.exists && index.value >= first && index.value < first + length;
    }
}

bool isSameCraft(ref const Crafting a, ref const Crafting b) {
    return a.kind == b.kind && a.work is b.work && a.index == b.index && a.payload == b.payload && a.held.item == b.held.item;
}

uint runLength(ref const Game game, uint first) {
    uint end = first + 1;
    while (end < game.crafts.length && isSameCraft(game.crafts.ptr[first], game.crafts.ptr[end])) {
        end += 1;
    }
    return end - first;
}

void queueSlot(ref Hud hud, ref const Game game, Box slot, Run run, MaybeIndex!uint active) {
    char[LINE_CAPACITY] buffer;
    const(Crafting)* crafting = &game.crafts.ptr[run.first];
    uint swatch = craftSwatch(*crafting);
    if (!game.isWorkable(*crafting)) {
        swatch = faded(swatch, WAITING_SHADE);
    }
    hud.rect(slot.x, slot.y, slot.w, slot.h, RAISED);
    hud.rect(slot.x + hud.padding(), slot.y + hud.padding(), slot.w - 2 * hud.padding(), slot.h - 2 * hud.padding(), swatch);
    if (run.length > 1) {
        hud.text(slot.x + hud.padding(), slot.y, printed(buffer[], "%u", run.length), WHITE);
    }
    if (run.holds(active)) {
        const(Crafting)* working = &game.crafts.ptr[active.value];
        float done = 1 - (working.left / timeOf(*working)).value;
        hud.rect(slot.x, slot.y + slot.h - hud.padding(), slot.w * done, hud.padding(), GOLD);
    }
    UiAction cancel = {kind: UiKind.cancelCraft, index: run.first + run.length - 1};
    hud.hotspot(slot, cancel);
    if (hud.isUnderCursor(slot)) {
        hud.outline(slot, hud.scale, GOLD);
        queueTooltip(hud, game, run, active);
    }
}

void queueTooltip(ref Hud hud, ref const Game game, Run run, MaybeIndex!uint active) {
    char[LINE_CAPACITY] storage;
    char[LINE_CAPACITY] counted;
    char[LINE_CAPACITY] buffer;
    const(Crafting)* crafting = &game.crafts.ptr[run.first];
    const(char)[] name = craftLabel(*crafting, storage[]);
    if (run.length > 1) {
        name = printed(counted[], "%u x %.*s", run.length, cast(int) name.length, name.ptr);
    }
    Station station = stationOf(*crafting);
    char[NAME_CAPACITY] place;
    const(char)[] where = stationName(station, place[]);
    if (run.holds(active)) {
        tooltip(hud, printed(buffer[], "making %.*s; click to cancel one", cast(int) name.length, name.ptr));
    } else if (!game.isStationReady(station)) {
        tooltip(hud, printed(buffer[], "%.*s waits for you at a %.*s; click to cancel one", cast(int) name.length, name.ptr, cast(int) where.length, where.ptr));
    } else {
        tooltip(hud, printed(buffer[], "%.*s waits for the steps before it; click to cancel one", cast(int) name.length, name.ptr));
    }
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
        double cell = edgeLength(game.world.graph.layout).value / edgeCells(game.world.graph.layout.dimension);
        hud.row(panel, printed(buffer[], "%.*s and %.*s, %.0f blocks above the ground", cast(int) warmth.length, warmth.ptr, cast(int) wetness.length, wetness.ptr, game.altitude.value / cell), WHITE);
        foreach (ref display; displays.slice()) {
            display.surroundings(hud, game, panel, slot);
        }
    }
    hud.row(panel, printed(buffer[], "%u nodes deep, %.0f frames a second", game.world.graph.depthOf(slot), cast(double) meter.fps), DIM);
    hud.closeScroll(panel, content, Column.first);
}

float labelShare(ref const Hud hud, const(char)[] label, const(char)[] key, float width) {
    float wanted = hud.textWidth(label) + hud.padding();
    float keyWanted = hud.textWidth(key) + 2 * hud.padding();
    if (wanted + keyWanted <= width) {
        return width - keyWanted;
    } else {
        return width * wanted / (wanted + keyWanted);
    }
}

void buildControls(ref Hud hud, ref const Game game, ref const Controls controls, Box area) {
    float pad = hud.padding();
    float row = hud.rowHeight();
    UiAction back = {kind: UiKind.open, index: Screen.menu};
    Box content = titled(hud, area, "controls", "back", back);
    uint listed = 0;
    foreach (index; 0 .. boundCount()) {
        if (isAllowed(Bound(cast(ubyte) index), game.rules)) {
            listed += 1;
        }
    }
    uint rows = cast(uint) higherOf(floorf((content.h - 2 * row) / row), 1.0f);
    uint columnCount = higherOf(cast(uint) ceilf(cast(float) listed / rows), 1u);
    float columnWidth = (content.w - (columnCount - 1) * pad) / columnCount;
    hud.clippedText(content.x, content.y, content.w, "click a key, then press the new one; Esc cancels", DIM);
    uint shown = 0;
    foreach (index; 0 .. boundCount()) {
        Bound bound = Bound(cast(ubyte) index);
        if (isAllowed(bound, game.rules)) {
            float x = content.x + (shown / rows) * (columnWidth + pad);
            float y = content.y + row + (shown % rows) * row;
            const(char)[] name = keyLabel(controls.bindings.keys[index].slice());
            if (controls.awaiting.exists && controls.awaiting.value == bound) {
                name = "press a key";
            }
            float label = labelShare(hud, infoOf(bound).label, name, columnWidth);
            hud.clippedText(x, y, label, infoOf(bound).label, WHITE);
            Box key = Box(x + label, y, columnWidth - label, row - hud.scale);
            UiAction rebind = {kind: UiKind.rebind, index: cast(uint) index};
            hud.button(key, name, Maybe!UiAction.of(rebind));
            shown += 1;
        }
    }
    UiAction reset = {kind: UiKind.resetBindings};
    hud.button(Box(content.x, content.y + content.h - row, lowerOf(content.w, hud.columns(24)), row - hud.scale), "reset to defaults", Maybe!UiAction.of(reset));
}

