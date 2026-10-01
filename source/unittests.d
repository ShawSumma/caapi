module unittests;

import array = common.array;
import characterCollision = common.character_controller.collision;
import chunkCollision = common.chunk_collision;
import chunkNeighbors = common.chunk_neighbors;
import chunkRayCasting = common.chunk_ray_casting;
import clientConfig = client.config;
import collisionMath = common.collision_math;
import controller = common.character_controller.controller;
import dodeca = common.dodeca;
import game = client.game;
import generation = common.worldgen.generation;
import graph = common.graph;
import graphCollision = common.graph_collision;
import graphRayCasting = common.graph_ray_casting;
import hashMap = common.hash_map;
import localCharacterController = client.local_character_controller;
import localWorld = client.local_world;
import margins = common.margins;
import math = common.math;
import meshing = client.meshing;
import murmur = common.murmur;
import node = common.node;
import plane = common.worldgen.plane;
import png = client.png;
import proto = common.proto;
import rangeAllocator = common.range_allocator;
import simConfig = common.sim_config;
import slab = common.slab;
import spawn = common.worldgen.spawn;
import terraingen = common.worldgen.terraingen;
import traversal = common.traversal;
import vector3 = common.vector3;
import voxelMath = common.voxel_math;
import world = common.world;
import worldgenDriver = client.worldgen_driver;

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
