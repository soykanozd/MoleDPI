# SPDX-License-Identifier: GPL-3.0-only
"""Small macOS-only bounded shutdown patch for the pinned ByeDPI source.
No packet-handling change. SIGTERM marks a flag; poll wakes at most every 250ms.
"""
from pathlib import Path
import sys
root=Path(sys.argv[1])
p=root/'proxy.c'
s=p.read_text()
if 'moledpi_stop_requested' not in s:
    old='static void on_cancel(int sig) {\n    shutdown(server_fd, SHUT_RDWR);\n}'
    assert s.count(old)==1
    s=s.replace(old,'''#ifdef __APPLE__
volatile sig_atomic_t moledpi_stop_requested = 0;
#endif
static void on_cancel(int sig) {
#ifdef __APPLE__
    (void)sig;
    moledpi_stop_requested = 1;
#else
    shutdown(server_fd, SHUT_RDWR);
#endif
}''')
    p.write_text(s)
p=root/'conev.c';s=p.read_text()
if 'moledpi_stop_requested' not in s:
    s='#ifdef __APPLE__\n#include <signal.h>\nextern volatile sig_atomic_t moledpi_stop_requested;\nstatic long time_ms(void);\n#endif\n'+s
    old='int ret = poll(pool->pevents, pool->count, ms);'
    assert s.count(old)==1
    s=s.replace(old,'''#ifdef __APPLE__
            int ret;
            long long deadline = ms < 0 ? -1 : (long long)time_ms() + ms;
            do {
                if (moledpi_stop_requested) { errno = EINTR; return NULL; }
                long long left = deadline < 0 ? 250 : deadline - (long long)time_ms();
                int slice = left < 0 ? 0 : left > 250 ? 250 : (int)left;
                ret = poll(pool->pevents, pool->count, slice);
            } while (ret == 0 && (deadline < 0 || (long long)time_ms() < deadline));
#else
            int ret = poll(pool->pevents, pool->count, ms);
#endif''')
    # Inspect and match the pinned loop, never silently patch an unknown version.
    old='while (!pool->brk) {'
    assert s.count(old)==1
    s=s.replace(old,'''while (!pool->brk) {
#ifdef __APPLE__
        if (moledpi_stop_requested) break;
#endif''')
    p.write_text(s)
