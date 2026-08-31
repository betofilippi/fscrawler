#!/bin/sh
set -eu

VER=0.151.0
EXTRACT=/root/codex-package-extract
ARC=/root/codex-package.tar.gz
DEST=/opt/codex-$VER

export HOME=/root
export CODEX_HOME=/root/.codex
export PATH=/usr/local/bin:/usr/bin:/bin:$PATH

mkdir -p /opt /usr/local/bin /root/f44-rescue

# Reuse the 125 MB package that is already downloaded. Extract only if needed.
if [ ! -d "$EXTRACT" ]; then
  [ -f "$ARC" ] || { echo "ERRO: pacote /root/codex-package.tar.gz nao encontrado"; exit 1; }
  mkdir -p "$EXTRACT"
  python3 - "$ARC" "$EXTRACT" <<'PY'
import sys, tarfile
arc,out=sys.argv[1:]
with tarfile.open(arc,'r:gz') as t:
    t.extractall(out)
PY
fi

python3 - "$EXTRACT" "$DEST" <<'PY'
import shutil, sys
from pathlib import Path
extract, dest = map(Path, sys.argv[1:])

# The canonical package root is the directory containing codex-package.json.
roots = [p.parent for p in extract.rglob('codex-package.json')]
root = None
for r in roots:
    main = r / 'bin' / 'codex'
    host_bin = r / 'bin' / 'codex-code-mode-host'
    host_res = r / 'codex-resources' / 'codex-code-mode-host'
    if main.is_file() and (host_bin.is_file() or host_res.is_file()):
        root = r
        break

if root is None:
    print('Conteudo encontrado para diagnostico:')
    for p in sorted(extract.rglob('*')):
        if p.name in {'codex-package.json','codex','codex-code-mode-host'}:
            print(' ', p)
    raise SystemExit('ERRO: raiz canonica do pacote Codex nao localizada')

if dest.exists():
    shutil.rmtree(dest)
shutil.copytree(root, dest, symlinks=True)

for p in dest.rglob('*'):
    if p.is_file() and (p.parent.name in {'bin','codex-resources','codex-path'} or p.name == 'codex'):
        try:
            p.chmod(p.stat().st_mode | 0o111)
        except OSError:
            pass

print('Raiz detectada:', root)
print('Instalado em:', dest)
print('Main:', dest/'bin'/'codex')
if (dest/'bin'/'codex-code-mode-host').is_file():
    print('Host:', dest/'bin'/'codex-code-mode-host')
elif (dest/'codex-resources'/'codex-code-mode-host').is_file():
    print('Host:', dest/'codex-resources'/'codex-code-mode-host')
PY

ln -sfn "$DEST/bin/codex" /usr/local/bin/codex
if [ -f "$DEST/bin/codex-code-mode-host" ]; then
  ln -sfn "$DEST/bin/codex-code-mode-host" /usr/local/bin/codex-code-mode-host
elif [ -f "$DEST/codex-resources/codex-code-mode-host" ]; then
  ln -sfn "$DEST/codex-resources/codex-code-mode-host" /usr/local/bin/codex-code-mode-host
fi

# Preserve current live evidence again.
for f in anaconda.log packaging.log dnf.log dnf.librepo.log program.log storage.log syslog dbus.log; do
  [ -f "/tmp/$f" ] && cp -f "/tmp/$f" "/root/f44-rescue/$f" 2>/dev/null || true
done
[ -f /run/install/ks.cfg ] && cp -f /run/install/ks.cfg /root/f44-rescue/ks.cfg 2>/dev/null || true

printf '\n== Verificacao ==\n'
/usr/local/bin/codex --version
ls -l /usr/local/bin/codex /usr/local/bin/codex-code-mode-host

echo
printf '%s\n' 'Abrindo Codex novamente com acesso integral ao live system...'
cd /
exec /usr/local/bin/codex --dangerously-bypass-approvals-and-sandbox "Read /root/AGENTS.md first. You are root in the live Fedora 44 Anaconda environment. Diagnose and fix the repeated package-download failure directly on this machine. Inspect /tmp/anaconda.log, /tmp/packaging.log, /tmp/dnf.log, /tmp/dnf.librepo.log if present, /tmp/syslog, journal/dmesg, /run/install/ks.cfg and /root/f44-rescue. Correlate incomplete downloads with mirror/librepo/network/NIC/storage/RAM/kernel evidence. Apply the smallest safe reversible fix and validate it. Do not modify shared EFI, NixOS, or the plataforma data disk and do not perform destructive disk/bootloader operations or reboot without explicit user approval."