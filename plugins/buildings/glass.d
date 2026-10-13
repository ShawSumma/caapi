module plugins.buildings.glass;

import plugins.api.api : Box, Material, Rhythm;
import plugins.buildings.building : Bound, Lots, Palette, Part, PartJoin, Parts, STORY, Spec, Tier, crown, enter, footprint, helipad, makeParts, masts, middle, narrowing, pick, roof, setbacks, shell, strips, tiers, walls;
import plugins.turtle.turtle : boxOf;

enum int[2] STORIES = [12, 38];
enum int SETBACKS = 1;
enum Material ROOF = Material.concrete;
enum Rhythm SPANDRELS = Rhythm(STORY, STORY - 1, 1);
enum int MULLION_SPACING = 3;
enum int PENTHOUSE_SETBACK = 2;
enum int LEAST_WIDTH = 3;
enum int ANTENNA = 6;

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
    Box roofBox = footprint(part, tier.shrink, false, tier.high, tier.high);
    int inset = narrowing([roofBox.low[0], roofBox.high[0]], [roofBox.low[1], roofBox.high[1]], PENTHOUSE_SETBACK, LEAST_WIDTH);
    Tier cap = Tier(tier.high + 1, tier.high + STORY, tier.shrink + inset, false);
    Part closed = part;
    closed.kinds = [Bound.lot, Bound.lot, Bound.lot, Bound.lot];
    closed.joins = PartJoin.init;
    shell(closed, Palette(palette.band, Material.none, palette.floor), cap);
    return cap;
}

void antenna(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink, false, tier.high, tier.high);
    int x = middle(roofBox.low[0], roofBox.high[0]);
    int y = middle(roofBox.low[1], roofBox.high[1]);
    part.tower.paint(palette.trim, boxOf([x, x], [y, y], [tier.high + 1, tier.high + ANTENNA]));
}

void build(ref const Lots lots, Spec spec) {
    Parts parts;
    makeParts(parts, lots, spec);
    int chosen = setbacks(parts, SETBACKS);
    foreach (ref part; parts.slice()) {
        foreach (tier; tiers(part, spec, chosen).slice()) {
            curtain(part, spec.palette, shell(part, spec.palette, tier), tier);
            if (tier.isRoofed) {
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
