module unit.heap;

import base.heap : WorkHeap, rekeyed;
import base.maybe : Maybe;
import base.splitmix : SplitMix;

enum uint ITEMS = 1000;
enum uint DROPPED_EVERY = 3;

unittest {
    WorkHeap!uint heap;
    SplitMix rng = SplitMix(7);
    foreach (value; 0 .. ITEMS) {
        heap.push(cast(float)(rng.next() % ITEMS), value);
    }
    float last = -1;
    uint popped;
    foreach (taken; 0 .. ITEMS / 2) {
        float nearest = heap.nearest();
        bool took = heap.pop(popped);
        assert(took && nearest >= last);
        last = nearest;
    }
    Maybe!float flipped(ref uint value) {
        if (value % DROPPED_EVERY == 0) {
            return Maybe!float.init;
        } else {
            return Maybe!float.of(-cast(float) value);
        }
    }
    rekeyed!flipped(heap);
    uint before = uint.max;
    uint left = 0;
    bool took = heap.pop(popped);
    while (took) {
        assert(popped % DROPPED_EVERY != 0 && popped < before);
        before = popped;
        left += 1;
        took = heap.pop(popped);
    }
    assert(left > 0 && left <= ITEMS / 2);
    assert(heap.nearest() == float.infinity);
    heap.release();
}
