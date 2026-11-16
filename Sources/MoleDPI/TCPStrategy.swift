// SPDX-License-Identifier: GPL-3.0-only
// Shared by the unprivileged preflight and the authenticated PF worker.
// OOB consistently timed out on this CDN while ordinary splitting succeeded.
// Keep the exception suffix-bound and in memory; never collect browsing hosts.
enum TCPStrategy {
    static let profiles = [
        ["--split-pos=host+1", "--tlsrec=host+1"],
        ["--hostlist-exclude-domains=rbxcdn.com", "--split-pos=2", "--oob=tls",
         "--new", "--filter-tcp=80,443", "--filter-l7=http,tls", "--split-pos=host+1"],
        ["--split-pos=host+1", "--tlsrec=host+1"]
    ]
}
