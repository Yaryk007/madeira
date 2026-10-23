/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * GameHub's session host: the first program of a Wine session, so the
 * session outlives its games. GameHub runs every game in its own iOS
 * process, where a Wine session cannot start twice; with this host as the
 * session's first program, each game is a child process and a finished game
 * leaves the session running for the next one.
 *
 * GameHub writes C:\gamehub-host\job.txt (UTF-8, one "key=value" per line):
 *   token=<n>          the launch's number
 *   cmd=<command line> what to start, quoted as CreateProcess expects
 *   dir=<folder>       its working folder (optional)
 *   env=NAME=VALUE     set for this game only (repeatable; empty VALUE unsets)
 * The host takes the job (deletes the file), starts the game, writes
 * running.txt ("<token>") and, when the game exits, exited.txt
 * ("<token> <exit code>"). A game that does not start reports
 * "<token> start-failed <error>". Between jobs it sleeps; it never exits.
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

#define DIR_W  L"C:\\gamehub-host"
#define JOB_W  L"C:\\gamehub-host\\job.txt"
#define RUN_W  L"C:\\gamehub-host\\running.txt"
#define DONE_W L"C:\\gamehub-host\\exited.txt"

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

static wchar_t *utf8_to_wide(const char *s, int len)
{
    int n = MultiByteToWideChar(CP_UTF8, 0, s, len, NULL, 0);
    wchar_t *w = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, (n + 1) * sizeof(wchar_t));
    if (w) MultiByteToWideChar(CP_UTF8, 0, s, len, w, n);
    return w;
}

/* The job file's bytes, or NULL while there is none. */
static char *take_job(void)
{
    HANDLE f = CreateFileW(JOB_W, GENERIC_READ, 0, NULL, OPEN_EXISTING, 0, NULL);
    DWORD size, got = 0;
    char *buf;
    if (f == INVALID_HANDLE_VALUE) return NULL;
    size = GetFileSize(f, NULL);
    if (size == INVALID_FILE_SIZE || size > 256 * 1024) { CloseHandle(f); DeleteFileW(JOB_W); return NULL; }
    buf = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size + 1);
    if (buf) ReadFile(f, buf, size, &got, NULL);
    CloseHandle(f);
    DeleteFileW(JOB_W);
    return buf;
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
    DWORD code = 0;

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
    if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, 0, NULL, dir, &si, &pi))
    {
        snprintf(report, sizeof(report), "%s start-failed %lu", token, (unsigned long)GetLastError());
        write_text(DONE_W, report);
    }
    else
    {
        write_text(RUN_W, token);
        WaitForSingleObject(pi.hProcess, INFINITE);
        GetExitCodeProcess(pi.hProcess, &code);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        snprintf(report, sizeof(report), "%s %lu", token, (unsigned long)code);
        write_text(DONE_W, report);
    }
    /* The next game starts with the session's own environment. */
    for (i = 0; i < set_count; i++) { SetEnvironmentVariableW(set_names[i], NULL); HeapFree(GetProcessHeap(), 0, set_names[i]); }
    HeapFree(GetProcessHeap(), 0, cmd);
    if (dir) HeapFree(GetProcessHeap(), 0, dir);
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR command_line, int show)
{
    (void)instance; (void)previous; (void)command_line; (void)show;
    CreateDirectoryW(DIR_W, NULL);
    for (;;)
    {
        char *job = take_job();
        if (job) { run_job(job); HeapFree(GetProcessHeap(), 0, job); }
        else Sleep(250);
    }
}
