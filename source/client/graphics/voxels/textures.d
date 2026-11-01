module client.graphics.voxels.textures;

import core.stdc.math : fabsf, floorf, sinf;
import core.stdc.stdlib : malloc;
import base.numbers : PI, clamped, higherOf;
import base.splitmix : SplitMix;
import common.material : MATERIAL_COLORS;
import plugins.api.api : Material;

enum uint TEXTURE_SIZE = 16;
enum uint TEXTURE_MIPS = 5;
enum uint TEXTURE_LAYERS = Material.max;
enum uint TEXEL_BYTES = 4;
enum uint COLOR_CHANNELS = 3;
enum ubyte TEXTURE_OPAQUE = 255;
enum ubyte TEXTURE_CLEAR = 0;
enum uint SHADE_FULL = 255;
enum uint BRICK_LONG = 8;
enum uint BRICK_SHORT = 4;
enum uint BOARD_WIDTH = 4;
enum uint FORM_EVERY = 8;
enum uint WEAVE_EVERY = 8;
enum uint BLADES_EVERY = 3;
enum ulong SALT_FINE = 0x9E37;
enum ulong SALT_COARSE = 0x79B9;
enum ulong SALT_PIECE = 0x7F4A;
enum ulong SALT_BLADE = 0x7C15;

enum Pattern : ubyte {
    soil,
    gravel,
    grass,
    stone,
    marble,
    bark,
    leaves,
    planks,
    bricks,
    concrete,
    steel,
    glass,
    water,
    lava,
    wallpaper,
    carpet,
    ceilingTile,
    lightPanel,
    sunlight,
    snow,
}

immutable Pattern[Material.max + 1] PATTERNS = [
    Material.none: Pattern.soil,
    Material.dirt: Pattern.soil,
    Material.sand: Pattern.snow,
    Material.redSand: Pattern.snow,
    Material.silt: Pattern.soil,
    Material.clay: Pattern.soil,
    Material.mud: Pattern.soil,
    Material.sandyLoam: Pattern.soil,
    Material.siltyLoam: Pattern.soil,
    Material.clayLoam: Pattern.soil,
    Material.gravel: Pattern.gravel,
    Material.grass: Pattern.grass,
    Material.lushGrass: Pattern.grass,
    Material.coarseGrass: Pattern.grass,
    Material.tanGrass: Pattern.grass,
    Material.mudGrass: Pattern.grass,
    Material.caveGrass: Pattern.grass,
    Material.snow: Pattern.snow,
    Material.ice: Pattern.water,
    Material.iceSlush: Pattern.snow,
    Material.limestone: Pattern.stone,
    Material.dolomite: Pattern.stone,
    Material.shale: Pattern.stone,
    Material.slate: Pattern.stone,
    Material.sandstone: Pattern.stone,
    Material.redSandstone: Pattern.stone,
    Material.marble: Pattern.marble,
    Material.granite: Pattern.gravel,
    Material.diorite: Pattern.gravel,
    Material.andesite: Pattern.stone,
    Material.gabbro: Pattern.gravel,
    Material.basalt: Pattern.stone,
    Material.olivine: Pattern.gravel,
    Material.water: Pattern.water,
    Material.lava: Pattern.lava,
    Material.oakWood: Pattern.bark,
    Material.oakLeaves: Pattern.leaves,
    Material.birchWood: Pattern.bark,
    Material.birchLeaves: Pattern.leaves,
    Material.spruceWood: Pattern.bark,
    Material.spruceLeaves: Pattern.leaves,
    Material.woodPlanks: Pattern.planks,
    Material.greyBrick: Pattern.bricks,
    Material.whiteBrick: Pattern.bricks,
    Material.concrete: Pattern.concrete,
    Material.steel: Pattern.steel,
    Material.glass: Pattern.glass,
    Material.jungleWood: Pattern.bark,
    Material.jungleLeaves: Pattern.leaves,
    Material.acaciaWood: Pattern.bark,
    Material.acaciaLeaves: Pattern.leaves,
    Material.cherryLeaves: Pattern.leaves,
    Material.mapleLeaves: Pattern.leaves,
    Material.willowLeaves: Pattern.leaves,
    Material.cactus: Pattern.bark,
    Material.wallpaper: Pattern.wallpaper,
    Material.stainedWallpaper: Pattern.wallpaper,
    Material.carpet: Pattern.carpet,
    Material.dampCarpet: Pattern.carpet,
    Material.ceilingTile: Pattern.ceilingTile,
    Material.lightPanel: Pattern.lightPanel,
    Material.redCarpet: Pattern.carpet,
    Material.sunlight: Pattern.sunlight,
    Material.plaster: Pattern.concrete,
    Material.wetConcrete: Pattern.concrete,
];

float noiseAt(uint layer, ulong salt, uint u, uint v) {
    return SplitMix(salt * 0x100000001B3 ^ (cast(ulong) layer << 40) ^ (cast(ulong) u << 20) ^ v).roll();
}

float wobble(uint layer, ulong salt, uint u, uint v, float amount) {
    return 1.0f + amount * (2.0f * noiseAt(layer, salt, u, v) - 1.0f);
}

bool isEdge(uint at, uint every) {
    return at % every == every - 1;
}

// Chunks meet at any quarter turn, and a pattern with a grain would change direction at every chunk border. Masonry and
// boards are laid as a basket weave so a quarter turn leaves them looking the same.
struct Weave {
    uint along;
    uint across;
    uint piece;

    static Weave at(uint u, uint v, uint pieceAcross) {
        uint block = (u / WEAVE_EVERY + v / WEAVE_EVERY) % 2;
        uint x = u % WEAVE_EVERY;
        uint y = v % WEAVE_EVERY;
        uint cell = (u / WEAVE_EVERY) * 4 + (v / WEAVE_EVERY) * 2;
        if (block == 0) {
            return Weave(x, y, cell * 8 + y / pieceAcross);
        } else {
            return Weave(y, x, cell * 8 + x / pieceAcross);
        }
    }
}

float bricksShade(uint layer, uint u, uint v) {
    Weave weave = Weave.at(u, v, BRICK_SHORT);
    if (isEdge(weave.across, BRICK_SHORT) || isEdge(weave.along, BRICK_LONG)) {
        return 0.62f;
    } else {
        return wobble(layer, SALT_PIECE, weave.piece, 0, 0.1f) * wobble(layer, SALT_FINE, u, v, 0.05f);
    }
}

float planksShade(uint layer, uint u, uint v) {
    Weave weave = Weave.at(u, v, BOARD_WIDTH);
    if (isEdge(weave.across, BOARD_WIDTH)) {
        return 0.68f;
    } else {
        return wobble(layer, SALT_PIECE, weave.piece, 0, 0.1f) * wobble(layer, SALT_FINE, weave.piece, weave.along / 2, 0.06f);
    }
}

float barkShade(uint layer, uint u, uint v) {
    uint crack = (u + cast(uint)(noiseAt(layer, SALT_COARSE, v / 3, 0) * 2)) % 4;
    if (crack == 0) {
        return 0.68f;
    } else {
        return wobble(layer, SALT_FINE, u, v, 0.1f);
    }
}

float stoneShade(uint layer, uint u, uint v) {
    float coarse = wobble(layer, SALT_COARSE, u / 4, v / 4, 0.06f);
    return coarse * wobble(layer, SALT_FINE, u / 2, v / 2, 0.06f) * wobble(layer, SALT_FINE, u, v, 0.03f);
}

float marbleShade(uint layer, uint u, uint v) {
    float vein = sinf((u + v + 2 * sinf(v * 2 * PI / TEXTURE_SIZE)) * 2 * PI / TEXTURE_SIZE);
    if (fabsf(vein) < 0.14f) {
        return 0.82f;
    } else {
        return wobble(layer, SALT_FINE, u, v, 0.015f);
    }
}

float concreteShade(uint layer, uint u, uint v) {
    float form = 1.0f;
    if (u == 0 || v == 0) {
        form = 0.9f;
    }
    return form * wobble(layer, SALT_FINE, u, v, 0.045f);
}

float steelShade(uint layer, uint u, uint v) {
    bool isRivet = (u == 2 || u == TEXTURE_SIZE - 3) && (v == 2 || v == TEXTURE_SIZE - 3);
    if (isRivet) {
        return 1.3f;
    } else if (u == 0 || v == 0) {
        return 0.74f;
    } else {
        return wobble(layer, SALT_FINE, u / 2, v, 0.035f);
    }
}

float grassShade(uint layer, uint u, uint v) {
    if (noiseAt(layer, SALT_BLADE, u, v) * BLADES_EVERY < 1) {
        return wobble(layer, SALT_FINE, u, v, 0.2f) * 1.1f;
    } else {
        return wobble(layer, SALT_COARSE, u / 2, v / 2, 0.12f);
    }
}

float wallpaperShade(uint layer, uint u, uint v) {
    float grain = wobble(layer, SALT_FINE, u, v, 0.015f);
    if ((u + v) % WEAVE_EVERY == 0 || (u + TEXTURE_SIZE - v) % WEAVE_EVERY == 0) {
        return 0.9f * grain;
    } else if (u % WEAVE_EVERY == 4 && v % WEAVE_EVERY == 0) {
        return 1.08f * grain;
    } else {
        return grain;
    }
}

float ceilingTileShade(uint layer, uint u, uint v) {
    if (u == 0 || v == 0) {
        return 0.68f;
    } else if (noiseAt(layer, SALT_BLADE, u, v) < 0.14f) {
        return 0.88f;
    } else {
        return wobble(layer, SALT_FINE, u, v, 0.015f);
    }
}

float lightPanelShade(uint u, uint v) {
    if (u == 0 || v == 0 || u == TEXTURE_SIZE - 1 || v == TEXTURE_SIZE - 1) {
        return 0.78f;
    } else {
        return 1.0f;
    }
}

float lavaShade(uint layer, uint u, uint v) {
    float crust = noiseAt(layer, SALT_COARSE, u / 3, v / 3);
    if (crust < 0.3f) {
        return 0.55f * wobble(layer, SALT_FINE, u, v, 0.12f);
    } else {
        return 1.1f * wobble(layer, SALT_FINE, u, v, 0.08f);
    }
}

float waterShade(uint layer, uint u, uint v) {
    float ripple = sinf((u + 2 * sinf(v * 2 * PI / TEXTURE_SIZE)) * 4 * PI / TEXTURE_SIZE);
    return 1.0f + 0.05f * ripple;
}

float shadeOf(uint layer, Pattern pattern, uint u, uint v) {
    final switch (pattern) {
        case Pattern.soil:
            return wobble(layer, SALT_COARSE, u / 2, v / 2, 0.08f) * wobble(layer, SALT_FINE, u, v, 0.05f);
        case Pattern.gravel:
            return wobble(layer, SALT_COARSE, u / 2, v / 2, 0.2f);
        case Pattern.snow:
            return wobble(layer, SALT_FINE, u, v, 0.03f);
        case Pattern.grass:
            return grassShade(layer, u, v);
        case Pattern.stone:
            return stoneShade(layer, u, v);
        case Pattern.marble:
            return marbleShade(layer, u, v);
        case Pattern.bark:
            return barkShade(layer, u, v);
        case Pattern.leaves:
            return wobble(layer, SALT_COARSE, u / 2, v / 2, 0.24f);
        case Pattern.planks:
            return planksShade(layer, u, v);
        case Pattern.bricks:
            return bricksShade(layer, u, v);
        case Pattern.concrete:
            return concreteShade(layer, u, v);
        case Pattern.steel:
            return steelShade(layer, u, v);
        case Pattern.glass:
        case Pattern.sunlight:
            return 1.0f;
        case Pattern.water:
            return waterShade(layer, u, v);
        case Pattern.lava:
            return lavaShade(layer, u, v);
        case Pattern.wallpaper:
            return wallpaperShade(layer, u, v);
        case Pattern.carpet:
            return wobble(layer, SALT_FINE, u, v, 0.09f);
        case Pattern.ceilingTile:
            return ceilingTileShade(layer, u, v);
        case Pattern.lightPanel:
            return lightPanelShade(u, v);
    }
}

bool isGlassPane(uint u, uint v) {
    return u > 0 && v > 0 && u < TEXTURE_SIZE - 1 && v < TEXTURE_SIZE - 1;
}

size_t mipBytes(uint mip) {
    size_t side = TEXTURE_SIZE >> mip;
    return side * side * TEXEL_BYTES * TEXTURE_LAYERS;
}

size_t mipOffset(uint mip) {
    size_t offset = 0;
    foreach (level; 0 .. mip) {
        offset += mipBytes(level);
    }
    return offset;
}

size_t textureBytes() {
    return mipOffset(TEXTURE_MIPS);
}

void fillFirstMip(ubyte[] pixels) {
    size_t at = 0;
    foreach (layer; 0 .. TEXTURE_LAYERS) {
        Material material = cast(Material)(layer + 1);
        Pattern pattern = PATTERNS[material];
        foreach (v; 0 .. TEXTURE_SIZE) {
            foreach (u; 0 .. TEXTURE_SIZE) {
                float shade = shadeOf(layer, pattern, u, v);
                foreach (channel; 0 .. COLOR_CHANNELS) {
                    pixels[at + channel] = cast(ubyte) clamped(floorf(MATERIAL_COLORS[material][channel] * shade + 0.5f), 0.0f, cast(float) SHADE_FULL);
                }
                pixels[at + COLOR_CHANNELS] = TEXTURE_OPAQUE;
                if (pattern == Pattern.glass && isGlassPane(u, v)) {
                    pixels[at + COLOR_CHANNELS] = TEXTURE_CLEAR;
                }
                at += TEXEL_BYTES;
            }
        }
    }
}

// Alpha takes the most of its four texels and color averages only the opaque ones, so distant glass closes into a solid
// pane instead of its frame fading out and leaving a hole.
void downsample(const(ubyte)[] from, ubyte[] to, uint side) {
    foreach (layer; 0 .. TEXTURE_LAYERS) {
        foreach (y; 0 .. side / 2) {
            foreach (x; 0 .. side / 2) {
                uint[COLOR_CHANNELS] sum = 0;
                uint opaque = 0;
                ubyte alpha = TEXTURE_CLEAR;
                foreach (corner; 0 .. 4) {
                    size_t source = (layer * side * side + (y * 2 + corner / 2) * side + x * 2 + corner % 2) * TEXEL_BYTES;
                    if (from[source + COLOR_CHANNELS] != TEXTURE_CLEAR) {
                        foreach (channel; 0 .. COLOR_CHANNELS) {
                            sum[channel] += from[source + channel];
                        }
                        opaque += 1;
                    }
                    alpha = higherOf(alpha, from[source + COLOR_CHANNELS]);
                }
                size_t target = (layer * (side / 2) * (side / 2) + y * (side / 2) + x) * TEXEL_BYTES;
                foreach (channel; 0 .. COLOR_CHANNELS) {
                    to[target + channel] = cast(ubyte)(sum[channel] / higherOf(opaque, 1u));
                }
                to[target + COLOR_CHANNELS] = alpha;
            }
        }
    }
}

ubyte[] makeTexturePixels() {
    ubyte[] pixels = (cast(ubyte*) malloc(textureBytes()))[0 .. textureBytes()];
    fillFirstMip(pixels);
    foreach (mip; 1 .. TEXTURE_MIPS) {
        downsample(pixels[mipOffset(mip - 1) .. mipOffset(mip)], pixels[mipOffset(mip) .. mipOffset(mip) + mipBytes(mip)], TEXTURE_SIZE >> (mip - 1));
    }
    return pixels;
}
