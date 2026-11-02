module unit.sweep;

import core.math : sqrt;
import core.stdc.math : fabsf;
import common.character.features : Edge, Quad;
import common.character.sweep : Capsule, Contact, Section, SectionRank;

enum float TOLERANCE = 1e-5f;

unittest {
    Capsule capsule = Capsule([0, 1, 0], 0.4f, 0.9f, 0.01f);
    uint count = capsule.sectionCount();
    assert(capsule.sectionOffset(0, count) == -capsule.capOffset());
    assert(capsule.sectionOffset(count - 1, count) == capsule.capOffset());
    float spacing = capsule.sectionOffset(1, count) - capsule.sectionOffset(0, count);
    float half = spacing / 2;
    assert(capsule.radius - sqrt(capsule.radius * capsule.radius - half * half) <= capsule.skin);
    Capsule sphere = Capsule([0, 1, 0], 0.4f, 0.4f, 0.01f);
    assert(sphere.sectionCount() == 1);
}

unittest {
    Quad floor = Quad([[0, 1, 0], [0, 1, 1], [1, 1, 1], [1, 1, 0]], [0, 1, 0]);
    Section section = Section(null, [0.5f, 2.0f, 0.5f], 0.4f, 0.41f, SectionRank.lowest);
    float[3] down = [0, -1, 0];
    Contact landing = section.quadContact(floor, down, 2.0f, Contact.init);
    assert(landing.isHit() && fabsf(landing.stop - 0.59f) < TOLERANCE);
    float[3] along = [1, 0, 0];
    assert(!section.quadContact(floor, along, 2.0f, Contact.init).isHit());
    Section resting = Section(null, [0.5f, 1.405f, 0.5f], 0.4f, 0.41f, SectionRank.lowest);
    Contact touching = resting.quadContact(floor, down, 1.0f, Contact.init);
    assert(touching.stop == 0 && touching.gap > 0.004f && touching.gap < 0.006f);
    Edge rim = Edge([1, 1, 0], [1, 1, 1]);
    Section beside = Section(null, [1.6f, 1.2f, 0.5f], 0.4f, 0.41f, SectionRank.lowest);
    float[3] toward = [-1, 0, 0];
    Contact edgeHit = beside.edgeContact(rim, toward, 1.0f, Contact.init);
    assert(edgeHit.isHit() && edgeHit.normal[0] > 0 && edgeHit.normal[1] > 0);
}
