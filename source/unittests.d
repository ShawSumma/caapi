module unittests;

import clientArguments = client.arguments;
import clientCamera = client.camera;
import clientConfig = client.config;
import clientGame = client.game;
import clientMeshing = client.meshing;
import clientPng = client.png;
import clientStreaming = client.streaming;
import clientWorld = client.world;
import commonAllocator = common.allocator;
import commonArray = common.array;
import commonClock = common.clock;
import characterController = common.character.controller;
import characterFrame = common.character.frame;
import characterSweep = common.character.sweep;
import collisionChunk = common.collision.chunk;
import collisionGraph = common.collision.graph;
import commonCoords = common.coords;
import commonDodeca = common.dodeca;
import commonGraph = common.graph;
import commonHashmap = common.hashmap;
import commonMargins = common.margins;
import commonMaterial = common.material;
import commonMath = common.math;
import commonMurmur = common.murmur;
import commonNames = common.names;
import commonNeighbors = common.neighbors;
import commonNode = common.node;
import commonPosition = common.position;
import commonRay = common.ray;
import raycastChunk = common.raycast.chunk;
import raycastGraph = common.raycast.graph;
import commonSettings = common.settings;
import commonSlab = common.slab;
import commonTraversal = common.traversal;
import commonVector3 = common.vector3;
import worldgenBuilding = common.worldgen.building;
import worldgenGeneration = common.worldgen.generation;
import worldgenPlane = common.worldgen.plane;
import worldgenSpawn = common.worldgen.spawn;
import worldgenTerraingen = common.worldgen.terraingen;
import worldgenTower = common.worldgen.tower;

alias TESTED_MODULES = __traits(allMembers, unittests);

extern (C) int main() {
    static foreach (member; TESTED_MODULES) {
        static if (member != "object" && __traits(compiles, __traits(getUnitTests, __traits(getMember, unittests, member)))) {
            static foreach (test; __traits(getUnitTests, __traits(getMember, unittests, member))) {
                test();
            }
        }
    }
    return 0;
}
