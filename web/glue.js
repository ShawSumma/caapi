const KEY_CODES = {KeyW: 0, KeyA: 1, KeyS: 2, KeyD: 3, Space: 4, ShiftLeft: 5, ArrowLeft: 6, ArrowRight: 7, ArrowUp: 8, ArrowDown: 9, KeyV: 10, KeyN: 11, KeyT: 12, BracketLeft: 13, BracketRight: 14, Digit1: 15, Digit2: 16, Digit3: 17, Digit4: 18, Digit5: 19, Digit6: 20, Digit7: 21, Digit8: 22, Digit9: 23, KeyP: 24, KeyO: 25, KeyE: 26, KeyF: 27};
const PROGRAM_UNIFORMS = [["face_texture", "textures", "current_draw.transform", "current_draw.reversed", "dimension", "cell_ratio", "glowing_materials", "unseen_materials", "framed_material"], ["model", "low", "high"], ["model", "half_side", "marker_color"], ["depth_input", "glow_input"], ["width_over_height"], ["glyph_atlas"], ["image"]];
const PROGRAM_VOXELS = 0;
const PROGRAM_HIGHLIGHT = 1;
const PROGRAM_MARKER = 2;
const PROGRAM_FOG = 3;
const PROGRAM_CROSSHAIR = 4;
const PROGRAM_HUD = 5;
const PROGRAM_PRESENT = 6;
const DEFAULT_RENDER_RADIUS = 5;
const MOST_RENDER_RADIUS = 6;
const FACE_TEXTURE_WIDTH = 4096;
const WORDS_PER_FACE = 2;
const COMMON_BUFFER_BYTES = 2048;
const COMMON_BINDING = 0;
const UNIT_FACES = 0;
const UNIT_TEXTURES = 1;
const UNIT_DEPTH = 2;
const UNIT_GLOW = 3;
const UNIT_IMAGE = 4;
const UNIT_ATLAS = 5;
const CHUNK_RECORD_WORDS = 20;
const MATRIX_WORDS = 16;
const CUBE_EDGE_VERTICES = 24;
const CUBE_VERTICES = 36;
const CROSSHAIR_VERTICES = 18;
const FULLSCREEN_VERTICES = 3;
const HUD_VERTEX_BYTES = 16;
const HUD_COLOR_OFFSET = 8;
const HUD_TEXEL_OFFSET = 12;
const TEXEL_BYTES = 4;
const MATERIAL_WORDS = 3;
const CIOVEC_WORDS = 2;
const WASI_ERRNO_SUCCESS = 0;
const WASI_ERRNO_BADF = 8;

const gameOn = (canvas, gl, showStatus, showFailure) => {
    let memory = null;
    let bytes = null;
    let words = null;
    let floats = null;
    const programs = [];
    const decoder = new TextDecoder();

    const refreshViews = () => {
        if (bytes === null || bytes.buffer !== memory.buffer) {
            bytes = new Uint8Array(memory.buffer);
            words = new Uint32Array(memory.buffer);
            floats = new Float32Array(memory.buffer);
        }
    };

    const textAt = (pointer, length) => {
        refreshViews();
        return decoder.decode(bytes.subarray(pointer, pointer + length));
    };

    const cString = (pointer) => {
        refreshViews();
        let end = pointer;
        while (bytes[end] !== 0) {
            end += 1;
        }
        return textAt(pointer, end - pointer);
    };

    const compile = (type, source) => {
        const shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
            showFailure("a shader failed to compile: " + gl.getShaderInfoLog(shader));
        }
        return shader;
    };

    const web_gl_program = (index, vertex, vertexLength, fragment, fragmentLength) => {
        const made = gl.createProgram();
        gl.attachShader(made, compile(gl.VERTEX_SHADER, textAt(vertex, vertexLength)));
        gl.attachShader(made, compile(gl.FRAGMENT_SHADER, textAt(fragment, fragmentLength)));
        gl.linkProgram(made);
        if (!gl.getProgramParameter(made, gl.LINK_STATUS)) {
            showFailure("shaders failed to link: " + gl.getProgramInfoLog(made));
        }
        const block = gl.getUniformBlockIndex(made, "Common");
        if (block !== gl.INVALID_INDEX) {
            gl.uniformBlockBinding(made, block, COMMON_BINDING);
        }
        const uniforms = {};
        for (const name of PROGRAM_UNIFORMS[index]) {
            uniforms[name] = gl.getUniformLocation(made, name);
        }
        programs[index] = {made, uniforms};
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
    gl.enableVertexAttribArray(2);
    gl.vertexAttribPointer(2, 2, gl.UNSIGNED_SHORT, false, HUD_VERTEX_BYTES, HUD_TEXEL_OFFSET);
    gl.bindVertexArray(emptyVertices);
    let atlasTexture = null;

    const commonBuffer = gl.createBuffer();
    gl.bindBuffer(gl.UNIFORM_BUFFER, commonBuffer);
    gl.bufferData(gl.UNIFORM_BUFFER, COMMON_BUFFER_BYTES, gl.DYNAMIC_DRAW);
    gl.bindBufferBase(gl.UNIFORM_BUFFER, COMMON_BINDING, commonBuffer);

    let faceTexture = null;
    let faceRows = 0;
    const copyFramebuffer = gl.createFramebuffer();
    const geometryFramebuffer = gl.createFramebuffer();
    const overlayFramebuffer = gl.createFramebuffer();
    let targets = [];
    let targetWidth = 0;
    let targetHeight = 0;

    const makeFaceTexture = (rows) => {
        const texture = gl.createTexture();
        gl.activeTexture(gl.TEXTURE0 + UNIT_FACES);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RG32UI, FACE_TEXTURE_WIDTH, rows);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        return texture;
    };

    const rowsFor = (capacity) => Math.ceil(capacity / FACE_TEXTURE_WIDTH);

    const makeTarget = (format, attachment, framebuffers) => {
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
    };

    const makeTargets = (width, height) => {
        for (const texture of targets) {
            gl.deleteTexture(texture);
        }
        targets = [];
        targetWidth = width;
        targetHeight = height;
        gl.activeTexture(gl.TEXTURE0 + UNIT_IMAGE);
        makeTarget(gl.SRGB8_ALPHA8, gl.COLOR_ATTACHMENT0, [geometryFramebuffer, overlayFramebuffer]);
        gl.activeTexture(gl.TEXTURE0 + UNIT_GLOW);
        makeTarget(gl.R8, gl.COLOR_ATTACHMENT1, [geometryFramebuffer]);
        gl.activeTexture(gl.TEXTURE0 + UNIT_DEPTH);
        makeTarget(gl.DEPTH_COMPONENT32F, gl.DEPTH_ATTACHMENT, [geometryFramebuffer]);
        gl.bindFramebuffer(gl.FRAMEBUFFER, geometryFramebuffer);
        gl.drawBuffers([gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1]);
        if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
            showFailure("the geometry framebuffer is incomplete");
        }
        gl.bindFramebuffer(gl.FRAMEBUFFER, overlayFramebuffer);
        gl.drawBuffers([gl.COLOR_ATTACHMENT0]);
    };

    const web_gl_setup = (pixels, size, mips, layers, faceCapacity) => {
        refreshViews();
        const voxels = programs[PROGRAM_VOXELS];
        gl.useProgram(voxels.made);
        gl.uniform1i(voxels.uniforms.face_texture, UNIT_FACES);
        gl.uniform1i(voxels.uniforms.textures, UNIT_TEXTURES);
        const fog = programs[PROGRAM_FOG];
        gl.useProgram(fog.made);
        gl.uniform1i(fog.uniforms.depth_input, UNIT_DEPTH);
        gl.uniform1i(fog.uniforms.glow_input, UNIT_GLOW);
        const present = programs[PROGRAM_PRESENT];
        gl.useProgram(present.made);
        gl.uniform1i(present.uniforms.image, UNIT_IMAGE);
        const hud = programs[PROGRAM_HUD];
        gl.useProgram(hud.made);
        gl.uniform1i(hud.uniforms.glyph_atlas, UNIT_ATLAS);
        gl.activeTexture(gl.TEXTURE0 + UNIT_TEXTURES);
        gl.bindTexture(gl.TEXTURE_2D_ARRAY, gl.createTexture());
        gl.texStorage3D(gl.TEXTURE_2D_ARRAY, mips, gl.SRGB8_ALPHA8, size, size, layers);
        let offset = pixels;
        for (let mip = 0; mip < mips; mip += 1) {
            const side = size >> mip;
            gl.texSubImage3D(gl.TEXTURE_2D_ARRAY, mip, 0, 0, 0, side, side, layers, gl.RGBA, gl.UNSIGNED_BYTE, bytes, offset);
            offset += side * side * TEXEL_BYTES * layers;
        }
        gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.texParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.REPEAT);
        faceRows = rowsFor(faceCapacity);
        faceTexture = makeFaceTexture(faceRows);
        makeTargets(canvas.width, canvas.height);
    };

    const web_gl_grow_faces = (capacity) => {
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
    };

    const web_gl_upload_faces = (offset, count, faces) => {
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
    };

    const web_gl_begin = (uniforms, count, red, green, blue) => {
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
    };

    const web_gl_voxels = (chunks, count, dimension, cellRatio, glowing, unseen, framedMaterial) => {
        refreshViews();
        const voxels = programs[PROGRAM_VOXELS];
        const uniforms = voxels.uniforms;
        const transformUniform = uniforms["current_draw.transform"];
        const reversedUniform = uniforms["current_draw.reversed"];
        gl.useProgram(voxels.made);
        gl.activeTexture(gl.TEXTURE0 + UNIT_FACES);
        gl.bindTexture(gl.TEXTURE_2D, faceTexture);
        gl.uniform1ui(uniforms.dimension, dimension);
        gl.uniform1f(uniforms.cell_ratio, cellRatio);
        gl.uniform1uiv(uniforms.glowing_materials, words, glowing >>> 2, MATERIAL_WORDS);
        gl.uniform1uiv(uniforms.unseen_materials, words, unseen >>> 2, MATERIAL_WORDS);
        gl.uniform1ui(uniforms.framed_material, framedMaterial);
        gl.enable(gl.CULL_FACE);
        gl.cullFace(gl.BACK);
        gl.frontFace(gl.CW);
        let reversed = -1;
        let record = chunks >>> 2;
        for (let index = 0; index < count; index += 1) {
            gl.uniformMatrix4fv(transformUniform, false, floats, record, MATRIX_WORDS);
            const flipped = floats[record + MATRIX_WORDS + 2];
            if (flipped !== reversed) {
                gl.uniform4f(reversedUniform, flipped, flipped, flipped, flipped);
                reversed = flipped;
            }
            gl.drawArrays(gl.TRIANGLES, words[record + MATRIX_WORDS], words[record + MATRIX_WORDS + 1]);
            record += CHUNK_RECORD_WORDS;
        }
        gl.disable(gl.CULL_FACE);
    };

    const web_gl_highlight = (model, low, high) => {
        refreshViews();
        const highlight = programs[PROGRAM_HIGHLIGHT];
        const lowAt = low >>> 2;
        const highAt = high >>> 2;
        gl.useProgram(highlight.made);
        gl.depthMask(false);
        gl.uniformMatrix4fv(highlight.uniforms.model, false, floats, model >>> 2, MATRIX_WORDS);
        gl.uniform4f(highlight.uniforms.low, floats[lowAt], floats[lowAt + 1], floats[lowAt + 2], 0);
        gl.uniform4f(highlight.uniforms.high, floats[highAt], floats[highAt + 1], floats[highAt + 2], 0);
        gl.drawArrays(gl.LINES, 0, CUBE_EDGE_VERTICES);
        gl.depthMask(true);
    };

    const web_gl_marker = (model, half, color) => {
        refreshViews();
        const marker = programs[PROGRAM_MARKER];
        gl.useProgram(marker.made);
        gl.uniformMatrix4fv(marker.uniforms.model, false, floats, model >>> 2, MATRIX_WORDS);
        gl.uniform1f(marker.uniforms.half_side, half);
        gl.uniform1ui(marker.uniforms.marker_color, color);
        gl.drawArrays(gl.TRIANGLES, 0, CUBE_VERTICES);
    };

    const web_gl_finish = (widthOverHeight, hud, hudCount) => {
        refreshViews();
        gl.bindFramebuffer(gl.FRAMEBUFFER, overlayFramebuffer);
        gl.disable(gl.DEPTH_TEST);
        gl.depthMask(false);
        gl.colorMask(true, true, true, false);
        gl.enable(gl.BLEND);
        gl.blendEquation(gl.FUNC_ADD);
        gl.blendFunc(gl.ONE_MINUS_SRC_ALPHA, gl.SRC_ALPHA);
        gl.useProgram(programs[PROGRAM_FOG].made);
        gl.drawArrays(gl.TRIANGLES, 0, FULLSCREEN_VERTICES);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        const crosshair = programs[PROGRAM_CROSSHAIR];
        gl.useProgram(crosshair.made);
        gl.uniform1f(crosshair.uniforms.width_over_height, widthOverHeight);
        gl.drawArrays(gl.TRIANGLES, 0, CROSSHAIR_VERTICES);
        if (hudCount > 0) {
            gl.useProgram(programs[PROGRAM_HUD].made);
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
        gl.useProgram(programs[PROGRAM_PRESENT].made);
        gl.drawArrays(gl.TRIANGLES, 0, FULLSCREEN_VERTICES);
    };

    const web_gl_atlas = (pixels, width, height) => {
        refreshViews();
        gl.activeTexture(gl.TEXTURE0 + UNIT_ATLAS);
        if (atlasTexture === null) {
            atlasTexture = gl.createTexture();
            gl.bindTexture(gl.TEXTURE_2D, atlasTexture);
            gl.texStorage2D(gl.TEXTURE_2D, 1, gl.R8, width, height);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        }
        gl.bindTexture(gl.TEXTURE_2D, atlasTexture);
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
        gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, width, height, gl.RED, gl.UNSIGNED_BYTE, bytes, pixels);
    };

    const web_now = () => performance.now();
    const web_status = (text) => showStatus(cString(text));
    const web_fail = (text) => showFailure(cString(text));

    const fd_write = (descriptor, vectors, vectorCount, written) => {
        refreshViews();
        let text = "";
        let total = 0;
        for (let index = 0; index < vectorCount; index += 1) {
            const vector = (vectors >>> 2) + index * CIOVEC_WORDS;
            text += textAt(words[vector], words[vector + 1]);
            total += words[vector + 1];
        }
        console.error(text);
        words[written >>> 2] = total;
        return WASI_ERRNO_SUCCESS;
    };
    const fd_close = (descriptor) => WASI_ERRNO_BADF;
    const fd_seek = (descriptor, offset, whence, position) => WASI_ERRNO_BADF;

    const imports = {env: {web_now, web_status, web_fail, web_gl_program, web_gl_setup, web_gl_grow_faces, web_gl_upload_faces, web_gl_begin, web_gl_voxels, web_gl_highlight, web_gl_marker, web_gl_finish, web_gl_atlas}, wasi_snapshot_preview1: {fd_write, fd_close, fd_seek}};
    const game = {gl, imports, makeTargets, exports: null};
    game.attach = (instance) => {
        memory = instance.exports.memory;
        game.exports = instance.exports;
        game.exports._initialize();
    };
    return game;
};

const createGame = (canvas, showStatus, showFailure, contextOptions) => {
    const gl = canvas.getContext("webgl2", contextOptions);
    if (gl === null) {
        showFailure("this browser or machine has no WebGL2, which mined needs to draw");
        return null;
    } else {
        return gameOn(canvas, gl, showStatus, showFailure);
    }
};

const resizeCanvas = (canvas) => {
    const scale = window.devicePixelRatio;
    const width = Math.max(1, Math.floor(canvas.clientWidth * scale));
    const height = Math.max(1, Math.floor(canvas.clientHeight * scale));
    const changed = canvas.width !== width || canvas.height !== height;
    canvas.width = width;
    canvas.height = height;
    return changed;
};

const renderRadiusFromAddress = () => {
    const asked = parseFloat(new URLSearchParams(location.search).get("radius"));
    if (asked > 0) {
        return Math.min(asked, MOST_RENDER_RADIUS);
    } else {
        return DEFAULT_RENDER_RADIUS;
    }
};

const wasmFromBase64 = (text) => {
    const binary = atob(text);
    const wasmBytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
        wasmBytes[index] = binary.charCodeAt(index);
    }
    return wasmBytes;
};

const failuresGoTo = (failure) => {
    const state = {failed: false};
    state.show = (text) => {
        state.failed = true;
        failure.textContent = text;
        failure.hidden = false;
    };
    window.addEventListener("error", (event) => state.show("the game stopped: " + event.message));
    window.addEventListener("unhandledrejection", (event) => state.show("the game stopped: " + event.reason));
    return state;
};
