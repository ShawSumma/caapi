module plugins.game.restart;

import client.plugins : registry, sceneCount, sceneNameAt, worldCount;
import client.structures : StructureProblem, WorldStep, growthProblem, placeWorldStructure, worldgenAt;
import common.worldgen.generation : StructureWorld, Worldgen, WorldgenKind;
import plugins.game.game : Game, PickKind, WorldPick;

StructureProblem placeStructure(ref Game game) {
    StructureProblem problem = placeWorldStructure(game.world.graph);
    if (problem.isPresent) {
        return problem;
    } else {
        game.placeAtSpawn();
        return growthProblem(game.world.graph);
    }
}

StructureProblem restartGame(ref Game game, Worldgen worldgen) {
    game.rebuildWorld(worldgen);
    return placeStructure(game);
}

Worldgen worldgenOf(WorldPick pick) {
    final switch (pick.kind) {
        case PickKind.world:
            return worldgenAt(pick.index);
        case PickKind.scene:
            return Worldgen.fromStructure(StructureWorld.fromName(sceneNameAt(pick.index)));
    }
}

uint countOf(PickKind kind) {
    final switch (kind) {
        case PickKind.world:
            return worldCount();
        case PickKind.scene:
            return sceneCount();
    }
}

WorldPick stepped(WorldPick pick, WorldStep direction) {
    uint count = countOf(pick.kind);
    uint step = count - 1;
    if (direction == WorldStep.next) {
        step = 1;
    }
    return WorldPick((pick.index + step) % count, pick.kind);
}

uint indexAmong(const(string)[] names, const(char)[] name) {
    uint index = 0;
    while (index < names.length && names[index] != name) {
        index += 1;
    }
    return index;
}

WorldPick pickOf(Worldgen worldgen) {
    const(string)[] worlds = registry().allNames();
    const(string)[] scenes = registry().allDebugNames();
    if (worldgen.kind != WorldgenKind.structure) {
        return WorldPick(0, PickKind.world);
    } else if (indexAmong(worlds, worldgen.structureName()) < worlds.length) {
        return WorldPick(indexAmong(worlds, worldgen.structureName()) + 1, PickKind.world);
    } else if (indexAmong(scenes, worldgen.structureName()) < scenes.length) {
        return WorldPick(indexAmong(scenes, worldgen.structureName()), PickKind.scene);
    } else {
        return WorldPick(0, PickKind.world);
    }
}
