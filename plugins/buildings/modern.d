module plugins.buildings.modern;

import plugins.api.api : Box, Material, Rhythm, Span;
import plugins.buildings.building : Bound, FLOORS, Lots, Palette, Part, Parts, SIDES, STORY, Spec, Split, Tier, WINDOW_ROWS, along, banded, crown, enter, faceOf, footprint, helipad, isEmpty, makeParts, masts, middle, movedOut, pick, roof, setbacks, shell, storefront, tiers, width, withAlong, xSpan, ySpan;
import plugins.turtle.turtle : boxOf, higherOf;

enum Span STORIES = Span(6, 20);
enum int SETBACKS = 1;
enum Material ROOF = Material.concrete;
enum Rhythm RAILS = Rhythm(STORY, 1, 1);
enum int LEAST_GARDEN = 5;

immutable Palette[4] PALETTES = [
    Palette(Material.concrete, Material.steel, Material.concrete),
    Palette(Material.whiteBrick, Material.glass, Material.marble),
    Palette(Material.diorite, Material.steel, Material.concrete),
    Palette(Material.gabbro, Material.glass, Material.concrete),
];

void balconied(ref const Part part, Palette palette, Box box, Tier tier) {
    banded(part, box, tier, WINDOW_ROWS);
    int low = higherOf(tier.low, STORY);
    if (low < tier.high) {
        foreach (side; SIDES) {
            if (part.kinds[side] == Bound.street) {
                Box slab = movedOut(faceOf(box, side), side, 1);
                Span run = along(slab, side);
                slab = withAlong(slab, side, Span(run.low + 1, run.high - 1));
                slab.low[2] = low;
                slab.high[2] = tier.high - 1;
                part.tower.paint(palette.floor, slab, FLOORS);
                part.tower.paint(palette.trim, slab, RAILS);
            }
        }
    }
}

void garden(ref const Part part, Tier tier) {
    Box lawn = footprint(part, tier.shrink + 1, Split.above, tier.high, tier.high);
    if (!isEmpty(lawn)) {
        part.tower.paint(Material.grass, lawn);
        if (width(xSpan(lawn)) >= LEAST_GARDEN && width(ySpan(lawn)) >= LEAST_GARDEN) {
            int x = middle(xSpan(lawn));
            int y = middle(ySpan(lawn));
            int z = tier.high;
            part.tower.paint(Material.oakLeaves, boxOf(Span(x - 1, x + 1), Span(y - 1, y + 1), Span(z + 3, z + 4)));
            part.tower.paint(Material.oakLeaves, boxOf(Span(x, x), Span(y, y), Span(z + 5, z + 5)));
            part.tower.paint(Material.oakWood, boxOf(Span(x, x), Span(y, y), Span(z + 1, z + 3)));
        }
    }
}

void build(ref const Lots lots, Spec spec) {
    Parts parts;
    makeParts(parts, lots, spec);
    int chosen = setbacks(parts, SETBACKS);
    foreach (ref part; parts.slice()) {
        foreach (tier; tiers(part, spec, chosen).slice()) {
            balconied(part, spec.palette, shell(part, spec.palette, tier), tier);
            if (tier.isRoofed()) {
                roof(part, spec.palette, ROOF, tier);
            }
        }
        storefront(part);
        garden(part, part.top);
    }
    enter(parts, spec);
    uint choice = pick(parts, 3);
    if (choice == 0) {
        crown(parts, spec.palette, &helipad);
    } else if (choice == 1) {
        crown(parts, spec.palette, &masts);
    }
}
