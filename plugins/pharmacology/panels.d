module plugins.pharmacology.panels;

import core.stdc.math : floorf, powf;
import base.maybe : Maybe, MaybeIndex;
import base.names : ENUM_NAMES;
import base.numbers : LN_TWO, higherOf, lowerOf;
import base.stdio : printed;
import base.units : Ratio;
import client.drawing : ScreenPoint;
import common.material : materialCount;
import common.perception : MOST_SENSES;
import common.worldgen.climate : Climate;
import plugins.api.api : Material;
import plugins.crafting.crafting : Station;
import plugins.crafting.inventory : SLOT_COUNT, Sorting, Stack;
import plugins.crafting.items : ItemKind;
import plugins.game.bindings : Action;
import plugins.game.game : Act, Game, UiAction, UiKind;
import plugins.game.hud : Anchor, BAR_BACK_SHARE, Box, CYAN, Column, DIM, Display, Effect, GOLD, Hud, LINE_CAPACITY, NAME_CAPACITY, Panel, RAISED, STRIP_CELLS, WHITE, effectLabel, effectsOf, faded, geneStrip, itemName, letterColor, materialName, stackName;
import plugins.game.input : Controls, keyLabel;
import plugins.game.screens : CRAFT_COLUMNS, WINDOW_COLUMNS, barRow, buildQueue, buildRecipes, buttonRow, centered, frame, heading, recipeTooltip;
import plugins.pharmacology.air : AirMix, GAS_COUNT, GAS_NAMES, airOf;
import plugins.pharmacology.breeding : expressionIn, isPlant, productOf;
import plugins.pharmacology.genome : GeneKind, MOST_GENES, Receptor, enzymeOf;
import plugins.pharmacology.kinetics : clearanceOf;
import plugins.pharmacology.metabolism : Operation;
import plugins.pharmacology.catalog : CALL_DIGITS, callNumber, digitOf;
import plugins.pharmacology.molecule : GRID_CELLS, GRID_SIDE, Molecule, fragmentAt, fragmentCount, isConjugated;
import plugins.pharmacology.organism : Organism;
import plugins.pharmacology.player : CHOSEN_PLANTS, COLLECTION_RATE, Compound, DOSE_SIZE, LivingReading, MOST_COLLECTED_SECONDS, PLANT_DOSE, Pharma, Ripeness, Sight, breatheMachine, choose, chooseCompound, chosen, chosenCompound, compounds, crossChosen, cycleCatalogCell, eatingShare, extractionAt, hasAssay, isBreedable, isChosenBreedable, isKnownProduct, isPressable, moleculeName, mutationOddsAt, organism, pharma, pressLiving, spliceChosen, synthesize, takeDose, toggleCatalogConjugation;
import plugins.pharmacology.synthesis : Reaction, Synthesis, SynthesisRule, actsOnCompounds, doseRoutes, syntheses, synthesisBy, synthesized;

enum float PLOT_SHARE = 0.1f;
enum uint TARGET_COLUMNS = 34;
enum uint ASSAY_POINTS = 48;
enum float LEAST_ASSAY_DECADE = -3;
enum float ASSAY_DECADES = 4;
enum char FIRST_HALF_NAME = 'A';
enum Ratio BINDS_SHOWN = Ratio(0.1f);
enum uint BENCH_FIXED_ROWS = 4;
enum uint BUTTON_COUNT = 3;
enum uint TWO_COLUMNS = 60;
enum string BODY_SHEET = "body";
enum string CHEMISTRY_SHEET = "chemistry";
enum uint CATALOG_ROWS = 5;
enum float CATALOG_CELL_ROWS = 1.2f;

UiAction acting(Act act, uint index) {
    UiAction made = {kind: UiKind.act, index: index, act: act};
    return made;
}

void actPress(ref Game game, uint slot) {
    pressLiving(game, slot);
}

void actCross(ref Game game, uint index) {
    crossChosen(game);
}

void actSplice(ref Game game, uint index) {
    spliceChosen(game);
}

void actBreathe(ref Game game, uint index) {
    breatheMachine(game);
}

void actSynthesize(ref Game game, uint synthesis) {
    synthesize(game, Synthesis(cast(ubyte) synthesis));
}

void actTakeDose(ref Game game, uint route) {
    takeDose(game, route);
}

const(char)[] receptorName(ref const Receptor receptor, char[] buffer) {
    buffer[0] = cast(char)(FIRST_HALF_NAME + receptor.firstHalf);
    buffer[1] = cast(char)(FIRST_HALF_NAME + receptor.secondHalf);
    return buffer[0 .. 2];
}

char efficacySign(Ratio efficacy) {
    if (efficacy.value > 0) {
        return '+';
    } else if (efficacy.value < 0) {
        return '-';
    } else {
        return '0';
    }
}

Ratio occupancyAt(Ratio concentration, Ratio affinity) {
    return Ratio(concentration.value / (concentration.value + affinity.value));
}

bool actsOnAny(Ratio dose, const(Ratio)[] affinity) {
    uint index = 0;
    while (index < affinity.length && !(occupancyAt(dose, affinity[index]) > BINDS_SHOWN)) {
        index += 1;
    }
    return index < affinity.length;
}

const(char)[] bindsOf(Ratio dose, const(Ratio)[] affinity, const(Ratio)[] efficacy, const(Receptor)[] receptors, char[] buffer) {
    size_t length = printed(buffer, "acts on").length;
    foreach (index; 0 .. affinity.length) {
        if (occupancyAt(dose, affinity[index]) > BINDS_SHOWN) {
            char[2] name;
            receptorName(receptors[index], name[]);
            length += printed(buffer[length .. $], " %c%c%c", name[0], name[1], efficacySign(efficacy[index])).length;
        }
    }
    if (length == "acts on".length) {
        return printed(buffer, "does nothing to you");
    } else {
        return buffer[0 .. length];
    }
}

const(char)[] makeOf(ref const Game game, Molecule product, char[] buffer) {
    char[NAME_CAPACITY] storage;
    if (isKnownProduct(game, product)) {
        const(char)[] molecule = moleculeName(product, storage[]);
        return printed(buffer, "makes %.*s", cast(int) molecule.length, molecule.ptr);
    } else {
        return printed(buffer, "unidentified");
    }
}

const(char)[] stackMake(ref const Game game, ref const Stack stack, char[] buffer) {
    final switch (stack.sorting) {
        case Sorting.unsorted:
            return printed(buffer, "unidentified");
        case Sorting.sorted:
            return makeOf(game, productOf(stack.item.block, stack.strains[0].genes), buffer);
    }
}

ScreenPoint assayPoint(float x, float y, float w, float h, uint point, float affinity) {
    float share = cast(float) point / (ASSAY_POINTS - 1);
    float concentration = powf(10, LEAST_ASSAY_DECADE + share * ASSAY_DECADES);
    float occupied = concentration / (concentration + affinity);
    return ScreenPoint(x + w * share, y + h * (1 - occupied));
}

void assayPlot(ref Hud hud, float x, float y, float w, float h, const(Ratio)[] affinity, const(Ratio)[] efficacy) {
    hud.rect(x, y, w, h, faded(WHITE, BAR_BACK_SHARE / 2));
    foreach (index; 0 .. affinity.length) {
        uint color = faded(WHITE, BAR_BACK_SHARE * 2);
        if (efficacy[index].value > 0) {
            color = GOLD;
        } else if (efficacy[index].value < 0) {
            color = CYAN;
        }
        foreach (point; 1 .. ASSAY_POINTS) {
            hud.line(assayPoint(x, y, w, h, point - 1, affinity[index].value), assayPoint(x, y, w, h, point, affinity[index].value), hud.scale, color);
        }
    }
}

Ratio busy(ref const Game game) {
    return eatingShare(game);
}

bool target(ref Hud hud, ref const Game game, ref const Controls controls, const(char)[] name) {
    const(Pharma)* own = &pharma(game);
    if (own.sight != Sight.living) {
        return false;
    } else {
        char[LINE_CAPACITY] buffer;
        char[NAME_CAPACITY] storage;
        const(LivingReading)* reading = &own.living;
        const(char)[] mine = keyLabel(controls.bindings.keys[Action.mine].slice());
        const(Ratio)[] affinity = reading.affinity[0 .. reading.receptors];
        float plot = PLOT_SHARE * hud.height;
        uint plotRows = cast(uint)(plot / hud.rowHeight()) + 1;
        if (!actsOnAny(PLANT_DOSE, affinity)) {
            plotRows = 0;
        }
        const(char)[] make = makeOf(game, reading.product, storage[]);
        Panel panel = hud.openPanel(Anchor.topRight, hud.columns(TARGET_COLUMNS), 4 + plotRows);
        hud.row(panel, name, WHITE);
        final switch (reading.growth) {
            case Ripeness.wild:
                hud.row(panel, make, CYAN);
                break;
            case Ripeness.ripe:
                hud.row(panel, printed(buffer[], "%.*s, ripe, %.0f%% suited here", cast(int) make.length, make.ptr, cast(double) reading.fit.value * 100), CYAN);
                break;
            case Ripeness.growing:
                hud.row(panel, printed(buffer[], "%.*s, ripe in %.0fs", cast(int) make.length, make.ptr, cast(double) reading.left.value), CYAN);
                break;
        }
        if (hasAssay(game)) {
            hud.row(panel, bindsOf(PLANT_DOSE, affinity, reading.efficacy[0 .. reading.receptors], own.organism.receptors.slice(), buffer[]), DIM);
        } else if (isKnownProduct(game, reading.product)) {
            hud.row(panel, "an assay kit reads its effect", DIM);
        } else {
            hud.row(panel, "a press shows what it makes", DIM);
        }
        hud.row(panel, printed(buffer[], "%.*s: break it to carry", cast(int) mine.length, mine.ptr), DIM);
        if (plotRows > 0 && panel.left >= plotRows) {
            assayPlot(hud, panel.x, panel.y, panel.width, plot, affinity, reading.efficacy[0 .. reading.receptors]);
        }
        return true;
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
            bool picked = game.chosenCompound.exists && game.chosenCompound.value == index;
            if (picked) {
                hud.rect(line.x, line.y, line.w, line.h - hud.scale, RAISED);
            }
            const(char)[] name = moleculeName(compound.molecule, storage[]);
            hud.put(panel, 0, printed(buffer[], "%-8.*s extract %4.1f  doses %.0f", cast(int) name.length, name.ptr, cast(double) compound.raw, cast(double) compound.doses), CYAN);
            hud.hotspot(line, acting(&chooseCompound, cast(uint) index));
            if (picked || hud.isUnderCursor(line)) {
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
        if (hasAssay(game)) {
            hud.row(panel, bindsOf(DOSE_SIZE, compound.affinity[0 .. compound.receptors], compound.efficacy[0 .. compound.receptors], game.organism.receptors.slice(), buffer[]), DIM);
        } else {
            hud.row(panel, "an assay kit from a lab shows what it does", DIM);
        }
    }
}

void compoundPlot(ref Hud hud, ref const Game game, ref Panel panel) {
    const(Compound)* compound = chosenOf(game);
    if (compound !is null && hasAssay(game)) {
        const(Ratio)[] affinity = compound.affinity[0 .. compound.receptors];
        float plot = PLOT_SHARE * hud.height;
        uint plotRows = cast(uint)(plot / hud.rowHeight()) + 1;
        if (actsOnAny(DOSE_SIZE, affinity) && panel.takes(plotRows)) {
            assayPlot(hud, panel.x, panel.y, panel.width, plot, affinity, compound.efficacy[0 .. compound.receptors]);
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
        MaybeIndex!uint pressing = synthesisBy(Reaction.press);
        if (compound.doses < 1 && pressing.exists) {
            hud.row(right, printed(buffer[], "no doses: a press makes one from %.0f extract", cast(double) syntheses()[pressing.value].extract), DIM);
        }
        foreach (index, ref route; doseRoutes()) {
            Maybe!UiAction take;
            if (compound.doses >= 1 && (route.device.kind == ItemKind.nothing || game.inventory.countOf(route.device) > 0)) {
                take = Maybe!UiAction.of(acting(&actTakeDose, cast(uint) index));
            }
            buttonRow(hud, right, route.title, take);
        }
    }
}

bool hasSyntheses(Station station) {
    uint index = 0;
    while (index < syntheses().length && syntheses()[index].station != station) {
        index += 1;
    }
    return index < syntheses().length;
}

bool station(ref Hud hud, ref const Game game, Box content, Station station) {
    if (!hasSyntheses(station)) {
        return false;
    } else {
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
        if (extractionAt(station).exists) {
            livingList(hud, game, left, extractionAt(station).value);
        }
        buildQueue(hud, game, right);
        Maybe!uint recipe = buildRecipes(hud, game, right, station);
        hud.closeScroll(left, first, Column.first);
        hud.closeScroll(right, second, Column.second);
        if (recipe.exists) {
            recipeTooltip(hud, game, recipe.value);
        }
        return true;
    }
}

void livingList(ref Hud hud, ref const Game game, ref Panel panel, uint extraction) {
    char[LINE_CAPACITY] storage;
    char[LINE_CAPACITY] buffer;
    heading(hud, panel, printed(buffer[], "press a living block for %.0f extract", cast(double) syntheses()[extraction].extract));
    uint listed = 0;
    foreach (slot; 0 .. SLOT_COUNT) {
        if (isPressable(game, slot)) {
            const(char)[] name = stackName(game, game.inventory.slots[slot], storage[]);
            buttonRow(hud, panel, printed(buffer[], "%.*s x%u", cast(int) name.length, name.ptr, game.inventory.slots[slot].count), Maybe!UiAction.of(acting(&actPress, slot)));
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
    Maybe!UiAction action = Maybe!UiAction.of(acting(&actSynthesize, synthesis.id));
    const(char)[] shown;
    if (rule.reaction == Reaction.press) {
        shown = printed(buffer[], "%.*s from %.0f extract", cast(int) label.length, label.ptr, cast(double) rule.extract);
    } else if (!product.exists || product.value == compound.molecule) {
        shown = printed(buffer[], "%.*s: no effect on it", cast(int) label.length, label.ptr);
        action = Maybe!UiAction.init;
    } else {
        const(char)[] name = moleculeName(product.value, storage[]);
        const(char)[] reagent = itemName(rule.reagent, reagentStorage[]);
        uint held = game.inventory.countOf(rule.reagent);
        shown = printed(buffer[], "%.*s -> %.*s, %u/1 %.*s", cast(int) label.length, label.ptr, cast(int) name.length, name.ptr, lowerOf(held, 1u), cast(int) reagent.length, reagent.ptr);
        if (held == 0) {
            action = Maybe!UiAction.init;
        }
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
    Effect[MOST_SENSES] effects;
    uint count = effectsOf(game, effects[]);
    if (count == 0) {
        hud.row(panel, "normal", WHITE);
    }
    foreach (ref effect; effects[0 .. count]) {
        barRow(hud, panel, effectLabel(effect, buffer[]), effect.share, CYAN, "");
    }
    heading(hud, panel, "in your body");
    const(Organism)* body = &game.organism;
    if (body.body.count == 0) {
        hud.row(panel, "nothing; eat, breathe or take a dose", WHITE);
    }
    foreach (held; 0 .. body.body.count) {
        char[NAME_CAPACITY] storage;
        const(char)[] name = moleculeName(body.body.species[held].molecule, storage[]);
        float total = body.body.species[held].gut.value + body.body.species[held].lung.value + body.body.species[held].blood.value;
        float half = LN_TWO / clearanceOf(body.body.species[held].molecule).value;
        string where = "blood";
        if (body.body.species[held].gut.value > body.body.species[held].blood.value) {
            where = "stomach";
        } else if (body.body.species[held].lung.value > body.body.species[held].blood.value) {
            where = "lungs";
        }
        barRow(hud, panel, name, total / 2, GOLD, printed(buffer[], "%.*s %.0fs", cast(int) where.length, where.ptr, cast(double) half));
    }
}

void bodyReceptors(ref Hud hud, ref const Game game, ref Panel panel) {
    char[LINE_CAPACITY] buffer;
    const(Organism)* body = &game.organism;
    heading(hud, panel, "receptors held");
    foreach (index, occupied; body.occupancy.slice()) {
        char[2] name;
        receptorName(body.receptors.ptr[index], name[]);
        barRow(hud, panel, name[], occupied.value, CYAN, printed(buffer[], "%.0f%%", cast(double) occupied.value * 100));
    }
    heading(hud, panel, "genome");
    size_t length = printed(buffer[], "receptors").length;
    char half = FIRST_HALF_NAME;
    foreach (ref gene; body.genome.slice()) {
        if (gene.kind == GeneKind.receptorHalf) {
            length += printed(buffer[length .. $], " %c", half).length;
            half += 1;
        }
    }
    hud.row(panel, buffer[0 .. length], WHITE);
    length = printed(buffer[], "enzymes").length;
    foreach (ref gene; body.genome.slice()) {
        if (gene.kind == GeneKind.enzyme) {
            string operation = ENUM_NAMES!Operation[enzymeOf(gene).operation];
            length += printed(buffer[length .. $], " %.*s", cast(int) operation.length, operation.ptr).length;
        }
    }
    hud.row(panel, buffer[0 .. length], WHITE);
}

void surroundings(ref Hud hud, ref const Game game, ref Panel panel, uint slot) {
    char[LINE_CAPACITY] buffer;
    Climate climate = game.world.graph.stateAt(slot).climate.climate();
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
    hud.row(panel, printed(buffer[], "crossing seeds here mutates %.0f%%", cast(double) mutationOddsAt(game, slot).value * 100), WHITE);
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
    const(Organism)* own = &game.organism;
    uint fit = cast(uint) higherOf(floorf((area.h - 3 * pad) / row), 0.0f);
    uint listRows = 0;
    if (fit > BENCH_FIXED_ROWS) {
        listRows = fit - BENCH_FIXED_ROWS;
    }
    uint plants = 0;
    foreach (slot; 0 .. SLOT_COUNT) {
        if (isBreedable(game, slot)) {
            plants += 1;
        }
    }
    uint plantRows = lowerOf(plants, listRows);
    uint geneRows = lowerOf(own.genome.count, listRows);
    uint body = higherOf(higherOf(plantRows, geneRows), 1u);
    Box box = centered(area, inner + 2 * pad, (BENCH_FIXED_ROWS + body) * row + 3 * pad);
    frame(hud, box);
    float x = box.x + pad;
    float y = box.y + pad;
    char[LINE_CAPACITY] buffer;
    MaybeIndex!uint bench = game.world.graph.slotOf(game.machine.node);
    if (bench.exists) {
        float odds = mutationOddsAt(game, bench.value).value;
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
        if (isBreedable(game, slot) && listed < plantRows) {
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
    foreach (shown, ref gene; own.genome.slice()) {
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
    if (isChosenBreedable(game, 0) && isChosenBreedable(game, 1)) {
        cross = Maybe!UiAction.of(acting(&actCross, 0));
    }
    Maybe!UiAction splice;
    if (isChosenBreedable(game, 0) && own.genome.count < MOST_GENES) {
        splice = Maybe!UiAction.of(acting(&actSplice, 0));
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
        geneStrip(hud, line.x + left, line.y, cell, stack.genes.value);
    }
    hud.hotspot(line, acting(&choose, slot));
    if (hud.isUnderCursor(line)) {
        hud.outline(line, hud.scale, GOLD);
    }
}

void buildCollector(ref Hud hud, ref const Game game, Box area) {
    const(Pharma)* own = &pharma(game);
    float pad = hud.padding();
    float row = hud.rowHeight();
    float inner = lowerOf(area.w - 2 * pad, hud.columns(CRAFT_COLUMNS + 16));
    Box box = centered(area, inner + 2 * pad, (GAS_COUNT + 5) * row + 3 * pad);
    frame(hud, box);
    Panel panel = Panel(box.x + pad, box.y + pad, row, inner, GAS_COUNT + 4);
    char[LINE_CAPACITY] buffer;
    heading(hud, panel, "collector");
    hud.row(panel, "fills with the air around it", DIM);
    barRow(hud, panel, "full", own.machineFill.value, GOLD, printed(buffer[], "%.0f%%", cast(double) own.machineFill.value * 100));
    float most = (COLLECTION_RATE * MOST_COLLECTED_SECONDS).value;
    float total = 0;
    foreach (gas; 0 .. GAS_COUNT) {
        float amount = own.machineAir[gas].value;
        total += amount;
        barRow(hud, panel, GAS_NAMES[gas], amount / most, CYAN, printed(buffer[], "%.2f", cast(double) amount));
    }
    float wide = (inner - pad) / 2;
    float y = box.y + pad + (GAS_COUNT + 4) * row;
    Maybe!UiAction breathe;
    if (total > 0) {
        breathe = Maybe!UiAction.of(acting(&actBreathe, 0));
    }
    UiAction closing = {kind: UiKind.close};
    hud.button(Box(box.x + pad, y, wide, row), "breathe it in", breathe);
    hud.button(Box(box.x + 2 * pad + wide, y, wide, row), "close", Maybe!UiAction.of(closing));
}

void actCycleCell(ref Game game, uint cell) {
    cycleCatalogCell(game, cell);
}

void actConjugation(ref Game game, uint index) {
    toggleCatalogConjugation(game, index);
}

void buildCatalog(ref Hud hud, ref const Game game, Box area) {
    const(Compound)* draft = &pharma(game).catalog;
    float pad = hud.padding();
    float row = hud.rowHeight();
    float inner = lowerOf(area.w - 2 * pad, hud.columns(WINDOW_COLUMNS));
    float cell = row * CATALOG_CELL_ROWS;
    Box box = centered(area, inner + 2 * pad, CATALOG_ROWS * row + GRID_SIDE * cell + 3 * pad);
    frame(hud, box);
    float x = box.x + pad;
    float y = box.y + pad;
    char[LINE_CAPACITY] buffer;
    char[CALL_DIGITS] call = callNumber(draft.molecule);
    hud.clippedText(x, y, inner, "catalog: set a shape to find its shelf", GOLD);
    y += row;
    hud.clippedText(x, y, inner, printed(buffer[], "shelf %.*s", cast(int) call.length, call.ptr), CYAN);
    y += row;
    float layer = (inner - (GRID_SIDE - 1) * pad) / GRID_SIDE;
    foreach (cellIndex; 0 .. GRID_CELLS) {
        uint level = cellIndex / (GRID_SIDE * GRID_SIDE);
        uint across = cellIndex % GRID_SIDE;
        uint down = cellIndex / GRID_SIDE % GRID_SIDE;
        float side = layer / GRID_SIDE;
        Box spot = Box(x + level * (layer + pad) + across * side, y + down * cell, side - hud.scale, cell - hud.scale);
        uint digit = digitOf(draft.molecule.fragmentAt(cellIndex));
        hud.button(spot, printed(buffer[], "%u", digit), Maybe!UiAction.of(acting(&actCycleCell, cellIndex)));
    }
    y += GRID_SIDE * cell + pad;
    float half = LN_TWO / clearanceOf(draft.molecule).value;
    hud.clippedText(x, y, inner, printed(buffer[], "%u fragments, leaves the blood by half every %.0fs", fragmentCount(draft.molecule), cast(double) half), WHITE);
    y += row;
    if (hasAssay(game)) {
        hud.clippedText(x, y, inner, bindsOf(DOSE_SIZE, draft.affinity[0 .. draft.receptors], draft.efficacy[0 .. draft.receptors], game.organism.receptors.slice(), buffer[]), DIM);
    } else {
        hud.clippedText(x, y, inner, "an assay kit reads what it would do to you", DIM);
    }
    y += row;
    float wide = (inner - pad) / 2;
    const(char)[] conjugation = "conjugate it";
    if (isConjugated(draft.molecule)) {
        conjugation = "unconjugate it";
    }
    UiAction closing = {kind: UiKind.close};
    hud.button(Box(x, y, wide, row), conjugation, Maybe!UiAction.of(acting(&actConjugation, 0)));
    hud.button(Box(x + wide + pad, y, wide, row), "close", Maybe!UiAction.of(closing));
}

immutable Display DISPLAY =Display(&busy, &target, &stackMake, &station, &surroundings);
