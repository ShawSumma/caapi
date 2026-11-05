async function play() {
    const canvas = document.getElementById("game");
    const status = document.getElementById("status");
    const failure = document.getElementById("failure");
    let stopped = false;

    function fail(text) {
        stopped = true;
        failure.textContent = text;
        failure.hidden = false;
    }

    function run(step) {
        try {
            step();
        } catch (error) {
            fail("the game stopped: " + error);
        }
    }

    resizeCanvas(canvas);
    let game = null;
    try {
        const module = await WebAssembly.compile(wasmFromBase64(MINED_WASM));
        game = createGame(canvas, module, (text) => {
            status.textContent = text;
            document.title = text;
        }, fail, {antialias: false, alpha: false, depth: false, stencil: false, powerPreference: "high-performance"});
        if (game !== null) {
            game.attach(await WebAssembly.instantiate(module, game.imports));
        }
    } catch (error) {
        fail("the game could not start: " + error);
        return;
    }
    if (game === null) {
        return;
    }
    run(() => game.exports.web_start(canvas.width, canvas.height, renderRadiusFromAddress()));

    function isCaptured() {
        return document.pointerLockElement === canvas;
    }

    document.addEventListener("pointerlockchange", () => {
        run(() => game.exports.web_capture(Number(isCaptured())));
    });
    document.addEventListener("pointerlockerror", () => {
        status.textContent = "the browser refused to capture the mouse; click the game again";
    });
    canvas.addEventListener("mousedown", (event) => {
        event.preventDefault();
        if (isCaptured()) {
            run(() => game.exports.web_button(event.button));
        } else {
            canvas.requestPointerLock();
        }
    });
    canvas.addEventListener("contextmenu", (event) => event.preventDefault());
    document.addEventListener("mousemove", (event) => {
        if (isCaptured()) {
            run(() => game.exports.web_motion(event.movementX, event.movementY));
        }
    });
    document.addEventListener("keydown", (event) => {
        const code = KEY_CODES[event.code];
        if (code !== undefined && isCaptured()) {
            event.preventDefault();
            run(() => game.exports.web_key_down(code, Number(event.repeat)));
        }
    });
    document.addEventListener("keyup", (event) => {
        const code = KEY_CODES[event.code];
        if (code !== undefined) {
            run(() => game.exports.web_key_up(code));
        }
    });
    window.addEventListener("resize", () => {
        if (resizeCanvas(canvas)) {
            run(() => {
                game.makeTargets(canvas.width, canvas.height);
                game.exports.web_resize(canvas.width, canvas.height);
            });
        }
    });

    function frame() {
        if (!stopped) {
            run(() => game.exports.web_frame());
            requestAnimationFrame(frame);
        }
    }
    requestAnimationFrame(frame);
}

play();
