module plugins.pharmacology.drives;

import base.array : Array;
import base.maybe : Maybe, MaybeIndex;
import base.units : Ratio;
import common.content.graph : ContentGraph, targetOf;
import common.perception : Perception, Sense, leveled, levelOf, reportUnread, senseNamed;
import plugins.api.content : ContentRef, Holder;
import plugins.pharmacology.signaling : SIGNAL_COUNT;

enum string DRIVE_KIND = "signal-drive";

immutable string[SIGNAL_COUNT] SIGNAL_NAMES = ["mist", "sway", "lift"];

struct SignalDrive {
    uint signal;
    MaybeIndex!uint also;
    Sense sense;
    float gain;

    Ratio heard(const(Ratio)[] signals) const {
        if (also.exists && signals[also.value] < signals[signal]) {
            return signals[also.value];
        } else {
            return signals[signal];
        }
    }
}

__gshared Array!SignalDrive drives;

uint signalNamed(const(char)[] name) {
    uint index = 0;
    while (index < SIGNAL_NAMES.length && SIGNAL_NAMES[index] != name) {
        index += 1;
    }
    return index;
}

MaybeIndex!uint secondSignal(const(char)[] name) {
    if (name is null) {
        return MaybeIndex!uint.init;
    } else {
        return MaybeIndex!uint.of(signalNamed(name));
    }
}

void buildDrives(ref ContentGraph graph) {
    drives.clear();
    foreach (node; 0 .. cast(uint) graph.nodes.length) {
        if (graph.isKind(node, DRIVE_KIND)) {
            ContentRef at = ContentRef(node, Holder.node);
            const(char)[] target = graph.nameOf(targetOf(graph, node, "drives").value);
            Maybe!Sense sense = senseNamed(target);
            if (!sense.exists) {
                reportUnread(graph, graph.nodes.ptr[node].owner, target);
            } else {
                drives.append(SignalDrive(signalNamed(graph.textAt(at, "signal")), secondSignal(graph.textAt(at, "also")), sense.value, graph.number(at, "gain")));
            }
        }
    }
}

uint drivenSenses(Sense[] driven) {
    uint count = 0;
    foreach (ref drive; drives.slice()) {
        uint index = 0;
        while (index < count && driven[index] != drive.sense) {
            index += 1;
        }
        if (index == count) {
            driven[count] = drive.sense;
            count += 1;
        }
    }
    return count;
}

Perception felt(Perception base, const(Ratio)[] signals) {
    Perception made = base;
    foreach (drive; drives.slice()) {
        made = made.leveled(drive.sense, made.levelOf(drive.sense) + drive.heard(signals) * drive.gain);
    }
    return made;
}
