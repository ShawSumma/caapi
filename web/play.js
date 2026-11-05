const CAPTURE_RELEASED = 0;
const CAPTURE_CAPTURED = 1;
const STROKE_FIRST = 0;
const STROKE_REPEATED = 1;

const play = async () => {
    const canvas = document.getElementById("game");
    const status = document.getElementById("status");
    const failures = failuresGoTo(document.getElementById("failure"));
    const showStatus = (text) => {
        status.textContent = text;
        document.title = text;
    };
    resizeCanvas(canvas);
    const game = createGame(canvas, showStatus, failures.show, {antialias: false, alpha: false, depth: false, stencil: false, powerPreference: "high-performance"});
    if (game !== null) {
        const module = await WebAssembly.compile(wasmFromBase64(MINED_WASM));
        game.attach(await WebAssembly.instantiate(module, game.imports));
        game.exports.web_start(canvas.width, canvas.height, renderRadiusFromAddress());
        const isCaptured = () => document.pointerLockElement === canvas;
        document.addEventListener("pointerlockchange", () => {
            const captured = isCaptured();
            if (captured) {
                game.exports.web_capture(CAPTURE_CAPTURED);
            } else {
                game.exports.web_capture(CAPTURE_RELEASED);
            }
        });
        document.addEventListener("pointerlockerror", () => showStatus("the browser refused to capture the mouse; click the game again"));
        canvas.addEventListener("mousedown", (event) => {
            event.preventDefault();
            const captured = isCaptured();
            if (captured) {
                game.exports.web_button(event.button);
            } else {
                canvas.requestPointerLock();
            }
        });
        canvas.addEventListener("contextmenu", (event) => event.preventDefault());
        document.addEventListener("mousemove", (event) => {
            const captured = isCaptured();
            if (captured) {
                game.exports.web_motion(event.movementX, event.movementY);
            }
        });
        document.addEventListener("keydown", (event) => {
            const code = KEY_CODES[event.code];
            const captured = isCaptured();
            if (code !== undefined && captured) {
                event.preventDefault();
                if (event.repeat) {
                    game.exports.web_key_down(code, STROKE_REPEATED);
                } else {
                    game.exports.web_key_down(code, STROKE_FIRST);
                }
            }
        });
        document.addEventListener("keyup", (event) => {
            const code = KEY_CODES[event.code];
            if (code !== undefined) {
                game.exports.web_key_up(code);
            }
        });
        window.addEventListener("resize", () => {
            const changed = resizeCanvas(canvas);
            if (changed) {
                game.makeTargets(canvas.width, canvas.height);
                game.exports.web_resize(canvas.width, canvas.height);
            }
        });
        const frame = () => {
            if (!failures.failed) {
                game.exports.web_frame();
                requestAnimationFrame(frame);
            }
        };
        requestAnimationFrame(frame);
    }
};

play();
