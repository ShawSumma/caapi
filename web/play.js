const STROKE_FIRST = 0;
const STROKE_REPEATED = 1;
const CAPTURE_RELEASED = 0;
const CAPTURE_CAPTURED = 1;
const WHEEL_BACK = 4;
const WHEEL_AHEAD = 5;
const LOCK_REFUSED = "the browser refused to capture the mouse; click the game again";

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
        const module = await WebAssembly.compile(wasmFromBase64(CAAPI_WASM));
        game.attach(await WebAssembly.instantiate(module, game.imports));
        game.exports.web_start(canvas.width, canvas.height, renderRadiusFromAddress(), creativeFromAddress());
        const isCaptured = () => document.pointerLockElement === canvas;
        const pixelsOf = (event) => {
            const box = canvas.getBoundingClientRect();
            const scale = canvas.width / box.width;
            return [(event.clientX - box.left) * scale, (event.clientY - box.top) * scale];
        };
        const refused = () => showStatus(LOCK_REFUSED);
        const lockIfWanted = () => {
            if (!isCaptured() && game.exports.web_wants_lock() !== 0) {
                const asked = canvas.requestPointerLock();
                if (asked instanceof Promise) {
                    asked.catch(refused);
                }
            }
        };
        document.addEventListener("pointerlockchange", () => {
            if (isCaptured()) {
                game.exports.web_capture(CAPTURE_CAPTURED);
            } else {
                game.exports.web_capture(CAPTURE_RELEASED);
            }
        });
        document.addEventListener("pointerlockerror", refused);
        window.addEventListener("blur", () => game.exports.web_blur());
        canvas.addEventListener("mousedown", (event) => {
            event.preventDefault();
            const button = BUTTON_NUMBERS[event.button];
            if (button !== undefined) {
                const [x, y] = pixelsOf(event);
                game.exports.web_button(button, x, y);
                lockIfWanted();
            }
        });
        document.addEventListener("mouseup", (event) => {
            const button = BUTTON_NUMBERS[event.button];
            if (button !== undefined) {
                game.exports.web_button_up(button);
            }
        });
        canvas.addEventListener("contextmenu", (event) => event.preventDefault());
        canvas.addEventListener("wheel", (event) => {
            if (isCaptured() && event.deltaY !== 0) {
                event.preventDefault();
                game.exports.web_button(event.deltaY < 0 ? WHEEL_BACK : WHEEL_AHEAD, 0, 0);
                game.exports.web_button_up(event.deltaY < 0 ? WHEEL_BACK : WHEEL_AHEAD);
            }
        });
        document.addEventListener("mousemove", (event) => {
            if (isCaptured()) {
                game.exports.web_motion(event.movementX, event.movementY);
            } else {
                const [x, y] = pixelsOf(event);
                game.exports.web_pointer(x, y);
            }
        });
        document.addEventListener("keydown", (event) => {
            const name = keyNameOf(event.code);
            if (name !== undefined && game.exports.web_takes_keys(isCaptured() ? 1 : 0) !== 0) {
                event.preventDefault();
                game.exports.web_key_down(game.name(name), event.repeat ? STROKE_REPEATED : STROKE_FIRST);
                lockIfWanted();
            }
        });
        document.addEventListener("keyup", (event) => {
            const name = keyNameOf(event.code);
            if (name !== undefined) {
                game.exports.web_key_up(game.name(name));
            }
        });
        window.addEventListener("resize", () => {
            const changed = resizeCanvas(canvas);
            if (changed) {
                game.makeTargets(canvas.width, canvas.height);
                game.exports.web_resize(canvas.width, canvas.height);
            }
        });
        window.addEventListener("pagehide", () => game.exports.web_save());
        document.addEventListener("visibilitychange", () => {
            if (document.hidden) {
                game.exports.web_save();
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
