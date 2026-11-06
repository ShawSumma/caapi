module common.perception;

import core.stdc.math : expf;
import base.numbers : clamped, higherOf, lowerOf;
import base.units : Angle, Length, Ratio, Time;
import common.color : ColorTurn, TURN_PLANES;
import common.material : FAMILY_SETS, HIDDEN_FAMILY_COUNT, MaterialSet, PLAIN_SOLID, joined, within, without;
import common.settings : CharacterConfig;

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

static assert(Channel.revealTide - Channel.revealMist + 1 == HIDDEN_FAMILY_COUNT);

static assert(Channel.colorTurn5 - Channel.colorTurn0 + 1 == TURN_PLANES);

enum uint CHANNEL_COUNT = Channel.max + 1;

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
    MaterialSet visible = PLAIN_SOLID;
}

struct Reveal {
    MaterialSet revealed;
    MaterialSet touchable;

    void update(ref const Perception perception) {
        foreach (index; 0 .. HIDDEN_FAMILY_COUNT) {
            float level = perception.level[Channel.revealMist + index].value;
            if (level > REVEAL_ON_LEVEL) {
                revealed = revealed.joined(FAMILY_SETS[index]);
            } else if (level < REVEAL_OFF_LEVEL) {
                revealed = revealed.without(FAMILY_SETS[index]);
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

immutable string[3] SIGNAL_NAMES = ["mist", "sway", "lift"];

immutable SignalDrive[7] SIGNAL_DRIVES = [
    SignalDrive(0, Channel.revealMist, 2.0f),
    SignalDrive(0, Channel.colorTurn0, 1.2f),
    SignalDrive(1, Channel.warp, 0.15f),
    SignalDrive(1, Channel.fieldOfView, 0.6f),
    SignalDrive(1, Channel.afterimage, 1.0f),
    SignalDrive(2, Channel.gravity, -0.8f),
    SignalDrive(2, Channel.jumpHeight, 0.8f),
];

Perception felt(Perception base, const(Ratio)[] signals) {
    Perception made = base;
    foreach (drive; SIGNAL_DRIVES) {
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
        PLAIN_SOLID.joined(revealed),
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
