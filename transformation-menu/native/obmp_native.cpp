// obmp_native — native core of ConsoleBridge for OblivionMP (Oblivion Remastered).
//
// Phase 1:
//   * recognition of the game build (PE timestamp + SizeOfImage) and AOB signatures;
//   * per-frame hook on the TES thread: the rel32 of the call is rewritten to the empty trace marker
//     of the END of the frame inside "Oblivion Main loop" (game RVA 0x65d3657). ReadyM uses the START
//     of the frame (0x65d3278), which is not touched here;
//   * queue of jobs run on the TES thread, protected by SEH.
//
// C API (all __cdecl, x64): see the extern "C" block at the bottom.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

namespace {

// ----------------------------------------------------------------------------------------------
// Constants of the reference build (see oblivion_mp/VERSIONI_RIFERIMENTO.md)
// ----------------------------------------------------------------------------------------------
constexpr DWORD kRefTimestamp = 0xF19077A4;
constexpr DWORD kRefSizeOfImage = 0x09E1E000;

struct Signature {
    const char* name;
    uint32_t expected_rva;  // where it is located in the reference build (fast path)
    const char* pattern;    // hex bytes, "??" = any
    int32_t result_offset;  // offset from the first byte of the signature to the point of interest
};

// End of frame of the main loop: if (!quit) { call marker; jmp loop_head }
constexpr Signature kSigFrameEndSite = {
    "FrameEndMarkerCall", 0x65d3641,
    "48 8B 05 ?? ?? ?? ?? 80 38 00 75 ?? 48 8B 40 30 80 78 09 00 75 ?? E8 ?? ?? ?? ?? 90 E9 ?? ?? ?? ??",
    0x16};

// VAltarCommands::ExecuteCommand(void* unused, UObject* target, std::string cmd /* by value */).
// Decompiled in REA (mini-PE, 2026-11-15): if target != null it converts it to the TES ref the command acts on;
// it builds a local Script, SetText(cmd), compiles and runs it; then DESTROYS
// the string (passed by value: the >15 char buffer is freed with the game's FMemory::Free).
constexpr Signature kSigExecuteCommand = {
    "VAltarCommands::ExecuteCommand", 0x6555280,
    "48 89 5C 24 08 48 89 74 24 20 57 48 81 EC D0 00 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 84 24 "
    "C8 00 00 00 49 8B D8 48",
    0};

// game's operator delete = FMemory::Free: `mov rcx,[rip+GMalloc]` at +0x0D. Needed for the GMalloc global
// to allocate long command buffers from the same heap that will free them.
constexpr Signature kSigGameOperatorDelete = {
    "operator delete (GMalloc)", 0xe26500,
    "48 85 C9 74 ?? 53 48 83 EC 20 48 8B D9 48 8B 0D ?? ?? ?? ?? 48 85 C9 75 ?? E8 ?? ?? ?? ?? 48 8B 0D "
    "?? ?? ?? ?? 48 8B 01 48 8B D3 FF 50 48 48 83 C4 20 5B C3",
    0x0D};

// FMalloc vtable (UE5): +0x28 Malloc(size, align), +0x48 Free(ptr). Verified in-game:
// 604 inline calls to +0x48 after GMalloc is loaded, and Malloc(0x80, 0) at +0x28.
constexpr size_t kFMallocMallocSlot = 0x28 / 8;
constexpr size_t kFMallocFreeSlot = 0x48 / 8;

// MSVC x64 std::string: 16-byte SSO buffer, then size and capacity.
struct MsvcString {
    union {
        char buf[16];
        char* ptr;
    };
    size_t size;
    size_t capacity;
};
static_assert(sizeof(MsvcString) == 32, "MSVC std::string layout");

// Above 4095 bytes MSVC uses the aligned "big block" format: we avoid it.
constexpr size_t kMaxCommandLength = 0xFFE;

// ----------------------------------------------------------------------------------------------
// State
// ----------------------------------------------------------------------------------------------
using LogFn = void(__cdecl*)(int level, const char* utf8);
using JobFn = void(__cdecl*)(void* ctx);
using MarkerFn = void(__cdecl*)();

enum Status : uint32_t {
    kStatusInitialized = 1u << 0,
    kStatusBuildKnown = 1u << 1,
    kStatusHookInstalled = 1u << 2,
    kStatusTesThreadSeen = 1u << 3,
    kStatusDisabled = 1u << 4,       // switch: jobs are not executed
    kStatusExecResolved = 1u << 5,   // ExecuteCommand found (Phase 2)
    kStatusChainedForeign = 1u << 6, // the site was already hooked by others: we chained after it
};

LogFn g_log = nullptr;
uint8_t* g_base = nullptr;
DWORD g_imageSize = 0;
uint8_t* g_textStart = nullptr;
size_t g_textSize = 0;

std::atomic<uint32_t> g_status{0};
std::atomic<uint64_t> g_ticks{0};
std::atomic<uint32_t> g_tesTid{0};
std::atomic<uint64_t> g_jobsRun{0};
std::atomic<uint64_t> g_jobFaults{0};
std::atomic<int> g_inHook{0};

uint8_t* g_site = nullptr;          // address of the hooked E8 instruction
int32_t g_origRel = 0;              // original rel32
int32_t g_ourRel = 0;               // rel32 pointing at our trampoline
MarkerFn g_origTarget = nullptr;    // original target (empty marker or someone else's hook)
uint8_t* g_trampoline = nullptr;
uint8_t* g_execCommand = nullptr;
void** g_gmallocGlobal = nullptr;  // address of the game's GMalloc global variable

using ExecuteCommandFn = void(__fastcall*)(void* unused, void* target, MsvcString* cmd);
using FMallocMallocFn = void*(__fastcall*)(void* self, size_t size, uint32_t align);

// Command outcomes, per ticket. Ring of 256 entries: an older ticket is reported as expired.
enum CommandState : int32_t { kCmdPending = 0, kCmdDone = 1, kCmdFault = 2, kCmdSkipped = 3 };
constexpr uint32_t kResultSlots = 256;
std::atomic<uint32_t> g_nextTicket{1};
std::atomic<uint32_t> g_resultTicket[kResultSlots];
std::atomic<int32_t> g_resultState[kResultSlots];
std::atomic<uint64_t> g_commandsRun{0};

struct CommandJob {
    uint32_t ticket;
    uint32_t length;
    char text[1];  // allocated with length + 1
};

std::mutex g_queueMutex;
std::vector<std::pair<JobFn, void*>> g_queue;

void Log(int level, const char* fmt, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    std::vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (g_log) g_log(level, buf);
    OutputDebugStringA(buf);
    OutputDebugStringA("\n");
}

// ----------------------------------------------------------------------------------------------
// AOB signatures
// ----------------------------------------------------------------------------------------------
struct ParsedSig {
    std::vector<int> bytes;  // -1 = wildcard
};

ParsedSig Parse(const char* pattern) {
    ParsedSig p;
    for (const char* s = pattern; *s;) {
        while (*s == ' ') ++s;
        if (!*s) break;
        if (s[0] == '?') {
            p.bytes.push_back(-1);
            s += (s[1] == '?') ? 2 : 1;
        } else {
            char hex[3] = {s[0], s[1], 0};
            p.bytes.push_back(static_cast<int>(std::strtoul(hex, nullptr, 16)));
            s += 2;
        }
    }
    return p;
}

bool MatchAt(const uint8_t* at, const ParsedSig& p) {
    for (size_t i = 0; i < p.bytes.size(); ++i)
        if (p.bytes[i] >= 0 && at[i] != static_cast<uint8_t>(p.bytes[i])) return false;
    return true;
}

// Returns the resolved address (signature + offset) or nullptr. It first tries the expected RVA, then
// scans all of .text and requires a unique result.
uint8_t* Resolve(const Signature& sig) {
    ParsedSig p = Parse(sig.pattern);
    if (p.bytes.empty() || !g_textStart) return nullptr;
    uint8_t* textEnd = g_textStart + g_textSize;

    uint8_t* fast = g_base + sig.expected_rva;
    if (fast >= g_textStart && fast + p.bytes.size() <= textEnd && MatchAt(fast, p)) {
        Log(1, "[obmp] %s: found at expected RVA 0x%X", sig.name, sig.expected_rva);
        return fast + sig.result_offset;
    }

    size_t anchor = 0;
    while (anchor < p.bytes.size() && p.bytes[anchor] < 0) ++anchor;
    if (anchor == p.bytes.size()) return nullptr;
    const uint8_t first = static_cast<uint8_t>(p.bytes[anchor]);

    uint8_t* found = nullptr;
    int hits = 0;
    for (uint8_t* cur = g_textStart + anchor; cur + (p.bytes.size() - anchor) <= textEnd;) {
        cur = static_cast<uint8_t*>(std::memchr(cur, first, textEnd - cur));
        if (!cur) break;
        uint8_t* start = cur - anchor;
        if (start + p.bytes.size() <= textEnd && MatchAt(start, p)) {
            found = start;
            if (++hits > 1) break;
        }
        ++cur;
    }
    if (hits != 1) {
        Log(3, "[obmp] %s: signature scan found %d matches (need exactly 1)", sig.name, hits);
        return nullptr;
    }
    Log(2, "[obmp] %s: not at expected RVA, found by scan at RVA 0x%llX", sig.name,
        static_cast<unsigned long long>(found - g_base));
    return found + sig.result_offset;
}

// ----------------------------------------------------------------------------------------------
// Job queue and per-frame hook
// ----------------------------------------------------------------------------------------------
// Separate function: __try cannot be used in functions with C++ objects that have destructors.
bool RunJobGuarded(JobFn fn, void* ctx) {
    __try {
        fn(ctx);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

void DrainQueue() {
    std::vector<std::pair<JobFn, void*>> jobs;
    {
        std::lock_guard<std::mutex> lock(g_queueMutex);
        if (g_queue.empty()) return;
        jobs.swap(g_queue);
    }
    const bool disabled = (g_status.load() & kStatusDisabled) != 0;
    for (auto& [fn, ctx] : jobs) {
        if (disabled) continue;
        if (RunJobGuarded(fn, ctx)) {
            g_jobsRun.fetch_add(1);
        } else {
            g_jobFaults.fetch_add(1);
            Log(3, "[obmp] a job raised an exception on the TES thread and was skipped");
        }
    }
}

// Called by the game at every end of frame, on the TES thread, in place of the empty marker.
void __cdecl OnFrameEnd() {
    g_inHook.fetch_add(1);
    if (g_origTarget) g_origTarget();  // chain: original marker or someone else's hook

    uint32_t tid = GetCurrentThreadId();
    uint32_t expected = 0;
    if (g_tesTid.compare_exchange_strong(expected, tid)) {
        g_status.fetch_or(kStatusTesThreadSeen);
    }
    g_ticks.fetch_add(1);
    DrainQueue();
    g_inHook.fetch_sub(1);
}

// Allocates executable memory within ±2 GB of `anchor` (needed so the call's rel32 can reach it).
uint8_t* AllocNear(uint8_t* anchor, size_t size) {
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    const uintptr_t gran = si.dwAllocationGranularity;
    const uintptr_t center = reinterpret_cast<uintptr_t>(anchor);
    const uintptr_t span = 0x7FF00000ull;
    const uintptr_t lo = center > span ? center - span : gran;
    const uintptr_t hi = center + span;
    for (uintptr_t delta = gran; delta < span; delta += gran) {
        for (int dir = 0; dir < 2; ++dir) {
            uintptr_t addr = dir == 0 ? (center - delta) & ~(gran - 1) : (center + delta) & ~(gran - 1);
            if (addr < lo || addr > hi) continue;
            void* p = VirtualAlloc(reinterpret_cast<void*>(addr), size, MEM_RESERVE | MEM_COMMIT,
                                   PAGE_EXECUTE_READWRITE);
            if (p) return static_cast<uint8_t*>(p);
        }
    }
    return nullptr;
}

// Writes a call's rel32 atomically when the 4 bytes fit in one aligned qword.
bool WriteRel32(uint8_t* site, int32_t expectedOld, int32_t newRel) {
    uint8_t* relAddr = site + 1;
    DWORD oldProt = 0;
    if (!VirtualProtect(relAddr, 4, PAGE_EXECUTE_READWRITE, &oldProt)) return false;

    bool ok = false;
    uintptr_t r = reinterpret_cast<uintptr_t>(relAddr);
    uintptr_t q = r & ~uintptr_t(7);
    if (r + 4 <= q + 8) {
        auto* qword = reinterpret_cast<volatile LONG64*>(q);
        const size_t shift = (r - q) * 8;
        for (int attempt = 0; attempt < 16 && !ok; ++attempt) {
            LONG64 cur = *qword;
            int32_t curRel = static_cast<int32_t>((static_cast<uint64_t>(cur) >> shift) & 0xFFFFFFFFull);
            if (curRel != expectedOld) break;
            uint64_t mask = 0xFFFFFFFFull << shift;
            LONG64 next = static_cast<LONG64>((static_cast<uint64_t>(cur) & ~mask) |
                                              (static_cast<uint64_t>(static_cast<uint32_t>(newRel)) << shift));
            ok = InterlockedCompareExchange64(qword, next, cur) == cur;
        }
    } else {
        int32_t cur;
        std::memcpy(&cur, relAddr, 4);
        if (cur == expectedOld) {
            std::memcpy(relAddr, &newRel, 4);
            ok = true;
        }
    }
    VirtualProtect(relAddr, 4, oldProt, &oldProt);
    FlushInstructionCache(GetCurrentProcess(), site, 5);
    return ok;
}

bool InstallFrameHook() {
    uint8_t* site = Resolve(kSigFrameEndSite);
    if (!site) return false;
    if (site[0] != 0xE8) {
        Log(3, "[obmp] hook site at RVA 0x%llX is not a CALL (byte 0x%02X); not hooking",
            static_cast<unsigned long long>(site - g_base), site[0]);
        return false;
    }
    std::memcpy(&g_origRel, site + 1, 4);
    uint8_t* origTarget = site + 5 + g_origRel;
    const bool targetIsStub = origTarget[0] == 0xC2 || origTarget[0] == 0xC3;  // ret / ret imm16
    const bool targetInGame = origTarget >= g_base && origTarget < g_base + g_imageSize;
    if (!targetIsStub || !targetInGame) {
        g_status.fetch_or(kStatusChainedForeign);
        Log(2, "[obmp] hook site already redirected (target %p, stub=%d, in_game=%d); chaining after it",
            origTarget, targetIsStub ? 1 : 0, targetInGame ? 1 : 0);
    }
    g_origTarget = reinterpret_cast<MarkerFn>(origTarget);

    g_trampoline = AllocNear(site, 64);
    if (!g_trampoline) {
        Log(3, "[obmp] could not allocate a trampoline within 2 GB of the hook site");
        return false;
    }
    // jmp qword ptr [rip+0] ; dq OnFrameEnd
    static const uint8_t jmpAbs[] = {0xFF, 0x25, 0x00, 0x00, 0x00, 0x00};
    std::memcpy(g_trampoline, jmpAbs, sizeof(jmpAbs));
    uint64_t target = reinterpret_cast<uint64_t>(&OnFrameEnd);
    std::memcpy(g_trampoline + sizeof(jmpAbs), &target, 8);
    FlushInstructionCache(GetCurrentProcess(), g_trampoline, 64);

    g_ourRel = static_cast<int32_t>(g_trampoline - (site + 5));
    if (!WriteRel32(site, g_origRel, g_ourRel)) {
        Log(3, "[obmp] failed to patch the hook site (it changed while patching?)");
        return false;
    }
    g_site = site;
    Log(1, "[obmp] frame hook installed at RVA 0x%llX (trampoline %p)",
        static_cast<unsigned long long>(site - g_base), g_trampoline);
    return true;
}

void UninstallFrameHook() {
    if (!g_site) return;
    if (WriteRel32(g_site, g_ourRel, g_origRel)) {
        Log(1, "[obmp] frame hook removed");
    } else {
        Log(2, "[obmp] hook site was changed by someone else; leaving it as is");
    }
    g_site = nullptr;
    g_status.fetch_and(~static_cast<uint32_t>(kStatusHookInstalled));
    // Waits for the TES thread to leave OnFrameEnd. The trampoline is never freed.
    for (int i = 0; i < 200 && g_inHook.load() > 0; ++i) Sleep(5);
}

// Address pointed to by an instruction with a [rip+disp32] operand; `insn` = start of the instruction,
// `dispOffset` = position of the disp32 within the instruction.
uint8_t* RipTarget(uint8_t* insn, size_t dispOffset, size_t insnLength) {
    int32_t disp;
    std::memcpy(&disp, insn + dispOffset, 4);
    return insn + insnLength + disp;
}

// ----------------------------------------------------------------------------------------------
// RunScriptCommand
// ----------------------------------------------------------------------------------------------
void SetResult(uint32_t ticket, int32_t state) {
    const uint32_t slot = ticket % kResultSlots;
    g_resultState[slot].store(state);
    g_resultTicket[slot].store(ticket);
}

// Guarded call to ExecuteCommand: false if the game raised an exception.
bool CallExecuteGuarded(ExecuteCommandFn fn, MsvcString* str) {
    __try {
        fn(nullptr, nullptr, str);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

// Runs on the TES thread (queue job). Builds the std::string in the game's format.
void __cdecl RunCommandJob(void* ctx) {
    auto* job = static_cast<CommandJob*>(ctx);
    const uint32_t ticket = job->ticket;
    int32_t state = kCmdFault;

    MsvcString str{};
    bool ready = true;
    if (job->length <= 15) {
        std::memcpy(str.buf, job->text, job->length);
        str.buf[job->length] = '\0';
        str.capacity = 15;
    } else {
        // Long buffer: must be allocated with the game's allocator, because the game will free it.
        void* gmalloc = g_gmallocGlobal ? *g_gmallocGlobal : nullptr;
        char* mem = nullptr;
        if (gmalloc) {
            auto gameMalloc = reinterpret_cast<FMallocMallocFn>((*static_cast<void***>(gmalloc))[kFMallocMallocSlot]);
            mem = static_cast<char*>(gameMalloc(gmalloc, job->length + 1, 0));
        }
        if (mem) {
            std::memcpy(mem, job->text, job->length);
            mem[job->length] = '\0';
            str.ptr = mem;
            str.capacity = job->length;
        } else {
            Log(3, "[obmp] command #%u: game allocator unavailable, not executed", ticket);
            ready = false;
        }
    }
    str.size = job->length;

    if (ready) {
        if (CallExecuteGuarded(reinterpret_cast<ExecuteCommandFn>(g_execCommand), &str)) {
            state = kCmdDone;
            g_commandsRun.fetch_add(1);
        } else {
            Log(3, "[obmp] command #%u raised an exception inside the game; skipped", ticket);
        }
        // `str` is not destroyed here: ExecuteCommand receives it by value and has already freed it.
    }
    SetResult(ticket, state);
    std::free(job);
}

bool IsAllowedCommandChar(unsigned char c) { return c >= 0x20 && c < 0x7F; }

bool ReadModuleLayout() {
    g_base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(g_base);
    auto* nt = reinterpret_cast<IMAGE_NT_HEADERS64*>(g_base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64) return false;
    g_imageSize = nt->OptionalHeader.SizeOfImage;
    if (nt->FileHeader.TimeDateStamp == kRefTimestamp && g_imageSize == kRefSizeOfImage)
        g_status.fetch_or(kStatusBuildKnown);
    auto* sec = IMAGE_FIRST_SECTION(nt);
    for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++sec) {
        if (std::memcmp(sec->Name, ".text", 5) == 0) {
            g_textStart = g_base + sec->VirtualAddress;
            g_textSize = sec->Misc.VirtualSize;
        }
    }
    Log(1, "[obmp] game base %p, image 0x%lX, timestamp 0x%08lX, build %s", g_base, g_imageSize,
        nt->FileHeader.TimeDateStamp, (g_status.load() & kStatusBuildKnown) ? "known" : "UNKNOWN");
    return g_textStart != nullptr;
}

}  // namespace

// ==============================================================================================
// Exported API
// ==============================================================================================
extern "C" {

struct ObmpStatus {
    uint32_t api_version;
    uint32_t flags;          // Status
    uint64_t ticks;          // TES frames seen by the hook
    uint32_t tes_thread_id;
    uint32_t reserved;
    uint64_t jobs_run;
    uint64_t job_faults;
    uint64_t game_base;
    uint32_t hook_site_rva;
    uint32_t exec_command_rva;
    uint64_t commands_run;   // v2
};

__declspec(dllexport) int obmp_api_version() { return 2; }

__declspec(dllexport) void obmp_set_logger(LogFn fn) { g_log = fn; }

// 0 = ok (hook installed), <0 = error; on error nothing has been modified.
__declspec(dllexport) int obmp_init() {
    if (g_status.load() & kStatusInitialized) return 0;
    if (!ReadModuleLayout()) {
        Log(3, "[obmp] unexpected process image; native core disabled");
        return -1;
    }
    if (!(g_status.load() & kStatusBuildKnown))
        Log(2, "[obmp] game build differs from the reference; relying on signatures");

    g_execCommand = Resolve(kSigExecuteCommand);
    if (uint8_t* del = Resolve(kSigGameOperatorDelete))
        g_gmallocGlobal = reinterpret_cast<void**>(RipTarget(del, 3, 7));  // mov rcx,[rip+disp32]
    if (g_execCommand && g_gmallocGlobal) g_status.fetch_or(kStatusExecResolved);
    else Log(2, "[obmp] script commands unavailable (ExecuteCommand=%p, GMalloc=%p)", g_execCommand, g_gmallocGlobal);

    if (!InstallFrameHook()) {
        Log(3, "[obmp] frame hook NOT installed; native core disabled");
        return -2;
    }
    g_status.fetch_or(kStatusInitialized | kStatusHookInstalled);
    return 0;
}

__declspec(dllexport) void obmp_shutdown() {
    UninstallFrameHook();
    std::lock_guard<std::mutex> lock(g_queueMutex);
    g_queue.clear();
}

__declspec(dllexport) void obmp_set_enabled(int enabled) {
    if (enabled) g_status.fetch_and(~static_cast<uint32_t>(kStatusDisabled));
    else g_status.fetch_or(kStatusDisabled);
}

// `size` = sizeof the caller's struct: never write beyond it, so a mod compiled against a different
// version of the struct cannot corrupt memory. Returns the bytes written.
__declspec(dllexport) int obmp_get_status(ObmpStatus* out, int size) {
    if (!out || size <= 0) return 0;
    ObmpStatus s{};
    s.api_version = 2;
    s.flags = g_status.load();
    s.ticks = g_ticks.load();
    s.tes_thread_id = g_tesTid.load();
    s.jobs_run = g_jobsRun.load();
    s.job_faults = g_jobFaults.load();
    s.game_base = reinterpret_cast<uint64_t>(g_base);
    s.hook_site_rva = g_site ? static_cast<uint32_t>(g_site - g_base) : 0;
    s.exec_command_rva = g_execCommand ? static_cast<uint32_t>(g_execCommand - g_base) : 0;
    s.commands_run = g_commandsRun.load();
    const size_t n = std::min(static_cast<size_t>(size), sizeof(s));
    std::memcpy(out, &s, n);
    return static_cast<int>(n);
}

// Enqueues a job to run on the TES thread at the next end of frame.
// 0 = enqueued, -1 = hook not active, -2 = invalid arguments.
__declspec(dllexport) int obmp_enqueue(JobFn fn, void* ctx) {
    if (!fn) return -2;
    if (!(g_status.load() & kStatusHookInstalled)) return -1;
    std::lock_guard<std::mutex> lock(g_queueMutex);
    g_queue.emplace_back(fn, ctx);
    return 0;
}

// Enqueues a script command (printable ASCII text, as in the game's console) to run on the
// TES thread. Returns a ticket > 0, or:
//  -1 hook not active, -2 empty text or disallowed characters, -3 ExecuteCommand or GMalloc
//  not found, -4 too long (max 4094), -5 out of memory.
__declspec(dllexport) int obmp_run_command(const char* text, int length) {
    if (!(g_status.load() & kStatusHookInstalled)) return -1;
    if (!text || length <= 0) return -2;
    if (static_cast<size_t>(length) > kMaxCommandLength) return -4;
    for (int i = 0; i < length; ++i)
        if (!IsAllowedCommandChar(static_cast<unsigned char>(text[i]))) return -2;
    if (!(g_status.load() & kStatusExecResolved)) return -3;

    auto* job = static_cast<CommandJob*>(std::malloc(sizeof(CommandJob) + length));
    if (!job) return -5;
    job->ticket = g_nextTicket.fetch_add(1);
    if (job->ticket == 0) job->ticket = g_nextTicket.fetch_add(1);  // 0 is not a valid ticket
    job->length = static_cast<uint32_t>(length);
    std::memcpy(job->text, text, length);
    job->text[length] = '\0';
    SetResult(job->ticket, kCmdPending);

    const uint32_t ticket = job->ticket;
    if (obmp_enqueue(RunCommandJob, job) != 0) {
        std::free(job);
        return -1;
    }
    return static_cast<int>(ticket);
}

// 0 pending, 1 executed, 2 exception in the game, 3 skipped; -1 unknown or expired ticket.
__declspec(dllexport) int obmp_command_state(int ticket) {
    if (ticket <= 0) return -1;
    const uint32_t slot = static_cast<uint32_t>(ticket) % kResultSlots;
    if (g_resultTicket[slot].load() != static_cast<uint32_t>(ticket)) return -1;
    return g_resultState[slot].load();
}

#ifdef OBMP_TESTING
// Offline test bench only: replaces ExecuteCommand and the GMalloc variable.
__declspec(dllexport) void obmp_test_set_targets(void* executeCommand, void** gmallocGlobal) {
    g_execCommand = static_cast<uint8_t*>(executeCommand);
    g_gmallocGlobal = gmallocGlobal;
    if (g_execCommand && g_gmallocGlobal) g_status.fetch_or(kStatusExecResolved);
}
#endif

}  // extern "C"

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID) { return TRUE; }
