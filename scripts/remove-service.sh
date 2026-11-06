#!/bin/zsh
# Run as an administrator after disconnecting and quitting MoleDPI.
set -eu
(( EUID == 0 )) || { print -u2 'Run with administrator privileges.'; exit 1; }
! /usr/bin/pgrep -x moledpi-pf >/dev/null || { print -u2 'Disconnect MoleDPI first.'; exit 1; }
label=local.moledpi.pf-service
if /bin/launchctl print system/$label >/dev/null 2>&1; then /bin/launchctl bootout system/$label; fi
/bin/rm -f /Library/LaunchDaemons/$label.plist
rootdir=/Library/PrivilegedHelperTools/local.moledpi
[[ ! -L $rootdir && ! -L /Library/PrivilegedHelperTools ]] || exit 1
/bin/rm -f "$rootdir"/{moledpi-service,moledpi-pf,tpws,ciadpi,tunnel-runner,moledpi-udp}
[[ ! -d $rootdir ]] || /bin/rmdir "$rootdir"
