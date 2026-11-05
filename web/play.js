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
        document.addEventListener("pointerlockchange", () => game.exports.web_capture(Number(isCaptured())));
        document.addEventListener("pointerlockerror", () => showStatus("the browser refused to capture the mouse; click the game again"));
        canvas.addEventListener("mousedown", (event) => {
            event.preventDefault();
            if (isCaptured()) {
                game.exports.web_button(event.button);
            } else {
                canvas.requestPointerLock();
            }
        });
        canvas.addEventListener("contextmenu", (event) => event.preventDefault());
        document.addEventListener("mousemove", (event) => {
            if (isCaptured()) {
                game.exports.web_motion(event.movementX, event.movementY);
            }
        });
        document.addEventListener("keydown", (event) => {
            const code = KEY_CODES[event.code];
            if (code !== undefined && isCaptured()) {
                event.preventDefault();
                game.exports.web_key_down(code, Number(event.repeat));
            }
        });
        document.addEventListener("keyup", (event) => {
            const code = KEY_CODES[event.code];
            if (code !== undefined) {
                game.exports.web_key_up(code);
            }
        });
        window.addEventListener("resize", () => {
            if (resizeCanvas(canvas)) {
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
