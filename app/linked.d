module app.linked;

import client.plugins : Linked;
import crafting = plugins.crafting.plugin;
import game = plugins.game.plugin;
import pharmacology = plugins.pharmacology.plugin;

immutable Linked[3] LINKED = [Linked(crafting.NAME, &crafting.plugin), Linked(game.NAME, &game.plugin), Linked(pharmacology.NAME, &pharmacology.plugin)];
