module common.perception;

import core.stdc.math : expf;
import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.numbers : clamped, higherOf, lowerOf;
import base.stdio : printed;
import base.units : Angle, Length, Ratio, Time;
import common.color : ColorTurn, TURN_PLANES;
import common.content.declarations : declare;
import common.content.graph : ContentGraph, PROBLEM_CAPACITY, targetOf;
import common.material : MaterialSet, families, joined, plainSolid, within, without;
import common.settings : CharacterConfig;
import plugins.api.binding : kebabOf;
import plugins.api.content : ContentRef, Holder;

enum Length EYE_BACK_PER_LEVEL = Length(1.0f);
enum float MOST_WARP_STRENGTH = 0.15f;
enum Time MOST_AFTERIMAGE_TIME = Time(0.2f);
enum float MOST_BAND_GAIN = 4;
enum uint BAND_COUNT = 4;
enum uint FINE_BANDS = 2;
enum float REVEAL_ON_LEVEL = 0.6f;
enum float REVEAL_OFF_LEVEL = 0.4f;

enum Channel : ubyte {
    walkSpeed,
    gravity,
    jumpHeight,
    fieldOfView,
    fog,
    eyeOffset,
    warp,
    colorTurn0,
    colorTurn1,
    colorTurn2,
    colorTurn3,
    colorTurn4,
    colorTurn5,
    revealMist,
    revealEmber,
    revealTide,
    afterimage,
    fineDetail,
    coarseDetail,
}

static assert(Channel.colorTurn5 - Channel.colorTurn0 + 1 == TURN_PLANES);

enum uint CHANNEL_COUNT = Channel.max + 1;

string[CHANNEL_COUNT] channelNames() {
    string[CHANNEL_COUNT] names;
    static foreach (index, member; __traits(allMembers, Channel)) {
        names[index] = "engine:" ~ kebabOf!member;
    }
    return names;
}

immutable string[CHANNEL_COUNT] CHANNEL_NAMES = channelNames();

struct Perception {
    Ratio[CHANNEL_COUNT] level;
}

struct ViewEffects {
    Ratio fieldTangentScale = Ratio(1);
    Ratio fogShare = Ratio(1);
    Length eyeBack;
    Ratio warpStrength;
    Time warpSeconds;
    Time afterimageTime;
    Ratio[BAND_COUNT] bandGains = Ratio(1);
    ColorTurn colorTurn;
    MaterialSet visible;
}

struct Reveal {
    MaterialSet revealed;
    MaterialSet touchable;

    void update(ref const Perception perception) {
        foreach (ref family; families.slice()) {
            float level = perception.level[family.channel].value;
            if (level > REVEAL_ON_LEVEL) {
                revealed = revealed.joined(family.members);
            } else if (level < REVEAL_OFF_LEVEL) {
                revealed = revealed.without(family.members);
            }
        }
        touchable = touchable.within(revealed);
    }
}

struct SignalDrive {
    uint signal;
    Channel channel;
    float gain;
}

struct NamedPreset {
    const(char)[] name;
    Perception perception;
}

immutable string[3] SIGNAL_NAMES = ["mist", "sway", "lift"];

enum string PLAIN_PRESET = "plain";
enum string PRESET_KIND = "perception-preset";
enum string DRIVE_KIND = "signal-drive";
enum string PERCEPTION_DECLARATIONS = "perception.decl";

__gshared Array!NamedPreset presets;
__gshared Array!SignalDrive drives;

void declarePerception(ref ContentGraph graph) {
    declare(graph, import(PERCEPTION_DECLARATIONS), PERCEPTION_DECLARATIONS);
}

Maybe!Channel channelNamed(const(char)[] name) {
    uint index = 0;
    while (index < CHANNEL_COUNT && CHANNEL_NAMES[index] != name) {
        index += 1;
    }
    if (index < CHANNEL_COUNT) {
        return Maybe!Channel.of(cast(Channel) index);
    } else {
        return Maybe!Channel.init;
    }
}

uint signalNamed(const(char)[] name) {
    uint index = 0;
    while (index < SIGNAL_NAMES.length && SIGNAL_NAMES[index] != name) {
        index += 1;
    }
    return index;
}

void reportUnread(ref ContentGraph graph, uint owner, const(char)[] channel) {
    char[PROBLEM_CAPACITY] buffer;
    graph.report(owner, printed(buffer[], "names the channel '%.*s', which no engine system reads", cast(int) channel.length, channel.ptr));
}

void buildPerception(ref ContentGraph graph) {
    presets.clear();
    drives.clear();
    presets.append(NamedPreset(PLAIN_PRESET, Perception.init));
    foreach (node; 0 .. cast(uint) graph.nodes.length) {
        if (graph.isKind(node, PRESET_KIND)) {
            Perception made;
            foreach (edge; graph.edgesFrom(node)) {
                Maybe!Channel channel = channelNamed(graph.nameOf(graph.edges.ptr[edge].to));
                if (!channel.exists) {
                    reportUnread(graph, graph.edges.ptr[edge].owner, graph.nameOf(graph.edges.ptr[edge].to));
                } else {
                    made = made.leveled(channel.value, Ratio(graph.number(ContentRef(edge, Holder.edge), "level")));
                }
            }
            presets.append(NamedPreset(graph.nameOf(node), made));
        } else if (graph.isKind(node, DRIVE_KIND)) {
            ContentRef at = ContentRef(node, Holder.node);
            const(char)[] target = graph.nameOf(targetOf(graph, node, "drives").value);
            Maybe!Channel channel = channelNamed(target);
            if (!channel.exists) {
                reportUnread(graph, graph.nodes.ptr[node].owner, target);
            } else {
                drives.append(SignalDrive(signalNamed(graph.textAt(at, "signal")), channel.value, graph.number(at, "gain")));
            }
        }
    }
}

MaybeIndex!uint presetNamed(const(char)[] name) {
    uint index = 0;
    while (index < presets.length && presets.ptr[index].name != name) {
        index += 1;
    }
    if (index < presets.length) {
        return MaybeIndex!uint.of(index);
    } else {
        return MaybeIndex!uint.init;
    }
}

Perception felt(Perception base, const(Ratio)[] signals) {
    Perception made = base;
    foreach (drive; drives.slice()) {
        made.level[drive.channel] = made.level[drive.channel] + signals[drive.signal] * drive.gain;
    }
    return made;
}

Perception leveled(Perception perception, Channel channel, Ratio level) {
    Perception made = perception;
    made.level[channel] = level;
    return made;
}

Ratio scaleOf(ref const Perception perception, Channel channel) {
    return Ratio(expf(perception.level[channel].value));
}

CharacterConfig effectiveFor(ref const CharacterConfig base, ref const Perception perception) {
    CharacterConfig effective = base;
    effective.walkSpeed = base.walkSpeed * perception.scaleOf(Channel.walkSpeed);
    effective.gravity = base.gravity * perception.scaleOf(Channel.gravity);
    effective.jumpHeight = base.jumpHeight * perception.scaleOf(Channel.jumpHeight);
    return effective;
}

ViewEffects viewOf(ref const Perception perception, Time time, MaterialSet revealed, Ratio comfort) {
    return ViewEffects(
        perception.scaleOf(Channel.fieldOfView),
        Ratio(lowerOf(1.0f, 1.0f / perception.scaleOf(Channel.fog).value)),
        EYE_BACK_PER_LEVEL * higherOf(perception.level[Channel.eyeOffset].value, 0.0f),
        Ratio(clamped(perception.level[Channel.warp].value, 0.0f, MOST_WARP_STRENGTH * comfort.value)),
        time,
        MOST_AFTERIMAGE_TIME * (clamped(perception.level[Channel.afterimage].value, 0.0f, 1.0f) * comfort.value),
        perception.bandGainsOf(),
        perception.colorTurnOf(),
        plainSolid.joined(revealed),
    );
}

Ratio[BAND_COUNT] bandGainsOf(ref const Perception perception) {
    Ratio[BAND_COUNT] gains;
    foreach (band; 0 .. BAND_COUNT) {
        Channel channel = Channel.coarseDetail;
        if (band < FINE_BANDS) {
            channel = Channel.fineDetail;
        }
        gains[band] = Ratio(lowerOf(perception.scaleOf(channel).value, MOST_BAND_GAIN));
    }
    return gains;
}

ColorTurn colorTurnOf(ref const Perception perception) {
    ColorTurn turn;
    foreach (index; 0 .. TURN_PLANES) {
        turn.angles[index] = Angle(perception.level[Channel.colorTurn0 + index].value);
    }
    return turn;
}
