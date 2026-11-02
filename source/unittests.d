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
import geometryHoneycomb = geometry.honeycomb;
import geometryCube = geometry.cube;
import geometryRay = geometry.ray;
import commonMaterial = common.material;
import commonSettings = common.settings;
import commonNode = common.node;
import commonGraph = common.graph;
import commonNeighbors = common.neighbors;
import commonPosition = common.position;
import commonTraversal = common.traversal;
import commonView = common.view;
import commonEviction = common.eviction;
import raycastChunk = common.raycast.chunk;
import raycastGraph = common.raycast.graph;
import characterChart = common.character.chart;
import characterFeatures = common.character.features;
import characterSweep = common.character.sweep;
import characterController = common.character.controller;
import worldgenPlane = common.worldgen.plane;
import worldgenClimate = common.worldgen.climate;
import worldgenGeneration = common.worldgen.generation;
import worldgenBlueprint = common.worldgen.blueprint;
import worldgenBuilding = common.worldgen.building;
import worldgenStructure = common.worldgen.structure;
import worldgenHorospheres = common.worldgen.horospheres;
import worldgenSpawn = common.worldgen.spawn;
import worldgenStrokes = common.worldgen.strokes;
import clientArguments = client.arguments;
import clientConfig = client.config;
import unitCamera = unit.camera;
import unitPng = unit.png;
import unitImages = unit.images;
import clientFrames = client.frames;
import unitMeshing = unit.meshing;
import clientArrivals = client.arrivals;
import clientStreaming = client.streaming;
import clientWorld = client.world;
import clientGame = client.game;
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
