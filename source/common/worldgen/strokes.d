module common.worldgen.strokes;

import core.stdc.math : acoshf, atanhf, cosh, coshf, fabsf, sinh, sqrtf, tanh;
import base.array : Array;
import base.hashmap : HashMap;
import base.numbers : higherOf;
import common.graph : ALL_FACES, NO_FACE, NodeId, farthestFaceBeyond;
import common.traversal : MIRRORED_ORIGINS;
import common.view : GraphView;
import geometry.honeycomb : FACE_COUNT, Face, NODE_RADIUS, mirror;
import geometry.lorentz : Motion, Point, Vec4;
import plugins.api.api : Material;

enum float LEAF_CORE = 0.5f;
enum float LEAF_CORE_DENSITY = 0.95f;
enum float LEAF_EDGE_DENSITY = 0.3f;
enum float FRAME_SLACK = 1e-3f;
enum double TEST_LENGTH = 0.8;
enum double TEST_SIDE = 0.3;
enum float TEST_TOLERANCE = 1e-4f;

struct Stroke {
    Vec4!float start;
    Vec4!float along;
    float length;
    float coshLength;
    float sinhLength;
    float tanhLength;
    float startRadius;
    float endRadius;
    float coshReach;
    Material material;
    bool isLeafy;

    static Stroke make(Motion!double frame, double length, float startRadius, float endRadius, Material material, bool isLeafy) {
        float widest = higherOf(startRadius, endRadius);
        return Stroke(frame.m.column(3).as!float(), frame.m.column(2).as!float(), cast(float) length, cast(float) cosh(length), cast(float) sinh(length), cast(float) tanh(length), startRadius, endRadius, coshf(widest), material, isLeafy);
    }

    Stroke moved(Motion!double motion) const {
        Stroke result = this;
        result.start = (motion * start.as!double()).as!float();
        result.along = (motion * along.as!double()).as!float();
        return result;
    }

    Vec4!double middle() const {
        double half = length / 2;
        return start.as!double() * cosh(half) + along.as!double() * sinh(half);
    }

    float reach() const {
        return higherOf(startRadius, endRadius);
    }

    bool isWithin(Vec4!float point, float distance) const {
        return nearest(point).coshDistance <= coshf(distance + reach());
    }

    bool mayBeWithin(Vec4!float point, float distance) const {
        return nearest(point).coshDistance <= coshf(distance + reach()) + FRAME_SLACK;
    }

    Nearest nearest(Vec4!float point) const {
        float a = -point.minkowski(start);
        float b = point.minkowski(along);
        if (b <= 0) {
            return Nearest(a, 0);
        } else if (b >= a * tanhLength) {
            return Nearest(a * coshLength - b * sinhLength, length);
        } else {
            return Nearest(sqrtf(a * a - b * b), atanhf(b / a));
        }
    }

    float radiusAt(float distance) const {
        if (length > 0) {
            return startRadius + (endRadius - startRadius) * distance / length;
        } else {
            return startRadius;
        }
    }

    bool holds(Vec4!float point, float roll) const {
        Nearest found = nearest(point);
        if (found.coshDistance > coshReach) {
            return false;
        } else {
            float radius = radiusAt(found.along);
            if (!isLeafy) {
                return found.coshDistance <= coshf(radius);
            } else {
                float depth = acoshf(higherOf(1.0f, found.coshDistance)) / radius;
                return depth <= 1 && roll < leafDensity(depth);
            }
        }
    }
}

struct Nearest {
    float coshDistance;
    float along;
}

float leafDensity(float depth) {
    if (depth <= LEAF_CORE) {
        return LEAF_CORE_DENSITY;
    } else {
        return LEAF_CORE_DENSITY + (LEAF_EDGE_DENSITY - LEAF_CORE_DENSITY) * (depth - LEAF_CORE) / (1 - LEAF_CORE);
    }
}

struct StrokeVisit {
    uint slot;
    Motion!double motion;
}

struct StrokeRun {
    NodeId node;
    uint first;
    uint count;
}

struct StrokeReach {
    Motion!double motion;
    uint record;
    uint run;
}

struct Strokes {
    HashMap!(NodeId, uint) lists;
    Array!(Array!StrokeReach) reaches;
    Array!uint freeLists;
    Array!StrokeVisit visits;
    Array!NodeId seen;

    const(StrokeReach)[] reachesAt(NodeId id) const {
        const(uint)* found = lists.find(id);
        if (found is null) {
            return null;
        } else {
            return reaches.ptr[*found].slice();
        }
    }

    void add(ref GraphView view, uint record, uint run, uint node, Stroke stroke, ref Array!NodeId reached) {
        visits.clear();
        seen.clear();
        visits.append(view.containing(node, stroke.middle()));
        seen.append(view.idAt(visits.ptr[0].slot));
        float within = coshf(NODE_RADIUS + stroke.reach());
        size_t next = 0;
        while (next < visits.length) {
            StrokeVisit visit = visits.ptr[next];
            next += 1;
            Stroke moved = stroke.moved(visit.motion);
            if (moved.nearest(Vec4!float.origin()).coshDistance <= within) {
                note(view.idAt(visit.slot), StrokeReach(visit.motion, record, run), reached);
                foreach (index; 0 .. FACE_COUNT) {
                    Face side = cast(Face) index;
                    if (moved.nearest(MIRRORED_ORIGINS[index]).coshDistance <= within + FRAME_SLACK) {
                        uint beside = view.ensureNeighborSlot(visit.slot, side);
                        if (!isSeen(view.idAt(beside))) {
                            seen.append(view.idAt(beside));
                            visits.append(StrokeVisit(beside, side.mirror.as!double() * visit.motion));
                        }
                    }
                }
            }
        }
    }

    bool isSeen(NodeId id) const {
        size_t index = 0;
        while (index < seen.length && seen.ptr[index] != id) {
            index += 1;
        }
        return index < seen.length;
    }

    void note(NodeId id, StrokeReach reach, ref Array!NodeId reached) {
        Array!StrokeReach* list = &listOf(id);
        bool hasRecord = false;
        bool hasRun = false;
        foreach (ref existing; list.slice()) {
            hasRecord = hasRecord || existing.record == reach.record;
            hasRun = hasRun || (existing.record == reach.record && existing.run == reach.run);
        }
        if (!hasRun) {
            list.append(reach);
        }
        if (!hasRecord) {
            reached.append(id);
        }
    }

    ref Array!StrokeReach listOf(NodeId id) {
        const(uint)* found = lists.find(id);
        if (found !is null) {
            return reaches.ptr[*found];
        } else if (freeLists.length > 0) {
            freeLists.length -= 1;
            uint index = freeLists.ptr[freeLists.length];
            lists.insert(id, index);
            return reaches.ptr[index];
        } else {
            lists.insert(id, cast(uint) reaches.length);
            reaches.append(Array!StrokeReach.init);
            return reaches.ptr[reaches.length - 1];
        }
    }

    void remove(NodeId id, uint record) {
        const(uint)* found = lists.find(id);
        if (found !is null) {
            uint index = *found;
            Array!StrokeReach* list = &reaches.ptr[index];
            size_t kept = 0;
            foreach (reach; list.slice()) {
                if (reach.record != record) {
                    list.ptr[kept] = reach;
                    kept += 1;
                }
            }
            list.length = kept;
            if (kept == 0) {
                list.release();
                lists.remove(id);
                freeLists.append(index);
            }
        }
    }

    void release() {
        foreach (ref list; reaches.slice()) {
            list.release();
        }
        lists.release();
        reaches.release();
        freeLists.release();
        visits.release();
        seen.release();
    }
}

unittest {
    Motion!double start = Motion!double.shift([0.2, -0.1, 0.3]);
    Stroke stroke = Stroke.make(start, TEST_LENGTH, 0.1f, 0.05f, Material.oakWood, false);
    Vec4!float beside = (start * Motion!double.shift([0, 0, TEST_LENGTH / 2]) * Motion!double.shift([TEST_SIDE, 0, 0]) * Point!double.origin()).v.as!float();
    Nearest middle = stroke.nearest(beside);
    assert(fabsf(acoshf(middle.coshDistance) - TEST_SIDE) < TEST_TOLERANCE && fabsf(middle.along - TEST_LENGTH / 2) < TEST_TOLERANCE);
    Vec4!float past = (start * Motion!double.shift([0, 0, TEST_LENGTH + TEST_SIDE]) * Point!double.origin()).v.as!float();
    Nearest end = stroke.nearest(past);
    assert(fabsf(acoshf(end.coshDistance) - TEST_SIDE) < TEST_TOLERANCE && end.along == stroke.length);
    Vec4!float behind = (start * Motion!double.shift([0, 0, -TEST_SIDE]) * Point!double.origin()).v.as!float();
    assert(fabsf(acoshf(stroke.nearest(behind).coshDistance) - TEST_SIDE) < TEST_TOLERANCE);
    assert(stroke.holds((start * Motion!double.shift([0.05, 0, 0.1]) * Point!double.origin()).v.as!float(), 0));
    assert(!stroke.holds(beside, 0));
}

StrokeVisit containing(ref GraphView view, uint node, Vec4!double point) {
    StrokeVisit visit = StrokeVisit(node, Motion!double.identity());
    uint face = farthestFaceBeyond(Point!float(point.as!float()), ALL_FACES);
    while (face != NO_FACE) {
        visit = StrokeVisit(view.ensureNeighborSlot(visit.slot, cast(Face) face), (cast(Face) face).mirror.as!double() * visit.motion);
        face = farthestFaceBeyond(Point!float((visit.motion * point).as!float()), ALL_FACES);
    }
    return visit;
}
