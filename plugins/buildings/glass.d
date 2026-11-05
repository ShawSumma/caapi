module plugins.buildings.glass;

import plugins.api.api : Box, Material, Rhythm, Span;
import plugins.buildings.building : ANTENNA, Bound, Lots, Palette, Part, PartJoin, Parts, STORY, Spec, Split, Tier, crown, enter, footprint, helipad, makeParts, masts, middle, narrowing, pick, roof, setbacks, shell, strips, tiers, walls, xSpan, ySpan;
import plugins.turtle.turtle : boxOf;

enum Span STORIES = Span(12, 38);
enum int SETBACKS = 1;
enum Material ROOF = Material.concrete;
enum Rhythm SPANDRELS = Rhythm(STORY, STORY - 1, 1);
enum int MULLION_SPACING = 3;
enum int PENTHOUSE_SETBACK = 2;
enum int LEAST_WIDTH = 3;

immutable Palette[4] PALETTES = [
    Palette(Material.glass, Material.steel, Material.concrete, Material.concrete),
    Palette(Material.glass, Material.basalt, Material.concrete, Material.slate),
    Palette(Material.glass, Material.steel, Material.marble, Material.steel),
    Palette(Material.glass, Material.gabbro, Material.concrete, Material.gabbro),
];

void curtain(ref const Part part, Palette palette, Box box, Tier tier) {
    foreach (face; walls(part, box, tier).slice()) {
        part.tower.paint(palette.band, face, SPANDRELS);
        foreach (mullion; strips(face, MULLION_SPACING).slice()) {
            part.tower.paint(palette.trim, mullion);
        }
    }
}

Tier penthouse(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink, Split.above, tier.high, tier.high);
    int inset = narrowing(xSpan(roofBox), ySpan(roofBox), PENTHOUSE_SETBACK, LEAST_WIDTH);
    Tier cap = Tier(tier.high + 1, tier.high + STORY, tier.shrink + inset, Split.above);
    Part closed = part;
    closed.kinds = [Bound.lot, Bound.lot, Bound.lot, Bound.lot];
    closed.joins = PartJoin.init;
    shell(closed, Palette(palette.band, Material.none, palette.floor), cap);
    return cap;
}

void antenna(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink, Split.above, tier.high, tier.high);
    int x = middle(xSpan(roofBox));
    int y = middle(ySpan(roofBox));
    part.tower.paint(palette.trim, boxOf(Span(x, x), Span(y, y), Span(tier.high + 1, tier.high + ANTENNA)));
}

void build(ref const Lots lots, Spec spec) {
    Parts parts;
    makeParts(parts, lots, spec);
    int chosen = setbacks(parts, SETBACKS);
    foreach (ref part; parts.slice()) {
        foreach (tier; tiers(part, spec, chosen).slice()) {
            curtain(part, spec.palette, shell(part, spec.palette, tier), tier);
            if (tier.isRoofed()) {
                roof(part, spec.palette, ROOF, tier);
            }
        }
        part.stand = penthouse(part, spec.palette, part.top);
    }
    enter(parts, spec);
    uint choice = pick(parts, 3);
    if (choice == 0) {
        crown(parts, spec.palette, &antenna);
    } else if (choice == 1) {
        crown(parts, spec.palette, &masts);
    } else {
        crown(parts, spec.palette, &helipad);
    }
}
