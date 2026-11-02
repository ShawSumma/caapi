module unittests;

import base.crash : reportCrashes, reportHangAfter;
import unitHashmap = unit.hashmap;
import unitAllocator = unit.allocator;
import unitSlab = unit.slab;
import unitClock = unit.clock;
import unitParallel = unit.parallel;
import unitNames = unit.names;
import unitUnits = unit.units;
import unitVector3 = unit.vector3;
import unitLorentz = unit.lorentz;
import unitHoneycomb = unit.honeycomb;
import unitNode = unit.node;
import unitNeighbors = unit.neighbors;
import unitTraversal = unit.traversal;
import unitRaycast = unit.raycast;
import unitChart = unit.chart;
import unitFeatures = unit.features;
import unitSweep = unit.sweep;
import unitController = unit.controller;
import unitPlane = unit.plane;
import unitClimate = unit.climate;
import unitGeneration = unit.generation;
import unitBlueprint = unit.blueprint;
import unitStructure = unit.structure;
import unitHorospheres = unit.horospheres;
import unitSpawn = unit.spawn;
import unitStrokes = unit.strokes;
import unitCamera = unit.camera;
import unitPng = unit.png;
import unitImages = unit.images;
import unitFrames = unit.frames;
import unitMeshing = unit.meshing;
import unitArrivals = unit.arrivals;
import unitHud = unit.hud;

enum uint TEST_TIME_LIMIT_SECONDS = 300;

alias TESTED_MODULES = __traits(allMembers, unittests);

extern (C) int main() {
    reportCrashes();
    reportHangAfter(TEST_TIME_LIMIT_SECONDS);
    static foreach (member; TESTED_MODULES) {
        static if (member != "object" && __traits(compiles, __traits(getUnitTests, __traits(getMember, unittests, member)))) {
            static foreach (test; __traits(getUnitTests, __traits(getMember, unittests, member))) {
                test();
            }
        }
    }
    return 0;
}
