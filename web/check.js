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

function check() {
    const log = document.getElementById("status");
    const notes = [];
    function note(text) {
        notes.push(text);
        log.textContent = notes.join("\n");
    }
    const parameters = new URLSearchParams(location.search);
    const canvas = document.getElementById("game");
    canvas.style.position = "absolute";
    canvas.style.left = "-10000px";
    canvas.width = CHECK_WIDTH;
    canvas.height = CHECK_HEIGHT;
    let lastStatus = "";
    const module = new WebAssembly.Module(wasmFromBase64(MINED_WASM));
    const game = createGame(canvas, module, (text) => {
        lastStatus = text;
    }, (text) => {
        throw new Error(text);
    }, {antialias: false, alpha: false, depth: false, stencil: false, preserveDrawingBuffer: true});
    game.attach(new WebAssembly.Instance(module, game.imports));
    const started = performance.now();
    game.exports.web_start(CHECK_WIDTH, CHECK_HEIGHT, renderRadiusFromAddress());
    note("started in " + Math.round(performance.now() - started) + "ms");
    game.exports.web_capture(1);

    function runFrames(count) {
        for (let frame = 0; frame < count; frame += 1) {
            game.exports.web_frame();
        }
    }

    function makeSheet(cells) {
        const sheet = document.createElement("canvas");
        const rows = Math.ceil(cells / SHEET_COLUMNS);
        sheet.width = SHEET_COLUMNS * SHEET_CELL_WIDTH;
        sheet.height = rows * SHEET_CELL_HEIGHT;
        sheet.style.display = "block";
        document.body.insertBefore(sheet, document.body.firstChild);
        return sheet.getContext("2d");
    }

    function drawCell(context, cell, label) {
        const x = (cell % SHEET_COLUMNS) * SHEET_CELL_WIDTH;
        const y = Math.floor(cell / SHEET_COLUMNS) * SHEET_CELL_HEIGHT;
        context.drawImage(canvas, x, y, SHEET_CELL_WIDTH, SHEET_CELL_HEIGHT);
        context.fillStyle = "#ff0";
        context.font = "12px monospace";
        context.fillText(label, x + 4, y + 14);
    }

    function pressed(key, frames, label, context, cell) {
        game.exports.web_key_down(KEY_CODES[key], 0);
        runFrames(frames);
        game.exports.web_key_up(KEY_CODES[key]);
        drawCell(context, cell, label);
    }

    function worldName() {
        return lastStatus.split(" - ")[1].replace(" ([ ])", "");
    }

    const mode = parameters.get("mode") || "run";
    if (mode === "tour") {
        const worlds = parseInt(parameters.get("worlds"));
        const context = makeSheet(worlds);
        for (let world = 0; world < worlds; world += 1) {
            const start = performance.now();
            runFrames(TOUR_WORLD_FRAMES);
            game.exports.web_key_down(KEY_CODES.KeyW, 0);
            runFrames(TOUR_WORLD_FRAMES / 2);
            game.exports.web_key_up(KEY_CODES.KeyW);
            game.exports.web_button(LEFT_BUTTON);
            game.exports.web_button(RIGHT_BUTTON);
            runFrames(2);
            drawCell(context, world, world + " " + worldName());
            console.log(world + " " + lastStatus + " " + Math.round(performance.now() - start) + "ms");
            game.exports.web_key_down(KEY_CODES.BracketRight, 0);
            game.exports.web_frame();
        }
        note("toured " + worlds + " worlds, memory " + Math.round(game.exports.memory.buffer.byteLength / 1048576) + "MB, gl error " + game.gl.getError());
    } else if (mode === "flight") {
        const context = makeSheet(FLIGHT_SHOTS);
        const flightStart = performance.now();
        runFrames(SETTLE_FRAMES);
        game.exports.web_key_down(KEY_CODES.KeyN, 0);
        game.exports.web_key_down(KEY_CODES.KeyW, 0);
        for (let shot = 0; shot < FLIGHT_SHOTS; shot += 1) {
            runFrames(FLIGHT_FRAMES_PER_SHOT);
            drawCell(context, shot, "flew " + (shot + 1) * FLIGHT_FRAMES_PER_SHOT + " frames");
            note("shot " + shot + " at " + Math.round(performance.now() - flightStart) + "ms: drawable " + game.exports.web_drawable_chunks() + " visible " + game.exports.web_visible_chunks() + " backlog " + game.exports.web_backlog() + " memory " + Math.round(game.exports.memory.buffer.byteLength / 1048576) + "MB gl error " + game.gl.getError());
        }
    } else if (mode === "actions") {
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
        game.exports.web_key_down(KEY_CODES.KeyV, 0);
        game.exports.web_key_down(KEY_CODES.KeyV, 0);
        pressed("KeyS", ACTION_FRAMES, "walk mode, back", context, 11);
        note("status: " + lastStatus);
        note("gl error " + game.gl.getError());
    } else {
        const frames = parseInt(parameters.get("frames")) || CHECK_FRAMES;
        const loopStart = performance.now();
        runFrames(frames);
        note("after " + frames + " frames in " + Math.round(performance.now() - loopStart) + "ms: drawable " + game.exports.web_drawable_chunks() + " visible " + game.exports.web_visible_chunks() + " backlog " + game.exports.web_backlog() + " settled " + game.exports.web_settled());
        note("status: " + lastStatus);
        note("gl error: " + game.gl.getError());
        note("memory: " + Math.round(game.exports.memory.buffer.byteLength / 1048576) + "MB");
        const shot = document.createElement("canvas");
        shot.width = CHECK_WIDTH;
        shot.height = CHECK_HEIGHT;
        shot.getContext("2d").drawImage(canvas, 0, 0);
        shot.style.display = "block";
        document.body.insertBefore(shot, document.body.firstChild);
    }
}

try {
    check();
} catch (error) {
    const failure = document.getElementById("failure");
    failure.textContent = "check failed: " + error + "\n" + error.stack;
    failure.hidden = false;
}
