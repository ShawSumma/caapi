module plugins.base.forms;

import core.stdc.stdlib : abs;
import plugins.api.api : Form, Part;

enum int CANOPY_RADIUS = 2;
enum int SPRUCE_LOWEST_LEAVES = 2;
enum double RAGGED_FROM = 0.55;
enum int RAGGED_EVERY = 3;
enum int RAG_ACROSS = 7;
enum int RAG_ALONG = 13;
enum int RAG_LEVEL = 5;
enum double ROUND_DROP = 1;
enum double ROUND_ACROSS = 2.6;
enum double ROUND_TALL = 2.1;
enum double BROAD_DROP = 1.5;
enum double BROAD_ACROSS = 3.5;
enum double BROAD_TALL = 2.6;
enum double TALL_DROP = 1;
enum double TALL_ACROSS = 2.4;
enum double TALL_TALL = 1.8;
enum double WEEPING_DROP = 0.5;
enum double WEEPING_ACROSS = 2.6;
enum double WEEPING_TALL = 1.6;
enum double CONE_STEP = 0.7;
enum double CONE_TIP = 0.6;
enum double CONE_WIDEST = 6.25;
enum int CAP_CROWN = 4;
enum int CAP_SPREAD = 9;
enum int CAP_RIM = 10;
enum int BLOOM_SPREAD = 5;
enum int BLOOM_CUP = 2;
enum int BLOOM_TIPS = 4;

struct NamedForm {
    string name;
    Form form;
}

immutable NamedForm[11] FORMS = [
    NamedForm("round", Form(&roundAt, 1)),
    NamedForm("cone", Form(&coneAt, 0)),
    NamedForm("broad", Form(&broadAt, 1)),
    NamedForm("weeping", Form(&weepingAt, 0)),
    NamedForm("tall", Form(&tallAt, 0)),
    NamedForm("flat", Form(&flatAt, 1)),
    NamedForm("bush", Form(&bushAt, 1)),
    NamedForm("bare", Form(&bareAt, 0)),
    NamedForm("column", Form(&columnAt, -1)),
    NamedForm("cap", Form(&capAt, 1)),
    NamedForm("bloom", Form(&bloomAt, 1)),
];

Part grownAs(bool wood, bool leaf) {
    if (wood) {
        return Part.wood;
    } else if (leaf) {
        return Part.leaves;
    } else {
        return Part.none;
    }
}

bool isInTrunk(int trunk, int level, int i, int j) {
    return i == 0 && j == 0 && level < trunk;
}

int spreadOf(int i, int j) {
    int across = abs(i);
    int along = abs(j);
    if (across > along) {
        return across;
    } else {
        return along;
    }
}

int spanOf(int i, int j) {
    return abs(i) + abs(j);
}

int squaredOf(int i, int j) {
    return i * i + j * j;
}

bool isRagged(int i, int j, int level) {
    int mark = (i * RAG_ACROSS + j * RAG_ALONG + level * RAG_LEVEL) % RAGGED_EVERY;
    return mark == 0;
}

bool isInBlob(int i, int j, int level, double centre, double across, double tall) {
    double dz = level - centre;
    double inside = squaredOf(i, j) / (across * across) + dz * dz / (tall * tall);
    return inside <= 1 && !(inside > RAGGED_FROM && isRagged(i, j, level));
}

bool isConeLeaf(int trunk, int level, int squared) {
    int below = trunk - level;
    if (level > trunk || level < SPRUCE_LOWEST_LEAVES) {
        return false;
    } else if (below % 2 == 0) {
        double radius = CONE_STEP * below + CONE_TIP;
        return squared <= radius * radius && squared <= CONE_WIDEST;
    } else {
        double radius = CONE_STEP * below;
        return squared <= radius * radius && squared <= CONE_WIDEST;
    }
}

bool isWeepingLeaf(int trunk, int level, int i, int j) {
    if (level >= trunk - 1) {
        return isInBlob(i, j, level, trunk - WEEPING_DROP, WEEPING_ACROSS, WEEPING_TALL);
    } else {
        return level >= 1 && spreadOf(i, j) == CANOPY_RADIUS && ((i + j) & 1) == 0;
    }
}

bool isTallLeaf(int trunk, int level, int i, int j) {
    if (level == trunk / 2) {
        return squaredOf(i, j) == 1;
    } else {
        return isInBlob(i, j, level, trunk - TALL_DROP, TALL_ACROSS, TALL_TALL);
    }
}

bool isCapLeaf(int trunk, int level, int squared) {
    if (level == trunk + 1) {
        return squared <= CAP_CROWN;
    } else if (level == trunk) {
        return squared <= CAP_SPREAD;
    } else if (level == trunk - 1) {
        return squared > CAP_CROWN + 1 && squared <= CAP_RIM;
    } else {
        return false;
    }
}

bool isBloomPetal(int trunk, int level, int squared) {
    if (level == trunk) {
        return squared > 0 && squared <= BLOOM_SPREAD;
    } else if (level == trunk - 1) {
        return squared > 0 && squared <= BLOOM_CUP;
    } else if (level == trunk + 1) {
        return squared == BLOOM_TIPS;
    } else {
        return false;
    }
}

Part roundAt(int trunk, int level, int i, int j) {
    return grownAs(isInTrunk(trunk, level, i, j), isInBlob(i, j, level, trunk - ROUND_DROP, ROUND_ACROSS, ROUND_TALL));
}

Part coneAt(int trunk, int level, int i, int j) {
    return grownAs(isInTrunk(trunk, level, i, j), isConeLeaf(trunk, level, squaredOf(i, j)));
}

Part broadAt(int trunk, int level, int i, int j) {
    return grownAs(isInTrunk(trunk, level, i, j), isInBlob(i, j, level, trunk - BROAD_DROP, BROAD_ACROSS, BROAD_TALL));
}

Part weepingAt(int trunk, int level, int i, int j) {
    return grownAs(isInTrunk(trunk, level, i, j), isWeepingLeaf(trunk, level, i, j));
}

Part tallAt(int trunk, int level, int i, int j) {
    return grownAs(isInTrunk(trunk, level, i, j), isTallLeaf(trunk, level, i, j));
}

Part flatAt(int trunk, int level, int i, int j) {
    bool wood = isInTrunk(trunk, level, i, j) || (level == trunk - 1 && i == 1 && j == 0) || (level == trunk && i == 1 && j == 1);
    int squared = squaredOf(i, j);
    return grownAs(wood, (level == trunk && squared <= 10) || (level == trunk + 1 && squared <= 4));
}

Part bushAt(int trunk, int level, int i, int j) {
    return grownAs(isInTrunk(trunk, level, i, j), (level == 0 && spanOf(i, j) <= 1) || (level == 1 && squaredOf(i, j) <= 2));
}

Part bareAt(int trunk, int level, int i, int j) {
    return grownAs(isInTrunk(trunk, level, i, j) || (level == trunk - 2 && i == 0 && j == 1) || (level == trunk - 1 && i == -1 && j == 0) || (level == trunk && i == 1 && j == 0), false);
}

Part columnAt(int trunk, int level, int i, int j) {
    return grownAs(isInTrunk(trunk, level, i, j) || (i == 1 && j == 0 && level >= 1 && level <= 2 && level < trunk - 1) || (i == -1 && j == 0 && level >= 2 && level <= 3 && level < trunk - 1), false);
}

Part capAt(int trunk, int level, int i, int j) {
    return grownAs(isInTrunk(trunk, level, i, j), isCapLeaf(trunk, level, squaredOf(i, j)));
}

Part bloomAt(int trunk, int level, int i, int j) {
    if (isInTrunk(trunk, level, i, j)) {
        return Part.wood;
    } else if (i == 0 && j == 0 && (level == trunk || level == trunk + 1)) {
        return Part.heart;
    } else {
        return grownAs(false, isBloomPetal(trunk, level, squaredOf(i, j)));
    }
}
