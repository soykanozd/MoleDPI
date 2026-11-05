// SPDX-License-Identifier: GPL-3.0-only
// Unprivileged test runner: accepts an inherited packet FD. Never changes routes.
#include <signal.h>
#include <stdlib.h>
#include "hev-main.h"
static void stop(int sig) { (void)sig; hev_socks5_tunnel_quit(); }
int main(int argc, char **argv) {
    if (argc != 3) return 64;
    char *end = NULL;
    long fd = strtol(argv[2], &end, 10);
    if (!end || *end || fd < 3 || fd > 65535) return 64;
    signal(SIGTERM, stop); signal(SIGINT, stop);
    return hev_socks5_tunnel_main_from_file(argv[1], (int)fd) == 0 ? 0 : 1;
}
