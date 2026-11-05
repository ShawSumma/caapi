const KEY_CODES = {
    KeyW: 0, KeyA: 1, KeyS: 2, KeyD: 3, Space: 4, ShiftLeft: 5, ArrowLeft: 6, ArrowRight: 7, ArrowUp: 8, ArrowDown: 9,
    KeyV: 10, KeyN: 11, KeyT: 12, BracketLeft: 13, BracketRight: 14,
    Digit1: 15, Digit2: 16, Digit3: 17, Digit4: 18, Digit5: 19, Digit6: 20, Digit7: 21, Digit8: 22, Digit9: 23,
};
const DEFAULT_RENDER_RADIUS = 5;
const MOST_RENDER_RADIUS = 6;
const FACE_TEXTURE_WIDTH = 4096;
const WORDS_PER_FACE = 2;
const COMMON_BUFFER_BYTES = 512;
const COMMON_BINDING = 0;
const UNIT_FACES = 0;
const UNIT_TEXTURES = 1;
const UNIT_DEPTH = 2;
const UNIT_GLOW = 3;
const UNIT_IMAGE = 4;
const CHUNK_RECORD_WORDS = 20;
const MATRIX_WORDS = 16;
const CUBE_EDGE_VERTICES = 24;
const CUBE_VERTICES = 36;
const CROSSHAIR_VERTICES = 18;
const FULLSCREEN_VERTICES = 3;
const HUD_VERTEX_BYTES = 16;
const HUD_COLOR_OFFSET = 8;
const TEXEL_BYTES = 4;
const WASI_ENOSYS = 52;
const WASI_EBADF = 8;
const WASI_SUCCESS = 0;
const NANOSECONDS_PER_MILLISECOND = 1000000n;

function createGame(canvas, module, onStatus, onFailure, contextOptions) {
    const gl = canvas.getContext("webgl2", contextOptions);
    if (gl === null) {
        onFailure("this browser or machine has no WebGL2, which mined needs to draw");
        return null;
    }
    let memory = null;
    let bytes = null;
    let words = null;
    let floats = null;
    let exports = null;

    function refreshViews() {
        if (bytes === null || bytes.buffer !== memory.buffer) {
            bytes = new Uint8Array(memory.buffer);
            words = new Uint32Array(memory.buffer);
            floats = new Float32Array(memory.buffer);
        }
    }

    function cString(pointer) {
        refreshViews();
        let end = pointer;
        while (bytes[end] !== 0) {
            end += 1;
        }
        return new TextDecoder().decode(bytes.subarray(pointer, end));
    }

    function compile(type, source) {
        const shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
            throw new Error("shader failed to compile: " + gl.getShaderInfoLog(shader));
        }
        return shader;
    }

    function program(vertex, fragment, uniformNames) {
        const made = gl.createProgram();
        gl.attachShader(made, compile(gl.VERTEX_SHADER, vertex));
        gl.attachShader(made, compile(gl.FRAGMENT_SHADER, fragment));
        gl.linkProgram(made);
        if (!gl.getProgramParameter(made, gl.LINK_STATUS)) {
            throw new Error("shaders failed to link: " + gl.getProgramInfoLog(made));
        }
        const block = gl.getUniformBlockIndex(made, "Common");
        if (block !== gl.INVALID_INDEX) {
            gl.uniformBlockBinding(made, block, COMMON_BINDING);
        }
        const uniforms = {};
        for (const name of uniformNames) {
            uniforms[name] = gl.getUniformLocation(made, name);
        }
        return {made, uniforms};
    }

    const programs = {
        voxels: program(VOXELS_VERT, VOXELS_FRAG, ["faces", "textures", "draw_transform", "draw_reversed", "dimension", "cell_ratio", "glowing_materials", "framed_material"]),
        highlight: program(HIGHLIGHT_VERT, HIGHLIGHT_FRAG, ["model", "low", "high"]),
        marker: program(MARKER_VERT, MARKER_FRAG, ["model", "half_side", "marker_color"]),
        fog: program(FULLSCREEN_VERT, FOG_FRAG, ["depth_input", "glow_input"]),
        crosshair: program(CROSSHAIR_VERT, CROSSHAIR_FRAG, ["width_over_height"]),
        hud: program(HUD_VERT, HUD_FRAG, []),
        present: program(FULLSCREEN_VERT, PRESENT_FRAG, ["image"]),
    };

    const emptyVertices = gl.createVertexArray();
    const hudVertices = gl.createVertexArray();
    const hudBuffer = gl.createBuffer();
    gl.bindVertexArray(hudVertices);
    gl.bindBuffer(gl.ARRAY_BUFFER, hudBuffer);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, HUD_VERTEX_BYTES, 0);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, true, HUD_VERTEX_BYTES, HUD_COLOR_OFFSET);
    gl.bindVertexArray(emptyVertices);

    const commonBuffer = gl.createBuffer();
    gl.bindBuffer(gl.UNIFORM_BUFFER, commonBuffer);
    gl.bufferData(gl.UNIFORM_BUFFER, COMMON_BUFFER_BYTES, gl.DYNAMIC_DRAW);
    gl.bindBufferBase(gl.UNIFORM_BUFFER, COMMON_BINDING, commonBuffer);

    gl.useProgram(programs.voxels.made);
    gl.uniform1i(programs.voxels.uniforms.faces, UNIT_FACES);
    gl.uniform1i(programs.voxels.uniforms.textures, UNIT_TEXTURES);
    gl.useProgram(programs.fog.made);
    gl.uniform1i(programs.fog.uniforms.depth_input, UNIT_DEPTH);
    gl.uniform1i(programs.fog.uniforms.glow_input, UNIT_GLOW);
    gl.useProgram(programs.present.made);
    gl.uniform1i(programs.present.uniforms.image, UNIT_IMAGE);

    let faceTexture = null;
    let faceRows = 0;
    const copyFramebuffer = gl.createFramebuffer();
    let geometryFramebuffer = null;
    let overlayFramebuffer = null;
    let targets = [];
    let targetWidth = 0;
    let targetHeight = 0;

    function makeFaceTexture(rows) {
        const texture = gl.createTexture();
        gl.activeTexture(gl.TEXTURE0 + UNIT_FACES);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RG32UI, FACE_TEXTURE_WIDTH, rows);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        return texture;
    }

    function rowsFor(capacity) {
        return Math.ceil(capacity / FACE_TEXTURE_WIDTH);
    }

    function makeTarget(format, attachment, framebuffers) {
        const texture = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texStorage2D(gl.TEXTURE_2D, 1, format, targetWidth, targetHeight);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        for (const framebuffer of framebuffers) {
            gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer);
            gl.framebufferTexture2D(gl.FRAMEBUFFER, attachment, gl.TEXTURE_2D, texture, 0);
        }
        targets.push(texture);
        return texture;
    }

    function makeTargets(width, height) {
        for (const texture of targets) {
            gl.deleteTexture(texture);
        }
        targets = [];
        targetWidth = width;
        targetHeight = height;
        if (geometryFramebuffer === null) {
            geometryFramebuffer = gl.createFramebuffer();
            overlayFramebuffer = gl.createFramebuffer();
        }
        gl.activeTexture(gl.TEXTURE0 + UNIT_IMAGE);
        makeTarget(gl.SRGB8_ALPHA8, gl.COLOR_ATTACHMENT0, [geometryFramebuffer, overlayFramebuffer]);
        gl.activeTexture(gl.TEXTURE0 + UNIT_GLOW);
        makeTarget(gl.R8, gl.COLOR_ATTACHMENT1, [geometryFramebuffer]);
        gl.activeTexture(gl.TEXTURE0 + UNIT_DEPTH);
        makeTarget(gl.DEPTH_COMPONENT32F, gl.DEPTH_ATTACHMENT, [geometryFramebuffer]);
        gl.bindFramebuffer(gl.FRAMEBUFFER, geometryFramebuffer);
        gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1]);
        if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
            throw new Error("the geometry framebuffer is incomplete");
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, overlayFramebuffer);
        gl.drawBuffers([gl.COLOR_ATTACHMENT0]);
    }

    const glImports = {
        web_gl_setup(pixels, size, mips, layers, faceCapacity) {
            refreshViews();
            gl.activeTexture(gl.TEXTURE0 + UNIT_TEXTURES);
            gl.bindTexture(gl.TEXTURE_2D_ARRAY, gl.createTexture());
            gl.texStorage3D(gl.TEXTURE_2D_ARRAY, mips, gl.SRGB8_ALPHA8, size, size, layers);
            let offset = pixels;
            for (let mip = 0; mip < mips; mip += 1) {
                const side = size >> mip;
                const count = side * side * TEXEL_BYTES * layers;
                gl.texSubImage3D(gl.TEXTURE_2D_ARRAY, mip, 0, 0, 0, side, side, layers, gl.RGBA, gl.UNSIGNED_BYTE, bytes, offset);
                offset += count;
            }
            gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
            gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
            gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.REPEAT);
            gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.REPEAT);
            faceRows = rowsFor(faceCapacity);
            faceTexture = makeFaceTexture(faceRows);
            makeTargets(canvas.width, canvas.height);
        },
        web_gl_grow_faces(capacity) {
            const rows = rowsFor(capacity);
            const old = faceTexture;
            const grown = makeFaceTexture(rows);
            gl.bindFramebuffer(gl.READ_FRAMEBUFFER, copyFramebuffer);
            gl.framebufferTexture2D(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, old, 0);
            gl.copyTexSubImage2D(gl.TEXTURE_2D, 0, 0, 0, 0, 0, FACE_TEXTURE_WIDTH, faceRows);
            gl.bindFramebuffer(gl.READ_FRAMEBUFFER, null);
            gl.deleteTexture(old);
            faceTexture = grown;
            faceRows = rows;
        },
        web_gl_upload_faces(offset, count, faces) {
            refreshViews();
            gl.activeTexture(gl.TEXTURE0 + UNIT_FACES);
            gl.bindTexture(gl.TEXTURE_2D, faceTexture);
            let at = offset;
            let source = faces >>> 2;
            let left = count;
            while (left > 0) {
                const column = at % FACE_TEXTURE_WIDTH;
                const run = Math.min(left, FACE_TEXTURE_WIDTH - column);
                gl.texSubImage2D(gl.TEXTURE_2D, 0, column, Math.floor(at / FACE_TEXTURE_WIDTH), run, 1, gl.RG_INTEGER, gl.UNSIGNED_INT, words, source);
                at += run;
                source += run * WORDS_PER_FACE;
                left -= run;
            }
        },
        web_gl_begin(uniforms, count, red, green, blue) {
            refreshViews();
            gl.bindBuffer(gl.UNIFORM_BUFFER, commonBuffer);
            gl.bufferSubData(gl.UNIFORM_BUFFER, 0, bytes, uniforms, count);
            gl.bindFramebuffer(gl.FRAMEBUFFER, geometryFramebuffer);
            gl.viewport(0, 0, targetWidth, targetHeight);
            gl.depthMask(true);
            gl.colorMask(true, true, true, true);
            gl.clearBufferfv(gl.COLOR, 0, [red, green, blue, 1]);
            gl.clearBufferfv(gl.COLOR, 1, [0, 0, 0, 0]);
            gl.clearBufferfv(gl.DEPTH, 0, [0]);
            gl.enable(gl.DEPTH_TEST);
            gl.depthFunc(gl.GREATER);
            gl.disable(gl.BLEND);
            gl.bindVertexArray(emptyVertices);
        },
        web_gl_voxels(chunks, count, dimension, cellRatio, glowing, framedMaterial) {
            refreshViews();
            const voxels = programs.voxels;
            const uniforms = voxels.uniforms;
            gl.useProgram(voxels.made);
            gl.activeTexture(gl.TEXTURE0 + UNIT_FACES);
            gl.bindTexture(gl.TEXTURE_2D, faceTexture);
            gl.uniform1ui(uniforms.dimension, dimension);
            gl.uniform1f(uniforms.cell_ratio, cellRatio);
            gl.uniform1uiv(uniforms.glowing_materials, words, glowing >>> 2, 3);
            gl.uniform1ui(uniforms.framed_material, framedMaterial);
            gl.enable(gl.CULL_FACE);
            gl.cullFace(gl.BACK);
            gl.frontFace(gl.CW);
            let reversed = -1;
            let record = chunks >>> 2;
            for (let index = 0; index < count; index += 1) {
                gl.uniformMatrix4fv(uniforms.draw_transform, false, floats, record, MATRIX_WORDS);
                const flipped = floats[record + MATRIX_WORDS + 2];
                if (flipped !== reversed) {
                    gl.uniform1f(uniforms.draw_reversed, flipped);
                    reversed = flipped;
                }
                gl.drawArrays(gl.TRIANGLES, words[record + MATRIX_WORDS], words[record + MATRIX_WORDS + 1]);
                record += CHUNK_RECORD_WORDS;
            }
            gl.disable(gl.CULL_FACE);
        },
        web_gl_highlight(model, low, high) {
            refreshViews();
            const highlight = programs.highlight;
            gl.useProgram(highlight.made);
            gl.depthMask(false);
            gl.uniformMatrix4fv(highlight.uniforms.model, false, floats, model >>> 2, MATRIX_WORDS);
            gl.uniform3fv(highlight.uniforms.low, floats, low >>> 2, 3);
            gl.uniform3fv(highlight.uniforms.high, floats, high >>> 2, 3);
            gl.drawArrays(gl.LINES, 0, CUBE_EDGE_VERTICES);
            gl.depthMask(true);
        },
        web_gl_marker(model, half, color) {
            refreshViews();
            const marker = programs.marker;
            gl.useProgram(marker.made);
            gl.uniformMatrix4fv(marker.uniforms.model, false, floats, model >>> 2, MATRIX_WORDS);
            gl.uniform1f(marker.uniforms.half_side, half);
            gl.uniform1ui(marker.uniforms.marker_color, color);
            gl.drawArrays(gl.TRIANGLES, 0, CUBE_VERTICES);
        },
        web_gl_finish(widthOverHeight, hud, hudCount) {
            refreshViews();
            gl.bindFramebuffer(gl.FRAMEBUFFER, overlayFramebuffer);
            gl.disable(gl.DEPTH_TEST);
            gl.depthMask(false);
            gl.colorMask(true, true, true, false);
            gl.enable(gl.BLEND);
            gl.blendEquation(gl.FUNC_ADD);
            gl.blendFunc(gl.ONE_MINUS_SRC_ALPHA, gl.SRC_ALPHA);
            gl.useProgram(programs.fog.made);
            gl.drawArrays(gl.TRIANGLES, 0, FULLSCREEN_VERTICES);
            gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
            gl.useProgram(programs.crosshair.made);
            gl.uniform1f(programs.crosshair.uniforms.width_over_height, widthOverHeight);
            gl.drawArrays(gl.TRIANGLES, 0, CROSSHAIR_VERTICES);
            if (hudCount > 0) {
                gl.useProgram(programs.hud.made);
                gl.bindVertexArray(hudVertices);
                gl.bindBuffer(gl.ARRAY_BUFFER, hudBuffer);
                gl.bufferData(gl.ARRAY_BUFFER, bytes, gl.DYNAMIC_DRAW, hud, hudCount * HUD_VERTEX_BYTES);
                gl.drawArrays(gl.TRIANGLES, 0, hudCount);
                gl.bindVertexArray(emptyVertices);
            }
            gl.disable(gl.BLEND);
            gl.colorMask(true, true, true, true);
            gl.bindFramebuffer(gl.FRAMEBUFFER, null);
            gl.viewport(0, 0, canvas.width, canvas.height);
            gl.useProgram(programs.present.made);
            gl.drawArrays(gl.TRIANGLES, 0, FULLSCREEN_VERTICES);
        },
    };

    const envImports = {
        web_now() {
            return performance.now();
        },
        web_status(text) {
            onStatus(cString(text));
        },
        web_fail(text) {
            onFailure(cString(text));
        },
        ...glImports,
    };

    const wasiImports = {
        fd_write(descriptor, vectors, vectorCount, written) {
            refreshViews();
            let total = 0;
            let text = "";
            for (let index = 0; index < vectorCount; index += 1) {
                const start = words[(vectors >>> 2) + index * 2];
                const length = words[(vectors >>> 2) + index * 2 + 1];
                text += new TextDecoder().decode(bytes.subarray(start, start + length));
                total += length;
            }
            console.log(text);
            words[written >>> 2] = total;
            return WASI_SUCCESS;
        },
        clock_time_get(clock, precision, result) {
            new BigUint64Array(memory.buffer, result, 1)[0] = BigInt(Math.floor(performance.now())) * NANOSECONDS_PER_MILLISECOND;
            return WASI_SUCCESS;
        },
        environ_sizes_get(count, size) {
            refreshViews();
            words[count >>> 2] = 0;
            words[size >>> 2] = 0;
            return WASI_SUCCESS;
        },
        environ_get() {
            return WASI_SUCCESS;
        },
        args_sizes_get(count, size) {
            refreshViews();
            words[count >>> 2] = 0;
            words[size >>> 2] = 0;
            return WASI_SUCCESS;
        },
        args_get() {
            return WASI_SUCCESS;
        },
        fd_prestat_get() {
            return WASI_EBADF;
        },
        proc_exit(status) {
            throw new Error("the game exited with status " + status);
        },
    };

    const imports = {env: envImports, wasi_snapshot_preview1: {...wasiImports}};
    for (const needed of WebAssembly.Module.imports(module)) {
        if (needed.module === "wasi_snapshot_preview1" && !(needed.name in imports.wasi_snapshot_preview1)) {
            imports.wasi_snapshot_preview1[needed.name] = () => WASI_ENOSYS;
        }
    }
    const game = {
        gl,
        imports,
        makeTargets,
        exports: null,
        attach(instance) {
            exports = instance.exports;
            memory = exports.memory;
            exports._initialize();
            game.exports = exports;
        },
    };
    return game;
}

function resizeCanvas(canvas) {
    const scale = window.devicePixelRatio || 1;
    const width = Math.max(1, Math.floor(canvas.clientWidth * scale));
    const height = Math.max(1, Math.floor(canvas.clientHeight * scale));
    const changed = canvas.width !== width || canvas.height !== height;
    canvas.width = width;
    canvas.height = height;
    return changed;
}

function renderRadiusFromAddress() {
    const asked = parseFloat(new URLSearchParams(location.search).get("radius"));
    if (asked > 0) {
        return Math.min(asked, MOST_RENDER_RADIUS);
    } else {
        return DEFAULT_RENDER_RADIUS;
    }
}

function wasmFromBase64(text) {
    const binary = atob(text);
    const wasmBytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
        wasmBytes[index] = binary.charCodeAt(index);
    }
    return wasmBytes;
}
