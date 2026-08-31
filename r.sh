#!/bin/sh
set -u

WORK=/tmp/f44-rescue
REPORT=$WORK/diagnostics.txt
PKG=$WORK/packages.txt
ERR=$WORK/errors.txt
NET=$WORK/network.txt
mkdir -p "$WORK"
export HOME=/root
mkdir -p "$HOME"

say() { printf '%s\n' "$*"; }
section() { printf '\n===== %s =====\n' "$1" >> "$REPORT"; }
run_report() {
  title=$1
  shift
  section "$title"
  "$@" >> "$REPORT" 2>&1 || true
}

say "== Fedora 44 Anaconda rescue + Codex =="
say "Coletando diagnostico em $WORK ..."
: > "$REPORT"

run_report "DATE" date
run_report "UNAME" uname -a
run_report "OS RELEASE" cat /etc/os-release
run_report "KERNEL CMDLINE" cat /proc/cmdline
run_report "LSBLK" lsblk -o NAME,PATH,SIZE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS
run_report "LSBLK -F" lsblk -f
run_report "MOUNTS" mount
run_report "DF" df -hT
run_report "MEMORY" free -h
run_report "IP ADDR" ip addr
run_report "IP ROUTE" ip route
run_report "RESOLV CONF" cat /etc/resolv.conf

if command -v resolvectl >/dev/null 2>&1; then run_report "RESOLVECTL" resolvectl status; fi
if command -v lspci >/dev/null 2>&1; then run_report "LSPCI" lspci -nnk; fi
if command -v ethtool >/dev/null 2>&1; then
  run_report "ETHTOOL eno1" ethtool eno1
  run_report "ETHTOOL STATS eno1" ethtool -S eno1
fi
if command -v nvme >/dev/null 2>&1; then
  run_report "NVME LIST" nvme list
  run_report "NVME SMART nvme0n1" nvme smart-log /dev/nvme0n1
  run_report "NVME SMART nvme1n1" nvme smart-log /dev/nvme1n1
fi

section "ANACONDA ACTIVE STATE"
python3 >> "$REPORT" 2>&1 <<'PY' || true
try:
    from pyanaconda.payload.dnf.payload import DNFPayload
    p = DNFPayload(None)
    s = p.get_packages_selection()
    c = p.get_packages_configuration()
    print('environment =', s.environment)
    print('core_group_enabled =', s.core_group_enabled)
    print('default_environment_enabled =', s.default_environment_enabled)
    print('groups =', s.groups)
    print('packages =', s.packages)
    print('excluded_groups =', s.excluded_groups)
    print('excluded_packages =', s.excluded_packages)
    print('timeout =', c.timeout)
    print('retries =', c.retries)
    print('multilib_policy =', c.multilib_policy)
    print('repositories:')
    for r in p.get_repo_configurations():
        print('  name=', getattr(r, 'name', None), 'url=', getattr(r, 'url', None), 'mirrorlist=', getattr(r, 'mirrorlist', None), 'metalink=', getattr(r, 'metalink', None), 'enabled=', getattr(r, 'enabled', None))
except Exception as e:
    print('Could not query Anaconda DNF state:', repr(e))
PY

if [ -f /run/install/ks.cfg ]; then
  cp -f /run/install/ks.cfg "$WORK/ks.cfg" 2>/dev/null || true
  section "KICKSTART PACKAGES/SOURCE"
  python3 /run/install/ks.cfg >> "$REPORT" 2>&1 <<'PY' || true
PY
  python3 >> "$REPORT" 2>&1 <<'PY' || true
from pathlib import Path
p=Path('/run/install/ks.cfg')
if p.exists():
    lines=p.read_text(errors='replace').splitlines()
    inside=False
    for i,line in enumerate(lines,1):
        s=line.strip()
        if s.startswith('%packages'):
            inside=True
        if inside or s.startswith('url ') or s.startswith('repo ') or 'fedora' in s.lower() and ('http://' in s or 'https://' in s):
            print(f'{i}: {line}')
        if inside and s == '%end':
            inside=False
PY
fi

for f in anaconda.log packaging.log dnf.log dnf.librepo.log program.log storage.log syslog dbus.log; do
  [ -f "/tmp/$f" ] && cp -f "/tmp/$f" "$WORK/$f" 2>/dev/null || true
done

say "Analisando downloads e erros ..."
python3 "$WORK" > "$PKG" 2>&1 <<'PY'
from pathlib import Path
import re, sys
w=Path(sys.argv[1])
p=w/'packaging.log'
if not p.exists():
    print('packaging.log not found')
    raise SystemExit
lines=p.read_text(errors='replace').splitlines()
starts=[]
dones=[]
for n,line in enumerate(lines,1):
    m=re.search(r"Started downloading '([^']+)'", line)
    if m: starts.append((n,m.group(1),line))
    m=re.search(r"Downloaded '([^']+)'", line)
    if m: dones.append((n,m.group(1),line))
done_names={x[1] for x in dones}
pending=[]
seen=set()
for item in reversed(starts):
    name=item[1]
    if name not in done_names and name not in seen:
        pending.append(item); seen.add(name)
pending.reverse()
print('=== PROVAVEIS PACOTES INICIADOS MAS NAO CONFIRMADOS COMO BAIXADOS ===')
for x in pending[-120:]: print(x[2])
print('\n=== ULTIMOS 120 STARTED ===')
for x in starts[-120:]: print(x[2])
print('\n=== ULTIMOS 120 DOWNLOADED ===')
for x in dones[-120:]: print(x[2])
PY

python3 "$WORK" > "$ERR" 2>&1 <<'PY'
from pathlib import Path
import sys
w=Path(sys.argv[1])
keys=('error','failed','failure','curl','librepo','timeout','timed out','checksum','mirror','ssl','tls','404','403','connection reset','connection refused','no route','network is unreachable','transfer','download')
for name in ('dnf.librepo.log','packaging.log','dnf.log','anaconda.log','program.log','syslog'):
    p=w/name
    if not p.exists(): continue
    matches=[]
    for line in p.read_text(errors='replace').splitlines():
        lo=line.lower()
        if any(k in lo for k in keys): matches.append(line)
    print('\n===== '+name+' : LAST RELEVANT LINES =====')
    for line in matches[-250:]: print(line)
PY

section "KERNEL / HARDWARE WARNINGS"
if command -v dmesg >/dev/null 2>&1; then
  dmesg 2>&1 | tail -n 800 >> "$REPORT" || true
fi
if command -v journalctl >/dev/null 2>&1; then
  journalctl -b -p warning --no-pager 2>&1 | tail -n 800 >> "$REPORT" || true
fi

say "Testando rede Fedora ..."
: > "$NET"
SOURCE=https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os
for mode in default ipv4 ipv6; do
  case "$mode" in
    ipv4) af=-4 ;;
    ipv6) af=-6 ;;
    *) af= ;;
  esac
  printf '\n===== %s =====\n' "$mode" >> "$NET"
  curl $af -L -sS --connect-timeout 10 --max-time 40 -o /dev/null \
    -w 'http=%{http_code} remote=%{remote_ip} time=%{time_total} speed=%{speed_download} final=%{url_effective}\n' \
    "$SOURCE/repodata/repomd.xml" >> "$NET" 2>&1 || true
done

python3 "$SOURCE" "$WORK" >> "$NET" 2>&1 <<'PY'
import hashlib, subprocess, sys
src=sys.argv[1]+'/repodata/repomd.xml'
w=sys.argv[2]
for af in ('-4','-6'):
    print('\nRepeated repomd downloads',af)
    hashes=[]
    for i in range(1,4):
        out=f'{w}/repomd-{af[1:]}-{i}.xml'
        cp=subprocess.run(['curl',af,'-fLsS','--retry','2','--connect-timeout','10','--max-time','60',src,'-o',out],text=True,capture_output=True)
        if cp.returncode:
            print(i,'FAIL',cp.returncode,cp.stderr.strip())
            continue
        b=open(out,'rb').read()
        h=hashlib.sha256(b).hexdigest()
        hashes.append(h)
        print(i,'OK',len(b),'sha256',h)
    if hashes: print('all_same =', len(set(hashes))==1)
PY

say "Diagnostico pronto: $REPORT"
say "Pacotes: $PKG"
say "Erros: $ERR"
say "Rede: $NET"

cat > "$WORK/AGENTS.md" <<'EOF'
# Fedora 44 Anaconda rescue rules

You are running inside the temporary Fedora 44 Anaconda installer environment, not the installed OS.

Goal: diagnose and fix repeated package-download failures during Fedora 44 installation.

Known history:
- COSMIC selection failed twice near 1.52-1.53 GiB of 2.34 GiB.
- Fedora Workstation selection was changed in-memory to workstation-product-environment and failed later near 1.58 GiB of 2.06 GiB.
- The installer environment itself has network access.

Disk safety map established earlier:
- /dev/nvme0n1p1 = shared EFI partition. PRESERVE.
- /dev/nvme0n1p2 = NIXOS-ROOT Btrfs. PRESERVE.
- /dev/nvme0n1p3 = disposable Fedora target partition. It may be reformatted only after explicit user approval.
- /dev/nvme1n1p1 = important data volume labeled plataforma. PRESERVE ABSOLUTELY.

Hard rules:
1. Do not reboot, power off, kill Anaconda, kill pyanaconda services, alter partition tables, format, fsck, mount/unmount target filesystems, write to /dev/nvme*, or change EFI/bootloader without explicit user approval.
2. Start with read-only diagnosis. Inspect diagnostics.txt, packages.txt, errors.txt, network.txt and copied Anaconda logs.
3. Determine the actual failing package(s), mirror/librepo/curl error, network transport issue, storage/I/O issue, or memory/hardware signal.
4. Prefer the smallest reversible fix: repo/mirror change, IPv4 pinning, retries/timeouts, cache cleanup only if justified, or exact package workaround.
5. Before any change outside /tmp/f44-rescue, explain exactly what will change and ask the user to approve it.
6. Do not start a new OS installation until the cause/fix is identified and the user approves.
EOF

cat > "$WORK/PROMPT.txt" <<'EOF'
Diagnose this Fedora 44 Anaconda installation failure now. Read AGENTS.md first, then diagnostics.txt, packages.txt, errors.txt, network.txt, and the copied Anaconda/DNF/librepo logs. Run additional non-destructive commands as needed. I want the root cause and the shortest safe fix. Do not merely summarize logs. Correlate the last package downloads with librepo/DNF errors and check whether IPv4/IPv6, mirror selection, NIC, NVMe, or memory/hardware evidence explains the repeated failures. Do not make destructive changes without asking me first.
EOF

say "Instalando Codex CLI standalone oficial ..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ASSET=codex-x86_64-unknown-linux-musl.tar.gz ;;
  aarch64|arm64) ASSET=codex-aarch64-unknown-linux-musl.tar.gz ;;
  *) say "Arquitetura Codex nao suportada automaticamente: $ARCH"; exit 2 ;;
esac
CODURL="https://github.com/openai/codex/releases/latest/download/$ASSET"
ARC=$WORK/$ASSET
if ! curl -fL --retry 3 --retry-all-errors --connect-timeout 15 "$CODURL" -o "$ARC"; then
  say "ERRO: nao consegui baixar o Codex de $CODURL"
  exit 3
fi
rm -rf "$WORK/codex-dist"
mkdir -p "$WORK/codex-dist"
python3 "$ARC" "$WORK/codex-dist" <<'PY'
import sys, tarfile
arc,out=sys.argv[1:]
with tarfile.open(arc,'r:gz') as t:
    t.extractall(out)
PY
CODEXBIN=$(find "$WORK/codex-dist" -type f -name 'codex*' | head -n 1)
if [ -z "$CODEXBIN" ]; then
  say "ERRO: binario Codex nao encontrado no archive"
  exit 4
fi
chmod +x "$CODEXBIN"
mkdir -p /usr/local/bin 2>/dev/null || true
cp -f "$CODEXBIN" /usr/local/bin/codex 2>/dev/null || true
if command -v codex >/dev/null 2>&1; then
  say "Codex instalado: $(codex --version 2>/dev/null || echo instalado)"
else
  cp -f "$CODEXBIN" "$WORK/codex"
  chmod +x "$WORK/codex"
  PATH="$WORK:$PATH"
  export PATH
  say "Codex instalado em $WORK/codex"
fi

cd "$WORK"

say ""
say "Agora vou autenticar o Codex por device code."
say "Abra o endereco que ele mostrar no celular e informe o codigo."
if ! codex login status >/dev/null 2>&1; then
  codex login --device-auth || {
    say "Login automatico nao concluiu. Rode depois: codex login --device-auth"
    exit 5
  }
fi

say "Login OK. Abrindo Codex com o diagnostico e regras de seguranca."
PROMPT=$(cat "$WORK/PROMPT.txt")
exec codex --sandbox workspace-write --ask-for-approval on-request "$PROMPT"
