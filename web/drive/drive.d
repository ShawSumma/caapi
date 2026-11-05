module drive;

import core.thread : Thread;
import core.time : msecs;
import std.base64 : Base64;
import std.conv : to;
import std.exception : enforce;
import std.file : getcwd, write;
import std.json : JSONType, JSONValue, parseJSON;
import std.socket : InternetAddress, Socket, TcpSocket;
import std.stdio : writefln, writeln;
import std.string : indexOf;

enum ushort MARIONETTE_PORT = 2828;
enum string ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf";
enum string SHOT_DIRECTORY = ".firefox-check/";
enum int CONNECT_ATTEMPTS = 60;

struct Marionette {
    Socket socket;
    char[] pending;
    int nextId = 1;

    static Marionette connect() {
        Marionette client;
        foreach (attempt; 0 .. CONNECT_ATTEMPTS) {
            try {
                client.socket = new TcpSocket(new InternetAddress("127.0.0.1", MARIONETTE_PORT));
                client.receive();
                return client;
            } catch (Exception) {
                Thread.sleep(500.msecs);
            }
        }
        throw new Exception("Firefox never opened its Marionette port");
    }

    string receive() {
        while (true) {
            ptrdiff_t colon = pending.indexOf(':');
            if (colon >= 0) {
                size_t length = pending[0 .. colon].to!size_t;
                if (pending.length >= colon + 1 + length) {
                    string message = pending[colon + 1 .. colon + 1 + length].idup;
                    pending = pending[colon + 1 + length .. $];
                    return message;
                }
            }
            char[65536] chunk;
            ptrdiff_t got = socket.receive(chunk[]);
            enforce(got > 0, "Firefox closed the connection");
            pending ~= chunk[0 .. got];
        }
    }

    JSONValue call(string name, JSONValue parameters) {
        JSONValue request = JSONValue([JSONValue(0), JSONValue(nextId), JSONValue(name), parameters]);
        nextId += 1;
        string text = request.toString();
        string framed = text.length.to!string ~ ":" ~ text;
        socket.send(framed);
        JSONValue reply = parseJSON(receive());
        enforce(reply[2].type == JSONType.null_, name ~ " failed: " ~ reply[2].toString());
        return reply[3];
    }

    string script(string source) {
        JSONValue parameters = ["script": JSONValue(source), "args": JSONValue(cast(JSONValue[]) [])];
        JSONValue result = call("WebDriver:ExecuteScript", parameters)["value"];
        if (result.type == JSONType.string) {
            return result.str;
        } else {
            return result.toString();
        }
    }

    void shot(string name) {
        JSONValue parameters = ["full": JSONValue(false), "hash": JSONValue(false)];
        string encoded = call("WebDriver:TakeScreenshot", parameters)["value"].str;
        write(SHOT_DIRECTORY ~ name ~ ".png", Base64.decode(encoded));
    }

    void perform(JSONValue[] sources) {
        JSONValue parameters = ["actions": JSONValue(sources)];
        call("WebDriver:PerformActions", parameters);
    }

    void click(int button) {
        JSONValue[] actions = [
            JSONValue(["type": JSONValue("pointerMove"), "x": JSONValue(640), "y": JSONValue(360), "duration": JSONValue(0), "origin": JSONValue("viewport")]),
            JSONValue(["type": JSONValue("pointerDown"), "button": JSONValue(button)]),
            JSONValue(["type": JSONValue("pointerUp"), "button": JSONValue(button)]),
        ];
        perform([pointer(actions)]);
    }

    void hold(string key, int milliseconds) {
        JSONValue[] actions = [
            JSONValue(["type": JSONValue("keyDown"), "value": JSONValue(key)]),
            JSONValue(["type": JSONValue("pause"), "duration": JSONValue(milliseconds)]),
            JSONValue(["type": JSONValue("keyUp"), "value": JSONValue(key)]),
        ];
        JSONValue source = ["type": JSONValue("key"), "id": JSONValue("keyboard"), "actions": JSONValue(actions)];
        perform([source]);
    }

    void moveBy(int dx, int dy) {
        JSONValue[] actions = [
            JSONValue(["type": JSONValue("pointerMove"), "x": JSONValue(dx), "y": JSONValue(dy), "duration": JSONValue(200), "origin": JSONValue("pointer")]),
        ];
        perform([pointer(actions)]);
    }

    string report(string label) {
        string state = script("return JSON.stringify({status: document.getElementById('status').textContent, failure: document.getElementById('failure').textContent, locked: document.pointerLockElement !== null, title: document.title})");
        writefln("%s: %s", label, state);
        return state;
    }
}

JSONValue pointer(JSONValue[] actions) {
    JSONValue parameters = ["pointerType": JSONValue("mouse")];
    return JSONValue(["type": JSONValue("pointer"), "id": JSONValue("mouse"), "parameters": parameters, "actions": JSONValue(actions)]);
}

int main(string[] arguments) {
    string query = "";
    if (arguments.length > 1) {
        query = arguments[1];
    }
    Marionette browser = Marionette.connect();
    JSONValue none = parseJSON("{}");
    browser.call("WebDriver:NewSession", none);
    browser.call("WebDriver:SetWindowRect", parseJSON(`{"x":0,"y":0,"width":1280,"height":800}`));
    JSONValue page = ["url": JSONValue("file://" ~ getcwd() ~ "/mined.html" ~ query)];
    browser.call("WebDriver:Navigate", page);
    browser.report("loaded");
    Thread.sleep(6000.msecs);
    browser.report("after 6s, nothing pressed");
    browser.shot("play-start");
    browser.click(0);
    Thread.sleep(500.msecs);
    browser.report("clicked to capture");
    browser.hold("w", 2000);
    browser.report("held W");
    browser.shot("play-walked");
    browser.moveBy(200, 150);
    Thread.sleep(300.msecs);
    browser.shot("play-looked");
    browser.click(0);
    Thread.sleep(500.msecs);
    browser.shot("play-broke");
    browser.click(2);
    Thread.sleep(500.msecs);
    browser.shot("play-placed");
    browser.hold("v", 50);
    browser.report("pressed V");
    browser.hold("]", 50);
    Thread.sleep(3000.msecs);
    browser.report("pressed ]");
    browser.shot("play-next-world");
    browser.script("document.exitPointerLock(); return true");
    Thread.sleep(500.msecs);
    browser.report("released the mouse");
    browser.hold("w", 300);
    browser.report("W while released");
    browser.call("WebDriver:SetWindowRect", parseJSON(`{"x":0,"y":0,"width":900,"height":600}`));
    Thread.sleep(2000.msecs);
    browser.report("resized");
    writefln("canvas: %s", browser.script("const c = document.getElementById('game'); return c.width + 'x' + c.height"));
    browser.shot("play-resized");
    browser.call("Marionette:Quit", none);
    writeln("driven to the end");
    return 0;
}
