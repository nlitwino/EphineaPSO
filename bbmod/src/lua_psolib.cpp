﻿#include "lua_psolib.h"

#include <Windows.h>
#include "sol.hpp"

#include "lua_hooks.h"
#include "luastate.h"
#include "log.h"
#include "wrap_imgui_impl.h"

static int wrap_exceptions(lua_State *L, lua_CFunction f);
static int psolua_print(lua_State *L);
static std::string psolualib_read_cstr(int memory_address, int len = 2048);
static std::string psolualib_read_wstr(int memory_address, int len = 1024);
static sol::table psolualib_read_mem(sol::table t, int memory_address, int len);
static std::string psolualib_read_mem_str(int memory_address, int len = 2048);
static sol::table psolualib_list_addons();

bool psolua_initialize_on_next_frame = false;

DWORD g_PSOBaseAddress;

// Catch C++ exceptions and convert them to Lua error messages.
// Customize as needed for your own exception classes.
static int wrap_exceptions(lua_State *L, lua_CFunction f) {
    try {
        return f(L);  // Call wrapped function and return result.
    }
    catch (const char *s) {  // Catch and convert exceptions.
        lua_pushstring(L, s);
    }
    catch (std::exception& e) {
        lua_pushstring(L, e.what());
    }
    catch (...) {
        lua_pushliteral(L, "caught (...)");
    }
    return lua_error(L);  // Rethrow as a Lua error.
}

std::string psolualib_error_handler(std::string msg) {
    sol::state_view lua(g_LuaState);

    try {
        g_log << "uncaught error: " << msg << std::endl;
        std::string traceback = lua["debug"]["traceback"]();
        g_log << traceback << std::endl;
        psoluah_UnhandledError(msg);
    }
    catch (...) {
        // do nothing
    }
    return msg;
}

static int psolua_print(lua_State *L) {
    sol::state_view lua(L);
    int nargs = lua_gettop(L);
    std::string coalesce;

    for (int i = 1; i <= nargs; i++) {
        sol::object o = sol::stack::get<sol::object>(lua, i);
        if (i > 1) g_log << "\t";
        if (i > 1) coalesce += "\t";
        std::string out = lua["tostring"](o);
        coalesce += out;
    }
    g_log << coalesce << std::endl;
    psoluah_Log(coalesce);

    return 0;
}

static void psolualib_set_sleep_hack_enabled(bool enabled) {
    uint8_t* location = (uint8_t*)(0x0042C47E + g_PSOBaseAddress);
    if (enabled) {
        location[1] = 0x01;
    }
    else {
        location[1] = 0x00;
    }
}

template <typename T> std::function<T(int)> read_t(void) {
    auto pid = GetCurrentProcess();
    return [=](int addr) {
        char buf[sizeof(T)];
        SIZE_T read;
        if (!ReadProcessMemory(pid, (LPCVOID)addr, (LPVOID)buf, sizeof(T), &read)) {
            throw "ReadProcessMemory error";
        }
        return *(T*)buf;
    };
}

void psolua_store_fpu_state(struct FPUSTATE& fpustate) {
    char* state = fpustate.state;
    __asm {
        mov ebx, state
        fsave [ebx]
    }
}

void psolua_restore_fpu_state(struct FPUSTATE& fpustate) {
    char* state = fpustate.state;
    __asm {
        mov ebx, state
        frstor [ebx]
    }
}

void psolua_load_library(lua_State * L) {
    sol::state_view lua(L);

    lua["print"] = psolua_print;
    sol::table psoTable = lua.create_named_table("pso");

    psoTable["error_handler"] = psolualib_error_handler;
    psoTable["reload"] = []() { psolua_initialize_on_next_frame = true; };

    psoTable["read_i8"] = read_t<int8_t>();
    psoTable["read_i16"] = read_t<int16_t>();
    psoTable["read_i32"] = read_t<int32_t>();
    psoTable["read_i64"] = read_t<int64_t>();
    psoTable["read_u8"] = read_t<uint8_t>();
    psoTable["read_u16"] = read_t<uint16_t>();
    psoTable["read_u32"] = read_t<uint32_t>();
    psoTable["read_u64"] = read_t<uint64_t>();
    psoTable["read_f32"] = read_t<float>();
    psoTable["read_f64"] = read_t<double>();
    psoTable["read_cstr"] = psolualib_read_cstr;
    psoTable["read_wstr"] = psolualib_read_wstr;
    psoTable["read_mem"] = psolualib_read_mem;
    psoTable["read_mem_str"] = psolualib_read_mem_str;
    psoTable["set_sleep_hack_enabled"] = psolualib_set_sleep_hack_enabled;
    psoTable["base_address"] = g_PSOBaseAddress;
    psoTable["list_addon_directories"] = psolualib_list_addons;
    psoTable["log_items"] = lua.create_table();
    lua["print"]("PSOBB Base address is ", g_PSOBaseAddress);

    // Exception handling
    lua_pushlightuserdata(L, (void*)wrap_exceptions);
    luaJIT_setmode(L, -1, LUAJIT_MODE_WRAPCFUNC | LUAJIT_MODE_ON);
    lua_pop(L, 1);

    // ImGui library
    luaopen_imgui(L);
}

void psolua_initialize_state(void) {
    if (g_LuaState != nullptr) {
        lua_close(g_LuaState);
        g_LuaState = nullptr;
    }
    g_LuaState = luaL_newstate();

    if (!g_LuaState) {
        MessageBoxA(nullptr, "LuaJit new state failed.", "Lua error", 0);
        exit(1);
    }

    g_lualog.Clear();
    g_log << "Initializing Lua state" << std::endl;

    sol::state_view lua(g_LuaState);

    luaL_openlibs(g_LuaState);
    psolua_load_library(g_LuaState);
    sol::protected_function_result res = lua.do_file("addons/init.lua");
    if (res.status() != sol::call_status::ok) {
        sol::error what = res;
        g_log << (int)res.status() << std::endl;
        g_log << what.what() << std::endl;
        lua["pso"]["error_handler"](what);
        MessageBoxA(nullptr, "Failed to load init.lua", "Lua error", 0);
        exit(1);
    }
    psoluah_Init();

    psolua_initialize_on_next_frame = false;
}

static std::string psolualib_read_cstr(int memory_address, int len) {
    char buf[8192];
    memset(buf, 0, len);
    SIZE_T read;
    auto pid = GetCurrentProcess();
    if (!ReadProcessMemory(pid, (LPCVOID)memory_address, buf, len, &read)) {
        throw "ReadProcessMemory error";
    }
    return buf;
}

static std::string psolualib_read_wstr(int memory_address, int len) {
    char buf[8192];
    char buf2[8192];
    memset(buf, 0, len * 2);
    memset(buf2, 0, len * 2);
    SIZE_T read;
    auto pid = GetCurrentProcess();
    if (!ReadProcessMemory(pid, (LPCVOID)memory_address, buf, len * 2, &read)) {
        throw "ReadProcessMemory error";
    }
    if (!WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)buf, len, buf2, 8192, nullptr, nullptr)) {
        throw "invalid utf-16 string";
    }
    return buf2;
}

static sol::table psolualib_read_mem(sol::table t, int memory_address, int len) {
    sol::state_view lua(g_LuaState);
    unsigned char buf[8192];
    memset(buf, 0, len);
    SIZE_T read;
    auto pid = GetCurrentProcess();
    if (len < 0) {
        throw "length must be greater than 0";
    }
    if (!ReadProcessMemory(pid, (LPCVOID)memory_address, buf, len, &read)) {
        throw "ReadProcessMemory error";
    }
    for (int i = 0; i < len; i++) {
        t.add((int)buf[i]);
    }
    return t;
}

static std::string psolualib_read_mem_str(int memory_address, int len) {
    char buf[8192];
    memset(buf, 0, len);
    SIZE_T read;
    auto pid = GetCurrentProcess();
    if (!ReadProcessMemory(pid, (LPCVOID)memory_address, buf, len, &read)) {
        throw "ReadProcessMemory error";
    }
    return std::string(buf, len);
}

static sol::table psolualib_list_addons() {
    sol::state_view lua(g_LuaState);

    HANDLE hFind;
    WIN32_FIND_DATA find;

    sol::table ret = lua.create_table();

    hFind = FindFirstFileA("addons/*", &find);
    do {
        std::string filename(find.cFileName);
        if (filename == "..") continue;
        if (filename == ".") continue;
        if (find.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            ret.add(filename);
        }
    } while (FindNextFileA(hFind, &find));

    return ret;
}
