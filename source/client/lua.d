module client.lua;

import bindings.lua : luaL_newstate, luaL_openselectedlibs, luaL_traceback, lua_CFunction, lua_State, lua_getglobal, lua_pushcclosure, lua_pushlightuserdata, lua_pushlstring, lua_pushnil, lua_setfield, lua_setglobal, lua_settop, lua_tolstring, lua_type;
import common.array : Array;
import common.names : ENUM_NAMES;

enum int LUA_REGISTRY = -(int.max / 2 + 1000);
enum int LUA_FIRST_UPVALUE = LUA_REGISTRY - 1;
enum int LUA_SECOND_UPVALUE = LUA_REGISTRY - 2;
enum int LUA_NO_REF = -2;
enum int LUA_TOP = -1;
enum int LUA_BELOW_TOP = -2;
enum int LUA_TRACEBACK_LEVEL = 1;
enum int LUA_STATUS_OK = 0;
enum int LUA_TYPE_TABLE = 5;
enum int LUA_TYPE_FUNCTION = 6;
enum int LUA_LIBRARY_BASE = 1 << 0;
enum int LUA_LIBRARY_PACKAGE = 1 << 1;
enum int LUA_LIBRARY_COROUTINE = 1 << 2;
enum int LUA_LIBRARY_MATH = 1 << 5;
enum int LUA_LIBRARY_STRING = 1 << 7;
enum int LUA_LIBRARY_TABLE = 1 << 8;
enum int LUA_LIBRARY_UTF8 = 1 << 9;
enum int LUA_SAFE_LIBRARIES = LUA_LIBRARY_BASE | LUA_LIBRARY_PACKAGE | LUA_LIBRARY_COROUTINE | LUA_LIBRARY_MATH | LUA_LIBRARY_STRING | LUA_LIBRARY_TABLE | LUA_LIBRARY_UTF8;
enum int SELF = 1;
enum int TRACEBACK_INDEX = 1;
enum string MODULE_PATTERN = "?.lua";
enum size_t LUA_NAME_CAPACITY = 32;
enum char LUA_NAME_SEPARATOR = '_';

alias LuaFunction = extern (C) int function(lua_State*);

struct LuaName {
    char[LUA_NAME_CAPACITY] text;
    size_t length;

    static LuaName fromMember(string member) {
        LuaName name;
        foreach (c; member) {
            if (isUpperCase(c)) {
                name.text[name.length] = LUA_NAME_SEPARATOR;
                name.text[name.length + 1] = lowerCase(c);
                name.length += 2;
            } else {
                name.text[name.length] = c;
                name.length += 1;
            }
        }
        return name;
    }

    const(char)[] slice() const return {
        return text[0 .. length];
    }
}

struct LuaLookup(E) {
    E value;
    bool isFound;

    static LuaLookup fromName(const(char)[] name) {
        uint index = 0;
        while (index < ENUM_NAMES!E.length && LuaName.fromMember(ENUM_NAMES!E[index]).slice() != name) {
            index += 1;
        }
        if (index < ENUM_NAMES!E.length) {
            return LuaLookup(cast(E) index, true);
        } else {
            return LuaLookup(E.init, false);
        }
    }
}

bool isUpperCase(char c) {
    return c >= 'A' && c <= 'Z';
}

char lowerCase(char c) {
    return cast(char)(c - 'A' + 'a');
}

void pushLuaName(E)(lua_State* lua, E value) {
    LuaName name = LuaName.fromMember(ENUM_NAMES!E[value]);
    lua_pushlstring(lua, name.text.ptr, name.length);
}

bool isNoneOrNil(lua_State* lua, int index) {
    return lua_type(lua, index) <= 0;
}

lua_State* newSafeState() {
    lua_State* lua = luaL_newstate();
    luaL_openselectedlibs(lua, LUA_SAFE_LIBRARIES, 0);
    lua_pushnil(lua);
    lua_setglobal(lua, "print");
    lua_pushnil(lua);
    lua_setglobal(lua, "warn");
    return lua;
}

void registerMethod(lua_State* lua, void* host, const(char)* name, LuaFunction fn) {
    lua_pushlightuserdata(lua, host);
    lua_pushcclosure(lua, cast(lua_CFunction) fn, 1);
    lua_setfield(lua, LUA_BELOW_TOP, name);
}

void setPackagePath(lua_State* lua, const(char)[] scriptPath) {
    Array!char searchPath;
    foreach_reverse (i, c; scriptPath) {
        if (c == '/') {
            searchPath.appendAll(scriptPath[0 .. i + 1]);
            searchPath.appendAll(MODULE_PATTERN ~ ";");
        }
    }
    searchPath.appendAll(MODULE_PATTERN);
    lua_getglobal(lua, "package");
    lua_pushlstring(lua, searchPath.ptr, searchPath.length);
    lua_setfield(lua, LUA_BELOW_TOP, "path");
    lua_settop(lua, LUA_BELOW_TOP);
    searchPath.release();
}

extern (C) int luaTraceback(lua_State* lua) {
    luaL_traceback(lua, lua, lua_tolstring(lua, 1, null), LUA_TRACEBACK_LEVEL);
    return 1;
}
