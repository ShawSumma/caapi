module web.main;

import core.stdc.stdlib : calloc;
import base.array : Array;
import base.clock : FrameClock, nowMilliseconds, nowSeconds;
import base.maybe : Maybe;
import base.names : ENUM_NAMES;
import base.stdio : printed;
import base.units : Time;
import app.linked : LINKED;
import client.plugins : Linked, gatherWorlds, worldCount, worldNameAt;
import client.structures : StructureProblem, WorldStep, growthProblem;
import common.settings : CHUNK_DIMENSION;
import plugins.api.flags : Flags;
import arbor = plugins.arbor.plugin;
import babel = plugins.babel.plugin;
import backrooms = plugins.backrooms.plugin;
import base = plugins.base.plugin;
import blocks = plugins.blocks.plugin;
import box = plugins.box.plugin;
import buildings = plugins.buildings.plugin;
import caves = plugins.caves.plugin;
import city = plugins.city.plugin;
import connector = plugins.connector.plugin;
import plugins.crafting.crafting : IdSet;
import plugins.crafting.inventory : Cycle;
import crown = plugins.crown.plugin;
import fixtures = plugins.fixtures.plugin;
import plugins.game.bindings : Bindings, Bound, Rules;
import plugins.game.config : ClientConfig;
import plugins.game.game : Click, Game, Key, KeyStroke, MOST_STEP_SECONDS, PickKind, Saving, Screen, UiAction, UiKind, WorldPick, creativeInventory, frameInputOf;
import plugins.game.hud : FrameMeter, Hud, MouseCapture, STATUS_CAPACITY, statusLine;
import plugins.game.input : BUTTON_NAME_CAPACITY, Controls, Request, buttonName;
import plugins.game.restart : placeStructure, stepped, worldgenOf;
import plugins.game.save : SaveData, Writer, applyEdits, applyState, readGame, writeGame;
import horospheres = plugins.horospheres.plugin;
import lattice = plugins.lattice.plugin;
import library = plugins.library.plugin;
import palace = plugins.palace.plugin;
import planet = plugins.planet.plugin;
import road = plugins.road.plugin;
import rooms = plugins.rooms.plugin;
import skies = plugins.skies.plugin;
import tower = plugins.tower.plugin;
import trail = plugins.trail.plugin;
import vaults = plugins.vaults.plugin;
import web.renderer : WebRenderer;

immutable Linked[23] WORLD_PLUGINS = [
    Linked("base", &base.plugin),
    Linked("blocks", &blocks.plugin),
    Linked("box", &box.plugin),
    Linked("buildings", &buildings.plugin),
    Linked("connector", &connector.plugin),
    Linked("horospheres", &horospheres.plugin),
    Linked("rooms", &rooms.plugin),
    Linked("arbor", &arbor.plugin),
    Linked("babel", &babel.plugin),
    Linked("backrooms", &backrooms.plugin),
    Linked("caves", &caves.plugin),
    Linked("city", &city.plugin),
    Linked("crown", &crown.plugin),
    Linked("fixtures", &fixtures.plugin),
    Linked("lattice", &lattice.plugin),
    Linked("library", &library.plugin),
    Linked("palace", &palace.plugin),
    Linked("planet", &planet.plugin),
    Linked("road", &road.plugin),
    Linked("skies", &skies.plugin),
    Linked("tower", &tower.plugin),
    Linked("trail", &trail.plugin),
    Linked("vaults", &vaults.plugin),
];
immutable Linked[LINKED.length + WORLD_PLUGINS.length] WEB_PLUGINS = LINKED[] ~ WORLD_PLUGINS[];

enum double FRAME_WORK_MILLISECONDS = 13.0;
enum double LEAST_TASK_MILLISECONDS = 2.0;
enum double AUTOSAVE_SECONDS = 30;
enum size_t NAME_CAPACITY = 32;
enum size_t STORE_KEY_CAPACITY = 128;
enum string CONFIG_KEY = "config";
enum string WORLD_KEY = "world";
enum uint RIGHT_BUTTON = 3;
enum uint WHEEL_BACK = 4;
enum uint WHEEL_AHEAD = 5;

enum SessionMark : ubyte {
    stopped,
    titleStale,
}

enum Saved : ubyte {
    absent,
    present,
}

extern (C) nothrow @nogc {
    void web_status(const(char)* text);
    void web_fail(const(char)* text);
    void web_free_pointer();
    uint web_store_size(const(char)* key, uint keyLength);
    uint web_store_read(const(char)* key, uint keyLength, ubyte* into, uint capacity);
    void web_store_write(const(char)* key, uint keyLength, const(ubyte)* from, uint length);
    void web_store_remove(const(char)* key, uint keyLength);
}

Maybe!(Array!ubyte) readStored(const(char)[] key) {
    uint size = web_store_size(key.ptr, cast(uint) key.length);
    if (size == 0) {
        return Maybe!(Array!ubyte).init;
    } else {
        Array!ubyte bytes;
        bytes.resize(size);
        web_store_read(key.ptr, cast(uint) key.length, bytes.ptr, size);
        return Maybe!(Array!ubyte).of(bytes);
    }
}

void writeStored(const(char)[] key, const(ubyte)[] bytes) {
    web_store_write(key.ptr, cast(uint) key.length, bytes.ptr, cast(uint) bytes.length);
}

struct Session {
    Game game;
    WebRenderer renderer;
    Hud hud;
    ClientConfig config;
    Controls controls;
    FrameClock clock;
    FrameMeter meter;
    double mouseDx = 0;
    double mouseDy = 0;
    double lastSave = 0;
    char[NAME_CAPACITY] name = 0;
    char[STORE_KEY_CAPACITY] saveKey = 0;
    size_t saveKeyLength;
    WorldPick current;
    Flags!SessionMark marks;
    MouseCapture mouse;
    Rules rules;
    Saving saving;

    bool isCaptured() const {
        return mouse == MouseCapture.captured;
    }

    bool isRunning() const {
        return !marks.has(SessionMark.stopped);
    }

    void start(uint width, uint height, float renderRadius, Rules chosen) {
        rules = chosen;
        renderer.setup(CHUNK_DIMENSION, width, height);
        loadConfig();
        current = WorldPick(storedWorld(), PickKind.world);
        game = Game.make(worldgenOf(current), config.reach);
        game.comfort = config.comfort;
        game.thread.spacing = config.threadSpacing;
        game.thread.most = config.threadBeads;
        game.rules = rules;
        game.world.graph.bindView();
        game.world.renderRadius = renderRadius;
        startInventory();
        SaveData saved;
        Saved loaded = loadEdits(saved);
        report(game.placeStructure());
        if (loaded == Saved.present) {
            applyState(game, saved);
        }
        saved.release();
        double started = nowSeconds();
        clock = FrameClock.startingAt(started);
        meter = FrameMeter.startingAt(started);
        lastSave = started;
        marks.set(SessionMark.titleStale);
    }

    void startInventory() {
        if (rules == Rules.creative) {
            game.inventory = creativeInventory();
        }
    }

    uint storedWorld() {
        Maybe!(Array!ubyte) bytes = readStored(WORLD_KEY);
        uint index = 0;
        if (bytes.exists) {
            while (index < worldCount() && worldNameAt(index) != cast(const(char)[]) bytes.value.slice()) {
                index += 1;
            }
            bytes.value.release();
        }
        if (index < worldCount()) {
            return index;
        } else {
            return 0;
        }
    }

    void loadConfig() {
        Maybe!(Array!ubyte) bytes = readStored(CONFIG_KEY);
        if (bytes.exists) {
            config = ClientConfig.fromText(cast(const(char)[]) bytes.value.slice());
            bytes.value.release();
        } else {
            config = ClientConfig.make();
        }
        controls.bindings = config.bindings;
    }

    void saveConfig() {
        config.bindings = controls.bindings;
        Array!char text;
        config.write(text);
        writeStored(CONFIG_KEY, cast(const(ubyte)[]) text.slice());
        text.release();
    }

    const(char)[] saveKeyOf(uint index, char[] key) const {
        const(char)[] world = worldNameAt(index);
        return printed(key, "save-%.*s-%s", cast(int) world.length, world.ptr, ENUM_NAMES!Rules[rules].ptr);
    }

    Saved loadEdits(ref SaveData saved) {
        if (current.kind == PickKind.scene) {
            saving = Saving.scene;
            return Saved.absent;
        } else {
            return loadWorldEdits(saved);
        }
    }

    Saved loadWorldEdits(ref SaveData saved) {
        saveKeyLength = saveKeyOf(current.index, saveKey[]).length;
        saving = Saving.enabled;
        Maybe!(Array!ubyte) bytes = readStored(saveKey[0 .. saveKeyLength]);
        if (!bytes.exists) {
            return Saved.absent;
        } else {
            const(char)* problem = readGame(bytes.value.slice(), game, saved);
            bytes.value.release();
            if (problem !is null) {
                saving = Saving.refused;
                return Saved.absent;
            } else {
                applyEdits(game, saved);
                return Saved.present;
            }
        }
    }

    void writeSave() {
        if (saving == Saving.enabled) {
            Writer writer;
            writeGame(game, writer);
            writeStored(saveKey[0 .. saveKeyLength], writer.bytes.slice());
            writer.bytes.release();
        }
        lastSave = nowSeconds();
    }

    void report(StructureProblem problem) {
        if (problem.isPresent) {
            web_fail(problem.text.ptr);
            marks.set(SessionMark.stopped);
        }
    }

    void frame() {
        double frameStart = nowMilliseconds();
        double now = nowSeconds();
        Time dt = Time(cast(float) clock.tick(now, MOST_STEP_SECONDS));
        if (game.screen == Screen.none && !isCaptured) {
            openMenu();
        }
        if (game.screen != Screen.none && isCaptured) {
            web_free_pointer();
        }
        game.step(frameInputOf(config, controls.held, mouseDx, mouseDy, dt), dt);
        mouseDx = 0;
        mouseDy = 0;
        hud.buildMarkers(game);
        hud.build(game, controls, meter, renderer.width, renderer.height);
        renderer.render(game.world, hud.vertices.slice(), hud.markers.slice(), hud.atlas);
        double deadline = frameStart + FRAME_WORK_MILLISECONDS;
        double least = nowMilliseconds() + LEAST_TASK_MILLISECONDS;
        if (least > deadline) {
            deadline = least;
        }
        game.world.streamer.runTasksUntil(deadline);
        report(growthProblem(game.world.graph));
        if (now - lastSave > AUTOSAVE_SECONDS) {
            writeSave();
        }
        bool refreshed = meter.tick(now, clock);
        if (refreshed) {
            marks.set(SessionMark.titleStale);
        }
        if (marks.has(SessionMark.titleStale)) {
            updateStatus();
        }
    }

    void updateStatus() {
        char[STATUS_CAPACITY] text = statusLine(game, mouse, meter);
        web_status(text.ptr);
        marks.clear(SessionMark.titleStale);
    }

    bool takesKeys() const {
        return isCaptured || game.screen != Screen.none;
    }

    void keyDown(const(char)[] key, KeyStroke press) {
        if (takesKeys()) {
            handle(controls.keyDown(game, key, press));
        }
    }

    void handle(Request request) {
        final switch (request) {
            case Request.nothing:
                break;
            case Request.previousWorld:
                switchWorld(WorldStep.previous);
                break;
            case Request.nextWorld:
                switchWorld(WorldStep.next);
                break;
            case Request.menu:
                openMenu();
                break;
            case Request.bindingsChanged:
                saveConfig();
                break;
        }
        marks.set(SessionMark.titleStale);
    }

    void openMenu() {
        writeSave();
        listWorlds();
        game.openScreen(Screen.menu);
    }

    void listWorlds() {
        char[STORE_KEY_CAPACITY] key;
        game.worlds.current = current;
        game.worlds.saving = saving;
        game.worlds.saved = IdSet.init;
        foreach (index; 0 .. worldCount()) {
            const(char)[] stored = saveKeyOf(index, key[]);
            if (web_store_size(stored.ptr, cast(uint) stored.length) > 0) {
                game.worlds.saved.set(index);
            }
        }
    }

    void switchWorld(WorldStep direction) {
        writeSave();
        enter(stepped(current, direction));
    }

    void enter(WorldPick pick) {
        current = pick;
        if (pick.kind == PickKind.world) {
            writeStored(WORLD_KEY, cast(const(ubyte)[]) worldNameAt(pick.index));
        }
        game.rebuildWorld(worldgenOf(pick));
        game.startOver();
        startInventory();
        SaveData saved;
        Saved loaded = loadEdits(saved);
        report(placeStructure(game));
        if (loaded == Saved.present) {
            applyState(game, saved);
        }
        saved.release();
    }

    void deleteWorld(uint index) {
        char[STORE_KEY_CAPACITY] key;
        const(char)[] stored = saveKeyOf(index, key[]);
        web_store_remove(stored.ptr, cast(uint) stored.length);
        if (current == WorldPick(index, PickKind.world)) {
            enter(current);
        }
        listWorlds();
    }

    void button(uint pressed, float x, float y) {
        char[BUTTON_NAME_CAPACITY] buttonText;
        hud.pointAt(x, y);
        if (game.screen != Screen.none && !controls.awaiting.exists) {
            clickScreen(pressed);
        } else if (isCaptured || controls.awaiting.exists) {
            keyDown(buttonName(pressed, buttonText[]), KeyStroke.first);
        }
    }

    void buttonUp(uint released) {
        char[BUTTON_NAME_CAPACITY] buttonText;
        controls.keyUp(game, buttonName(released, buttonText[]));
    }

    void clickScreen(uint pressed) {
        Maybe!UiAction action = hud.actionAt();
        if (pressed == WHEEL_BACK) {
            hud.wheel(Cycle.back);
        } else if (pressed == WHEEL_AHEAD) {
            hud.wheel(Cycle.ahead);
        } else if (action.exists && action.value.kind == UiKind.rebind) {
            controls.awaiting = Maybe!Bound.of(Bound(cast(ubyte) action.value.index));
        } else if (action.exists && action.value.kind == UiKind.resetBindings) {
            controls.bindings = Bindings.defaults();
            saveConfig();
        } else if (action.exists && action.value.kind == UiKind.playWorld) {
            writeSave();
            enter(WorldPick(action.value.index, PickKind.world));
        } else if (action.exists && action.value.kind == UiKind.playScene) {
            writeSave();
            enter(WorldPick(action.value.index, PickKind.scene));
        } else if (action.exists && action.value.kind == UiKind.deleteWorld) {
            deleteWorld(action.value.index);
        } else if (!action.exists && game.screen == Screen.menu) {
            game.closeScreen();
        } else if (action.exists) {
            Click click = Click.primary;
            if (pressed == RIGHT_BUTTON) {
                click = Click.secondary;
            } else if (controls.held.has(Key.down)) {
                click = Click.quick;
            }
            game.apply(action.value, click);
        }
    }

    void motion(double dx, double dy) {
        if (isCaptured && game.screen == Screen.none) {
            mouseDx += dx;
            mouseDy += dy;
        }
    }

    bool wantsLock() const {
        return game.screen == Screen.none;
    }

    void capture(MouseCapture state) {
        mouse = state;
        if (state == MouseCapture.released && game.screen == Screen.none) {
            controls.letGoAll(game);
        } else if (state == MouseCapture.captured && game.screen == Screen.menu) {
            game.closeScreen();
        }
        marks.set(SessionMark.titleStale);
    }
}

__gshared Session* session;

uint flagOf(bool condition) {
    if (condition) {
        return 1;
    } else {
        return 0;
    }
}

extern (C) void web_start(uint width, uint height, float renderRadius, uint creative) {
    gatherWorlds(WEB_PLUGINS[]);
    session = cast(Session*) calloc(1, Session.sizeof);
    *session = Session.init;
    Rules rules = Rules.survival;
    if (creative != 0) {
        rules = Rules.creative;
    }
    session.start(width, height, renderRadius, rules);
}

extern (C) void web_frame() {
    if (session.isRunning) {
        session.frame();
    }
}

extern (C) void web_resize(uint width, uint height) {
    session.renderer.resize(width, height);
}

extern (C) char* web_name_buffer() {
    return session.name.ptr;
}

extern (C) uint web_takes_keys(uint captured) {
    return flagOf(captured != 0 || session.game.screen != Screen.none);
}

extern (C) void web_key_down(uint length, uint press) {
    session.keyDown(session.name[0 .. length], cast(KeyStroke) press);
}

extern (C) void web_key_up(uint length) {
    session.controls.keyUp(session.game, session.name[0 .. length]);
}

extern (C) void web_button(uint pressed, float x, float y) {
    session.button(pressed, x, y);
}

extern (C) void web_button_up(uint released) {
    session.buttonUp(released);
}

extern (C) void web_pointer(float x, float y) {
    session.hud.pointAt(x, y);
}

extern (C) void web_motion(double dx, double dy) {
    session.motion(dx, dy);
}

extern (C) uint web_wants_lock() {
    return flagOf(session.wantsLock());
}

extern (C) void web_capture(uint state) {
    session.capture(cast(MouseCapture) state);
}

extern (C) void web_blur() {
    session.controls.letGoAll(session.game);
}

extern (C) void web_save() {
    session.writeSave();
}
