module plugins.buildings.civic;

import core.stdc.math : floor, sqrt;
import plugins.api.api : Box, Material, Span;
import plugins.buildings.building : Bound, Lots, Palette, Part, Parts, SIDES, STORY, Spec, Split, Tier, Traits, along, crown, enter, faceOf, footprint, makeParts, masonry, materials, middle, movedOut, narrowestOf, pick, pyramid, roof, setbacks, shell, strips, tiers, withAlong, xSpan, ySpan;
import plugins.turtle.turtle : boxOf, floorDiv;

enum int SETBACKS = 1;
enum int COLUMN_SPACING = 3;

void arcade(ref const Part part, Palette palette) {
    Box box = footprint(part, 0, Split.below, 1, STORY - 1);
    foreach (side; SIDES) {
        if (part.kinds[side] == Bound.street) {
            Box face = faceOf(box, side);
            part.tower.paint(Material.none, face);
            foreach (column; strips(face, COLUMN_SPACING).slice()) {
                part.tower.paint(palette.trim, column);
            }
            Box behind = movedOut(face, side, -1);
            Span run = along(behind, side);
            part.tower.paint(materials.window, withAlong(behind, side, Span(run.low + 1, run.high - 1)));
        }
    }
}

void dome(ref const Part part, Palette palette, Tier tier) {
    Box roofBox = footprint(part, tier.shrink + 1, Split.above, tier.high, tier.high);
    int reach = floorDiv(narrowestOf(roofBox) - 1, 2);
    int x = middle(xSpan(roofBox));
    int y = middle(ySpan(roofBox));
    foreach (level; 0 .. reach + 1) {
        int spread = cast(int) floor(sqrt(cast(double)(reach * reach - level * level)) + 0.5);
        int z = tier.high + level + 1;
        part.tower.paint(palette.roof, boxOf(Span(x - spread, x + spread), Span(y - spread, y + spread), Span(z, z)));
    }
}

void build(ref const Lots lots, Spec spec, ref const Traits traits) {
    Parts parts;
    makeParts(parts, lots, spec);
    int chosen = setbacks(parts, SETBACKS);
    foreach (ref part; parts.slice()) {
        foreach (tier; tiers(part, spec, chosen).slice()) {
            masonry(part, spec.palette, shell(part, spec.palette, tier), tier);
            if (tier.isRoofed()) {
                roof(part, spec.palette, traits.roof, tier);
            }
        }
        arcade(part, spec.palette);
    }
    enter(parts, spec);
    uint choice = pick(parts, 3);
    if (choice < 2) {
        crown(parts, spec.palette, &dome);
    } else {
        crown(parts, spec.palette, &pyramid);
    }
}
