/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * GameHub's session host: the first program of a Wine session, so the
 * session outlives its games. GameHub runs every game in its own iOS
 * process, where a Wine session cannot start twice; with this host as the
 * session's first program, each game is a child process and a finished game
 * leaves the session running for the next one. Several games (or other
 * programs) can run at once: GameHub shows one of them and keeps the others
 * running behind it.
 *
 * GameHub writes C:\gamehub-host\job.txt (UTF-8, one "key=value" per line):
 *   token=<n>          the launch's number
 *   cmd=<command line> what to start, quoted as CreateProcess expects
 *   dir=<folder>       its working folder (optional)
 *   env=NAME=VALUE     set for this game only (repeatable; empty VALUE unsets)
 * The host takes the job (deletes the file) and starts the game in a job
 * object of its own, so the processes it starts belong to it too. It writes
 * running.txt ("<token>"); when the job's last process exits it writes
 * exited-<token>.txt and exited.txt ("<token> <exit code>"). A game that does
 * not start reports "<token> start-failed <error>".
 *
 * GameHub sends commands as C:\gamehub-host\cmd-<n>.txt, one line each,
 * taken in order of n:
 *   front <token>      show that game's windows and minimize every other game's
 *   hide               minimize every game's windows (GameHub's home is shown)
 *   close <token>      end that game and every process it started
 *   pause 0|1          pause games in the background (default 1)
 * A game the host starts becomes the front one. The host never exits.
 *
 * A game behind the front one (or behind GameHub's home) gets every saving the
 * host can give it: idle priority, its process ids in background.txt (the app
 * then mutes it and gives it no frames to draw), and, while pausing is on, it
 * is suspended (NtSuspendProcess on each of its processes; wineserver holds
 * its threads at a safe point because the request comes from this host, whose
 * process id is in host-pid.txt). Bringing it to the front resumes it first.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define DIR_W  L"C:\\gamehub-host"
#define JOB_W  L"C:\\gamehub-host\\job.txt"
#define RUN_W  L"C:\\gamehub-host\\running.txt"
#define DONE_W L"C:\\gamehub-host\\exited.txt"
#define CMDS_W L"C:\\gamehub-host\\cmd-*.txt"
#define BACK_W L"C:\\gamehub-host\\background.txt"
#define PID_W  L"C:\\gamehub-host\\host-pid.txt"
#define MAX_GAMES 16
#define MAX_PIDS 32

struct game
{
    char token[32];
    HANDLE job;        /* NULL when the job object could not be made: the process alone counts */
    HANDLE process;
    DWORD pid;
    DWORD code;        /* the first process's exit code, reported for the game */
    int code_known;
    DWORD frozen[MAX_PIDS];   /* the processes this host suspended, to resume exactly those */
    int frozen_count;
};

static struct game games[MAX_GAMES];
static int game_count;
static char front_token[32];   /* the game in front; empty behind GameHub's home */
static int pause_games = 1;
static char last_background[1024];

typedef LONG (WINAPI *process_call)(HANDLE);
static process_call suspend_process, resume_process;

static void write_text(const wchar_t *path, const char *text)
{
    wchar_t tmp[MAX_PATH];
    HANDLE f;
    DWORD n;
    swprintf(tmp, MAX_PATH, L"%ls.tmp", path);
    f = CreateFileW(tmp, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) return;
    WriteFile(f, text, (DWORD)strlen(text), &n, NULL);
    CloseHandle(f);
    MoveFileExW(tmp, path, MOVEFILE_REPLACE_EXISTING);
}

/* exited-<token>.txt for GameHub's poll of that game, exited.txt for the last one. */
static void report_exit(const char *token, const char *report)
{
    wchar_t path[MAX_PATH];
    swprintf(path, MAX_PATH, DIR_W L"\\exited-%hs.txt", token);
    write_text(path, report);
    write_text(DONE_W, report);
}

static wchar_t *utf8_to_wide(const char *s, int len)
{
    int n = MultiByteToWideChar(CP_UTF8, 0, s, len, NULL, 0);
    wchar_t *w = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, (n + 1) * sizeof(wchar_t));
    if (w) MultiByteToWideChar(CP_UTF8, 0, s, len, w, n);
    return w;
}

/* A file's bytes (deleted once read), or NULL while there is none. */
static char *take_file(const wchar_t *path)
{
    HANDLE f = CreateFileW(path, GENERIC_READ, 0, NULL, OPEN_EXISTING, 0, NULL);
    DWORD size, got = 0;
    char *buf;
    if (f == INVALID_HANDLE_VALUE) return NULL;
    size = GetFileSize(f, NULL);
    if (size == INVALID_FILE_SIZE || size > 256 * 1024) { CloseHandle(f); DeleteFileW(path); return NULL; }
    buf = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size + 1);
    if (buf) ReadFile(f, buf, size, &got, NULL);
    CloseHandle(f);
    DeleteFileW(path);
    return buf;
}

/* The game's processes: its job's, else its first process. */
static int game_pids(const struct game *g, DWORD *pids, int max)
{
    struct { JOBOBJECT_BASIC_PROCESS_ID_LIST list; ULONG_PTR more[MAX_PIDS]; } info;
    int n = 0;
    DWORD i;
    if (g->job && QueryInformationJobObject(g->job, JobObjectBasicProcessIdList, &info, sizeof(info), NULL))
        for (i = 0; i < info.list.NumberOfProcessIdsInList && n < max; i++) pids[n++] = (DWORD)info.list.ProcessIdList[i];
    if (!n && !g->code_known && max) pids[n++] = g->pid;
    return n;
}

static void set_priority(DWORD pid, DWORD priority)
{
    HANDLE p = OpenProcess(PROCESS_SET_INFORMATION, FALSE, pid);
    if (p) { SetPriorityClass(p, priority); CloseHandle(p); }
}

static void freeze_game(struct game *g)
{
    DWORD pids[MAX_PIDS];
    int n = game_pids(g, pids, MAX_PIDS), i;
    if (g->frozen_count || !suspend_process) return;
    for (i = 0; i < n; i++)
    {
        HANDLE p = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, pids[i]);
        if (!p) continue;
        if (suspend_process(p) >= 0) g->frozen[g->frozen_count++] = pids[i];
        CloseHandle(p);
    }
}

static void thaw_game(struct game *g)
{
    int i;
    for (i = 0; i < g->frozen_count && resume_process; i++)
    {
        HANDLE p = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, g->frozen[i]);
        if (p) { resume_process(p); CloseHandle(p); }
    }
    g->frozen_count = 0;
}

/* background.txt: the process ids of every game not in front, one per line. */
static void report_background(void)
{
    char text[1024] = "";
    size_t len = 0;
    int i, k;
    for (i = 0; i < game_count; i++)
    {
        DWORD pids[MAX_PIDS];
        int n;
        if (!strcmp(games[i].token, front_token)) continue;
        n = game_pids(&games[i], pids, MAX_PIDS);
        for (k = 0; k < n && len + 12 < sizeof(text); k++) len += snprintf(text + len, sizeof(text) - len, "%lu\n", (unsigned long)pids[k]);
    }
    if (!strcmp(text, last_background)) return;
    strcpy(last_background, text);
    write_text(BACK_W, text);
}

/* Is this process one of the game's? Its job when there is one, else its first process. */
static BOOL owns_pid(const struct game *g, DWORD pid)
{
    HANDLE p;
    BOOL in = FALSE;
    if (pid == g->pid) return TRUE;
    if (!g->job) return FALSE;
    p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!p) return FALSE;
    if (!IsProcessInJob(p, g->job, &in)) in = FALSE;
    CloseHandle(p);
    return in;
}

struct show_args { const struct game *front; };

/* Every visible top-level window: the front game's restored and brought forward,
 * every other game's minimized. Windows of no game (the host has none) stay. */
static BOOL CALLBACK show_window(HWND hwnd, LPARAM param)
{
    const struct show_args *args = (const struct show_args *)param;
    DWORD pid = 0;
    int i;
    GetWindowThreadProcessId(hwnd, &pid);
    for (i = 0; i < game_count; i++)
    {
        if (!owns_pid(&games[i], pid)) continue;
        /* Async: a window's own thread does the work, so a busy game never stalls the host. */
        if (&games[i] == args->front)
        {
            if (IsIconic(hwnd)) ShowWindowAsync(hwnd, SW_RESTORE);
            if (IsWindowVisible(hwnd)) SetForegroundWindow(hwnd);
        }
        else if (!games[i].frozen_count && IsWindowVisible(hwnd) && !IsIconic(hwnd) && !GetWindow(hwnd, GW_OWNER))
            ShowWindowAsync(hwnd, SW_MINIMIZE);
        break;
    }
    return TRUE;
}

/* The front game runs at normal priority with its windows shown; every other
 * game is minimized, at idle priority and, while pausing is on, suspended. */
static void bring_front(struct game *front)
{
    struct show_args args = { front };
    int i, k;
    strcpy(front_token, front ? front->token : "");
    if (front) thaw_game(front);
    EnumWindows(show_window, (LPARAM)&args);
    for (i = 0; i < game_count; i++)
    {
        DWORD pids[MAX_PIDS];
        int n = game_pids(&games[i], pids, MAX_PIDS);
        int behind = &games[i] != front;
        for (k = 0; k < n; k++) set_priority(pids[k], behind ? IDLE_PRIORITY_CLASS : NORMAL_PRIORITY_CLASS);
        if (behind && pause_games) freeze_game(&games[i]);
        else if (behind) thaw_game(&games[i]);
    }
    report_background();
}

static struct game *find_game(const char *token)
{
    int i;
    for (i = 0; i < game_count; i++) if (!strcmp(games[i].token, token)) return &games[i];
    return NULL;
}

static void forget_game(int i)
{
    if (games[i].job) CloseHandle(games[i].job);
    if (games[i].process) CloseHandle(games[i].process);
    games[i] = games[--game_count];
}

static void run_job(char *job)
{
    char token[32] = "0", report[96];
    wchar_t *cmd = NULL, *dir = NULL;
    wchar_t *set_names[64];
    int set_count = 0, i;
    char *line = job, *next;
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    HANDLE job_object;

    for (; line && *line; line = next)
    {
        size_t len;
        next = strchr(line, '\n');
        if (next) *next++ = 0;
        len = strlen(line);
        if (len && line[len - 1] == '\r') line[--len] = 0;
        if (!strncmp(line, "token=", 6)) { strncpy(token, line + 6, sizeof(token) - 1); token[sizeof(token) - 1] = 0; }
        else if (!strncmp(line, "cmd=", 4)) cmd = utf8_to_wide(line + 4, -1);
        else if (!strncmp(line, "dir=", 4) && line[4]) dir = utf8_to_wide(line + 4, -1);
        else if (!strncmp(line, "env=", 4) && set_count < 64)
        {
            char *eq = strchr(line + 4, '=');
            wchar_t *name, *value;
            if (!eq) continue;
            *eq = 0;
            name = utf8_to_wide(line + 4, -1);
            value = eq[1] ? utf8_to_wide(eq + 1, -1) : NULL;
            if (name) { SetEnvironmentVariableW(name, value); set_names[set_count++] = name; }
            if (value) HeapFree(GetProcessHeap(), 0, value);
        }
    }
    if (!cmd) return;

    memset(&si, 0, sizeof(si));
    si.cb = sizeof(si);
    memset(&pi, 0, sizeof(pi));
    if (game_count == MAX_GAMES)
    {
        snprintf(report, sizeof(report), "%s start-failed %lu", token, (unsigned long)ERROR_TOO_MANY_OPEN_FILES);
        report_exit(token, report);
    }
    /* Suspended until it is in its job, so a program it starts at once is the game's too. */
    else if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, CREATE_SUSPENDED, NULL, dir, &si, &pi))
    {
        snprintf(report, sizeof(report), "%s start-failed %lu", token, (unsigned long)GetLastError());
        report_exit(token, report);
    }
    else
    {
        struct game *g = &games[game_count++];
        memset(g, 0, sizeof(*g));
        strcpy(g->token, token);
        job_object = CreateJobObjectW(NULL, NULL);
        if (job_object && !AssignProcessToJobObject(job_object, pi.hProcess)) { CloseHandle(job_object); job_object = NULL; }
        g->job = job_object;
        g->process = pi.hProcess;
        g->pid = pi.dwProcessId;
        ResumeThread(pi.hThread);
        CloseHandle(pi.hThread);
        write_text(RUN_W, token);
    }
    /* The next game starts with the session's own environment. */
    for (i = 0; i < set_count; i++) { SetEnvironmentVariableW(set_names[i], NULL); HeapFree(GetProcessHeap(), 0, set_names[i]); }
    HeapFree(GetProcessHeap(), 0, cmd);
    if (dir) HeapFree(GetProcessHeap(), 0, dir);
}

/* Reports the games whose last process exited. */
static void reap(void)
{
    char report[96];
    int i;
    for (i = game_count - 1; i >= 0; i--)
    {
        struct game *g = &games[i];
        JOBOBJECT_BASIC_ACCOUNTING_INFORMATION info;
        BOOL alive;
        if (!g->code_known && WaitForSingleObject(g->process, 0) == WAIT_OBJECT_0)
        {
            GetExitCodeProcess(g->process, &g->code);
            g->code_known = 1;
        }
        if (g->job && QueryInformationJobObject(g->job, JobObjectBasicAccountingInformation, &info, sizeof(info), NULL))
            alive = info.ActiveProcesses > 0;
        else
            alive = !g->code_known;
        if (alive) continue;
        snprintf(report, sizeof(report), "%s %lu", g->token, (unsigned long)g->code);
        report_exit(g->token, report);
        forget_game(i);
    }
}

static void run_command(char *text)
{
    char *nl = strpbrk(text, "\r\n"), *arg;
    struct game *g;
    if (nl) *nl = 0;
    arg = strchr(text, ' ');
    if (arg) *arg++ = 0;
    if (!strcmp(text, "hide")) bring_front(NULL);
    else if (!arg) return;
    else if (!strcmp(text, "pause"))
    {
        pause_games = atoi(arg) != 0;
        if (!pause_games) { int i; for (i = 0; i < game_count; i++) thaw_game(&games[i]); }
    }
    else if (!(g = find_game(arg))) return;
    else if (!strcmp(text, "front")) bring_front(g);
    else if (!strcmp(text, "close"))
    {
        thaw_game(g);   /* a suspended process cannot run its exit */
        if (g->job) TerminateJobObject(g->job, 0);
        else TerminateProcess(g->process, 0);
    }
}

static int __cdecl by_number(const void *a, const void *b)
{
    long x = *(const long *)a, y = *(const long *)b;
    return x < y ? -1 : x > y;
}

/* cmd-<n>.txt, oldest first. */
static void take_commands(void)
{
    WIN32_FIND_DATAW data;
    HANDLE find = FindFirstFileW(CMDS_W, &data);
    long numbers[64];
    int count = 0, i;
    if (find == INVALID_HANDLE_VALUE) return;
    do
    {
        if (count < 64 && swscanf(data.cFileName, L"cmd-%ld.txt", &numbers[count]) == 1) count++;
    } while (FindNextFileW(find, &data));
    FindClose(find);
    qsort(numbers, count, sizeof(long), by_number);
    for (i = 0; i < count; i++)
    {
        wchar_t path[MAX_PATH];
        char *text;
        swprintf(path, MAX_PATH, DIR_W L"\\cmd-%ld.txt", numbers[i]);
        if ((text = take_file(path))) { run_command(text); HeapFree(GetProcessHeap(), 0, text); }
    }
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR command_line, int show)
{
    char pid[16];
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    (void)instance; (void)previous; (void)command_line; (void)show;
    CreateDirectoryW(DIR_W, NULL);
    suspend_process = (process_call)(void *)GetProcAddress(ntdll, "NtSuspendProcess");
    resume_process = (process_call)(void *)GetProcAddress(ntdll, "NtResumeProcess");
    snprintf(pid, sizeof(pid), "%lu", (unsigned long)GetCurrentProcessId());
    write_text(PID_W, pid);
    for (;;)
    {
        char *job = take_file(JOB_W);
        if (job)
        {
            int before = game_count;
            run_job(job);
            HeapFree(GetProcessHeap(), 0, job);
            /* The new game is the front one once it has windows; until then the others step back. */
            if (game_count > before) bring_front(&games[game_count - 1]);
        }
        take_commands();
        reap();
        report_background();   /* a game behind can start more programs */
        Sleep(100);
    }
}
