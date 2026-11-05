module unit.sweep;

import core.math : sqrt;
import core.stdc.math : fabsf;
import base.maybe : Maybe;
import base.vector3 : Vec3;
import common.character.features : Edge, Quad;
import common.character.sweep : Capsule, Contact, Section, SectionRank;

enum float TOLERANCE = 1e-5f;

unittest {
    Capsule capsule = Capsule(Vec3!float(0, 1, 0), 0.4f, 0.9f, 0.01f);
    uint count = capsule.sectionCount();
    assert(capsule.sectionOffset(0, count) == -capsule.capOffset());
    assert(capsule.sectionOffset(count - 1, count) == capsule.capOffset());
    float spacing = capsule.sectionOffset(1, count) - capsule.sectionOffset(0, count);
    float half = spacing / 2;
    assert(capsule.radius - sqrt(capsule.radius * capsule.radius - half * half) <= capsule.skin);
    Capsule sphere = Capsule(Vec3!float(0, 1, 0), 0.4f, 0.4f, 0.01f);
    assert(sphere.sectionCount() == 1);
}

unittest {
    Quad floor = Quad([Vec3!float(0, 1, 0), Vec3!float(0, 1, 1), Vec3!float(1, 1, 1), Vec3!float(1, 1, 0)], Vec3!float(0, 1, 0));
    Section section = Section(null, Vec3!float(0.5f, 2.0f, 0.5f), 0.4f, 0.41f, SectionRank.lowest);
    Vec3!float down = Vec3!float(0, -1, 0);
    Maybe!Contact landing = section.quadContact(floor, down, 2.0f, Maybe!Contact.init);
    assert(landing.exists && fabsf(landing.value.stop - 0.59f) < TOLERANCE);
    Vec3!float along = Vec3!float(1, 0, 0);
    assert(!section.quadContact(floor, along, 2.0f, Maybe!Contact.init).exists);
    Section resting = Section(null, Vec3!float(0.5f, 1.405f, 0.5f), 0.4f, 0.41f, SectionRank.lowest);
    Maybe!Contact touching = resting.quadContact(floor, down, 1.0f, Maybe!Contact.init);
    assert(touching.exists && touching.value.stop == 0 && touching.value.gap > 0.004f && touching.value.gap < 0.006f);
    Edge rim = Edge(Vec3!float(1, 1, 0), Vec3!float(1, 1, 1));
    Section beside = Section(null, Vec3!float(1.6f, 1.2f, 0.5f), 0.4f, 0.41f, SectionRank.lowest);
    Vec3!float toward = Vec3!float(-1, 0, 0);
    Maybe!Contact edgeHit = beside.edgeContact(rim, toward, 1.0f, Maybe!Contact.init);
    assert(edgeHit.exists && edgeHit.value.normal.x > 0 && edgeHit.value.normal.y > 0);
}
