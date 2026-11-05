const CHECK_WIDTH = 1280;
const CHECK_HEIGHT = 720;
const CHECK_FRAMES = 900;
const SHEET_COLUMNS = 6;
const SHEET_CELL_WIDTH = 320;
const SHEET_CELL_HEIGHT = 180;
const TOUR_WORLD_FRAMES = 120;
const SETTLE_FRAMES = 600;
const LOOK_DOWN_COUNTS = 500;
const ACTION_FRAMES = 150;
const FLIGHT_SHOTS = 12;
const FLIGHT_FRAMES_PER_SHOT = 400;
const LEFT_BUTTON = 0;
const RIGHT_BUTTON = 2;
const BYTES_PER_MEGABYTE = 1048576;
const QUIET_FRAMES = 60;
const QUIET_FRAME_MILLISECONDS = 3;
const FRAME_INTERVAL_MILLISECONDS = 1000 / 60;
const MILLISECONDS_PER_SECOND = 1000;
const MOST_LOAD_FRAMES = 20000;
const BENCH_STILL_FRAMES = 300;
const BENCH_FLIGHT_FRAMES = 900;
const PIXEL_CHANNELS = 4;
const TIMED_IMPORTS = ["web_gl_upload_faces", "web_gl_voxels", "web_gl_highlight", "web_gl_marker", "web_gl_finish"];
const PERCENTILE_MEDIAN = 0.5;
const PERCENTILE_HIGH = 0.95;

const check = () => {
    const log = document.getElementById("status");
    const failures = failuresGoTo(document.getElementById("failure"));
    const notes = [];
    const note = (text) => {
        notes.push(text);
        log.textContent = notes.join("\n");
    };
    const parameters = new URLSearchParams(location.search);
    const canvas = document.getElementById("game");
    canvas.style.position = "absolute";
    canvas.style.left = "-10000px";
    const checkWidth = parseInt(parameters.get("width")) || CHECK_WIDTH;
    const checkHeight = parseInt(parameters.get("height")) || CHECK_HEIGHT;
    canvas.width = checkWidth;
    canvas.height = checkHeight;
    let lastStatus = "";
    const module = new WebAssembly.Module(wasmFromBase64(MINED_WASM));
    const game = createGame(canvas, (text) => {
        lastStatus = text;
    }, failures.show, {antialias: false, alpha: false, depth: false, stencil: false, preserveDrawingBuffer: true});

    const phase = {beforeBegin: 0, uploads: 0, uploadCount: 0, inVoxels: 0, inFinish: 0, inOthers: 0, frameStart: 0, finishEnd: 0, visible: 0};
    const timeImports = () => {
        const env = game.imports.env;
        const begin = env.web_gl_begin;
        env.web_gl_begin = (...arguments_) => {
            phase.beforeBegin = performance.now() - phase.frameStart;
            begin(...arguments_);
        };
        for (const name of TIMED_IMPORTS) {
            const inner = env[name];
            env[name] = (...arguments_) => {
                const start = performance.now();
                inner(...arguments_);
                const spent = performance.now() - start;
                if (name === "web_gl_upload_faces") {
                    phase.uploads += spent;
                    phase.uploadCount += 1;
                } else if (name === "web_gl_voxels") {
                    phase.inVoxels += spent;
                    phase.visible = arguments_[1];
                } else if (name === "web_gl_finish") {
                    phase.inFinish += spent;
                    phase.finishEnd = performance.now();
                } else {
                    phase.inOthers += spent;
                }
            };
        }
    };
    if (parameters.get("mode") === "bench") {
        timeImports();
    }
    game.attach(new WebAssembly.Instance(module, game.imports));
    const started = performance.now();
    game.exports.web_start(checkWidth, checkHeight, renderRadiusFromAddress());
    note("started in " + Math.round(performance.now() - started) + "ms");
    game.exports.web_capture(1);

    const memoryMegabytes = () => Math.round(game.exports.memory.buffer.byteLength / BYTES_PER_MEGABYTE);

    const runFrames = (count) => {
        for (let frame = 0; frame < count; frame += 1) {
            game.exports.web_frame();
        }
    };

    const makeSheet = (cells) => {
        const sheet = document.createElement("canvas");
        sheet.width = SHEET_COLUMNS * SHEET_CELL_WIDTH;
        sheet.height = Math.ceil(cells / SHEET_COLUMNS) * SHEET_CELL_HEIGHT;
        sheet.style.display = "block";
        document.body.insertBefore(sheet, document.body.firstChild);
        return sheet.getContext("2d");
    };

    const drawCell = (context, cell, label) => {
        const x = (cell % SHEET_COLUMNS) * SHEET_CELL_WIDTH;
        const y = Math.floor(cell / SHEET_COLUMNS) * SHEET_CELL_HEIGHT;
        context.drawImage(canvas, x, y, SHEET_CELL_WIDTH, SHEET_CELL_HEIGHT);
        context.fillStyle = "#ff0";
        context.font = "12px monospace";
        context.fillText(label, x + 4, y + 14);
    };

    const pressed = (key, frames, label, context, cell) => {
        game.exports.web_key_down(KEY_CODES[key], 0);
        runFrames(frames);
        game.exports.web_key_up(KEY_CODES[key]);
        drawCell(context, cell, label);
    };

    const worldName = () => lastStatus.split(" - ")[1].replace(" ([ ])", "");

    const tour = () => {
        const worlds = parseInt(parameters.get("worlds"));
        const context = makeSheet(worlds);
        for (let world = 0; world < worlds; world += 1) {
            runFrames(TOUR_WORLD_FRAMES);
            game.exports.web_key_down(KEY_CODES.KeyW, 0);
            runFrames(TOUR_WORLD_FRAMES / 2);
            game.exports.web_key_up(KEY_CODES.KeyW);
            game.exports.web_button(LEFT_BUTTON);
            game.exports.web_button(RIGHT_BUTTON);
            runFrames(2);
            drawCell(context, world, world + " " + worldName());
            game.exports.web_key_down(KEY_CODES.BracketRight, 0);
            game.exports.web_frame();
        }
        note("toured " + worlds + " worlds, memory " + memoryMegabytes() + "MB, gl error " + game.gl.getError());
    };

    const flight = () => {
        const shots = parseInt(parameters.get("shots")) || FLIGHT_SHOTS;
        const context = makeSheet(shots);
        runFrames(SETTLE_FRAMES);
        game.exports.web_key_down(KEY_CODES.KeyN, 0);
        game.exports.web_key_down(KEY_CODES.KeyW, 0);
        for (let shot = 0; shot < shots; shot += 1) {
            runFrames(FLIGHT_FRAMES_PER_SHOT);
            drawCell(context, shot, "flew " + (shot + 1) * FLIGHT_FRAMES_PER_SHOT + " frames");
            note("shot " + shot + ": memory " + memoryMegabytes() + "MB, gl error " + game.gl.getError());
        }
    };

    const actions = () => {
        const context = makeSheet(12);
        runFrames(SETTLE_FRAMES);
        drawCell(context, 0, "start");
        game.exports.web_motion(0, LOOK_DOWN_COUNTS);
        runFrames(30);
        drawCell(context, 1, "look down");
        game.exports.web_button(LEFT_BUTTON);
        runFrames(ACTION_FRAMES);
        drawCell(context, 2, "broke a block");
        game.exports.web_key_down(KEY_CODES.Digit7, 0);
        game.exports.web_button(RIGHT_BUTTON);
        runFrames(ACTION_FRAMES);
        drawCell(context, 3, "placed marble");
        game.exports.web_motion(0, -LOOK_DOWN_COUNTS);
        runFrames(30);
        pressed("KeyW", ACTION_FRAMES, "walked forward", context, 4);
        pressed("Space", 30, "jumped", context, 5);
        pressed("KeyT", 60, "threw a block", context, 6);
        game.exports.web_key_down(KEY_CODES.KeyV, 0);
        pressed("Space", ACTION_FRAMES, "flew up (V)", context, 7);
        pressed("ShiftLeft", ACTION_FRAMES / 2, "sank (Shift)", context, 8);
        game.exports.web_key_down(KEY_CODES.KeyN, 0);
        pressed("KeyW", ACTION_FRAMES, "noclip (N)", context, 9);
        pressed("ArrowLeft", ACTION_FRAMES / 2, "turned (arrow)", context, 10);
        game.exports.web_key_down(KEY_CODES.Space, 0);
        runFrames(2 * ACTION_FRAMES);
        game.exports.web_key_up(KEY_CODES.Space);
        game.exports.web_key_down(KEY_CODES.KeyV, 0);
        pressed("KeyS", ACTION_FRAMES, "walk mode, back", context, 11);
        note("status: " + lastStatus);
        note("gl error " + game.gl.getError());
    };

    const showCanvas = () => {
        const context = makeSheet(1);
        context.canvas.width = checkWidth;
        context.canvas.height = checkHeight;
        context.drawImage(canvas, 0, 0);
    };

    const run = () => {
        const frames = parseInt(parameters.get("frames")) || CHECK_FRAMES;
        const loopStart = performance.now();
        runFrames(frames);
        note("after " + frames + " frames in " + Math.round(performance.now() - loopStart) + "ms");
        note("status: " + lastStatus);
        note("gl error: " + game.gl.getError());
        note("memory: " + memoryMegabytes() + "MB");
        showCanvas();
    };

    const world = () => {
        const index = parseInt(parameters.get("index"));
        const frames = parseInt(parameters.get("frames")) || CHECK_FRAMES;
        for (let step = 0; step < index; step += 1) {
            game.exports.web_key_down(KEY_CODES.BracketRight, 0);
            game.exports.web_frame();
        }
        game.exports.web_motion(0, parseFloat(parameters.get("pitch")) || 0);
        runFrames(frames);
        note("world: " + worldName() + ", gl error " + game.gl.getError() + ", memory " + memoryMegabytes() + "MB");
        showCanvas();
    };

    const percentile = (sorted, share) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * share))];

    const summary = (values) => {
        const sorted = [...values].sort((a, b) => a - b);
        const total = sorted.reduce((sum, value) => sum + value, 0);
        return "mean " + (total / sorted.length).toFixed(2) + " p50 " + percentile(sorted, PERCENTILE_MEDIAN).toFixed(2) + " p95 " + percentile(sorted, PERCENTILE_HIGH).toFixed(2);
    };

    const pixel = new Uint8Array(PIXEL_CHANNELS);

    const timedFrame = (samples) => {
        phase.uploads = 0;
        phase.uploadCount = 0;
        phase.inVoxels = 0;
        phase.inFinish = 0;
        phase.inOthers = 0;
        phase.frameStart = performance.now();
        game.exports.web_frame();
        const frameEnd = performance.now();
        game.gl.readPixels(0, 0, 1, 1, game.gl.RGBA, game.gl.UNSIGNED_BYTE, pixel);
        const gpuEnd = performance.now();
        samples.total.push(frameEnd - phase.frameStart);
        samples.gpu.push(gpuEnd - frameEnd);
        samples.before.push(phase.beforeBegin - phase.uploads);
        samples.uploads.push(phase.uploads);
        samples.voxels.push(phase.inVoxels);
        samples.finish.push(phase.inFinish);
        samples.others.push(phase.inOthers);
        samples.after.push(frameEnd - phase.finishEnd);
        samples.visible.push(phase.visible);
        return phase.uploadCount;
    };

    const newSamples = () => ({total: [], gpu: [], before: [], uploads: [], voxels: [], finish: [], others: [], after: [], visible: []});

    const report = (label, samples) => {
        note(label + " (" + samples.total.length + " frames, " + samples.total.reduce((sum, value) => sum + value, 0).toFixed(0) + "ms, visible " + summary(samples.visible) + ")");
        for (const name of Object.keys(samples)) {
            if (name !== "visible") {
                note("  " + name + ": " + summary(samples[name]));
            }
        }
    };

    const bench = () => {
        const info = game.gl.getExtension("WEBGL_debug_renderer_info");
        note("renderer: " + game.gl.getParameter(info.UNMASKED_RENDERER_WEBGL));
        note("extensions: " + game.gl.getSupportedExtensions().join(" "));
        const worldSteps = parseInt(parameters.get("index")) || 0;
        for (let step = 0; step < worldSteps; step += 1) {
            game.exports.web_key_down(KEY_CODES.BracketRight, 0);
            game.exports.web_frame();
        }
        game.exports.web_frame();
        note("world: " + worldName());
        const loading = newSamples();
        let quiet = 0;
        while (quiet < QUIET_FRAMES && loading.total.length < MOST_LOAD_FRAMES) {
            const uploads = timedFrame(loading);
            if (uploads === 0 && loading.total[loading.total.length - 1] < QUIET_FRAME_MILLISECONDS) {
                quiet += 1;
            } else {
                quiet = 0;
            }
        }
        report("load until quiet", loading);
        note("  at 60Hz this load takes " + (loading.total.reduce((sum, value) => sum + Math.max(value, FRAME_INTERVAL_MILLISECONDS), 0) / MILLISECONDS_PER_SECOND).toFixed(1) + "s");
        showCanvas();
        const still = newSamples();
        for (let frame = 0; frame < BENCH_STILL_FRAMES; frame += 1) {
            timedFrame(still);
        }
        report("still", still);
        const flying = newSamples();
        game.exports.web_key_down(KEY_CODES.KeyN, 0);
        game.exports.web_key_down(KEY_CODES.KeyW, 0);
        for (let frame = 0; frame < BENCH_FLIGHT_FRAMES; frame += 1) {
            timedFrame(flying);
        }
        report("flight", flying);
        note("memory: " + memoryMegabytes() + "MB, gl error " + game.gl.getError());
    };

    const modes = {tour, flight, actions, run, world, bench};
    modes[parameters.get("mode") || "run"]();
};

check();
