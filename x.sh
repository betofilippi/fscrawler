#!/bin/sh
set -u

W=/tmp/f44-rescue
R=$W/diagnostics.txt
P=$W/packages.txt
E=$W/errors.txt
N=$W/network.txt
mkdir -p "$W" /root
export HOME=/root

logcmd() {
  title=$1
  shift
  printf '\n===== %s =====\n' "$title" >> "$R"
  "$@" >> "$R" 2>&1 || true
}

printf '%s\n' '== Fedora 44 rescue + Codex ==' '1/4 Coletando diagnostico...'
: > "$R"
logcmd DATE date
logcmd UNAME uname -a
logcmd OS cat /etc/os-release
logcmd CMDLINE cat /proc/cmdline
logcmd LSBLK lsblk -f
logcmd MOUNT mount
logcmd DF df -hT
command -v free >/dev/null 2>&1 && logcmd MEMORY free -h
command -v ip >/dev/null 2>&1 && logcmd IP_ADDR ip addr
command -v ip >/dev/null 2>&1 && logcmd IP_ROUTE ip route
logcmd RESOLV cat /etc/resolv.conf
command -v resolvectl >/dev/null 2>&1 && logcmd RESOLVECTL resolvectl status
command -v lspci >/dev/null 2>&1 && logcmd LSPCI lspci -nnk
if command -v ethtool >/dev/null 2>&1; then
  logcmd ETHTOOL_ENO1 ethtool eno1
  logcmd ETHTOOL_STATS_ENO1 ethtool -S eno1
fi
if command -v nvme >/dev/null 2>&1; then
  logcmd NVME_LIST nvme list
  logcmd NVME0_SMART nvme smart-log /dev/nvme0n1
  logcmd NVME1_SMART nvme smart-log /dev/nvme1n1
fi

printf '\n===== ANACONDA STATE =====\n' >> "$R"
python3 - >> "$R" 2>&1 <<'PY' || true
try:
    from pyanaconda.payload.dnf.payload import DNFPayload
    p=DNFPayload(None)
    s=p.get_packages_selection(); c=p.get_packages_configuration()
    print('environment =',s.environment)
    print('groups =',s.groups)
    print('packages =',s.packages)
    print('excluded_groups =',s.excluded_groups)
    print('timeout =',c.timeout,'retries =',c.retries,'multilib =',c.multilib_policy)
    print('repositories:')
    for r in p.get_repo_configurations():
        print(vars(r) if hasattr(r,'__dict__') else r)
except Exception as e:
    print('Anaconda state query failed:',repr(e))
PY

if [ -f /run/install/ks.cfg ]; then
  cp -f /run/install/ks.cfg "$W/ks.cfg" 2>/dev/null || true
  printf '\n===== KICKSTART RELEVANT =====\n' >> "$R"
  python3 - >> "$R" 2>&1 <<'PY'
from pathlib import Path
p=Path('/run/install/ks.cfg')
lines=p.read_text(errors='replace').splitlines()
inpkg=False
for i,l in enumerate(lines,1):
    s=l.strip()
    if s.startswith('%packages'): inpkg=True
    if inpkg or s.startswith('url ') or s.startswith('repo '): print(f'{i}: {l}')
    if inpkg and s=='%end': inpkg=False
PY
fi

for f in anaconda.log packaging.log dnf.log dnf.librepo.log program.log storage.log syslog dbus.log; do
  [ -f "/tmp/$f" ] && cp -f "/tmp/$f" "$W/$f" 2>/dev/null || true
done

python3 - "$W" > "$P" 2>&1 <<'PY'
from pathlib import Path
import re,sys
w=Path(sys.argv[1]); p=w/'packaging.log'
if not p.exists(): print('packaging.log missing'); raise SystemExit
lines=p.read_text(errors='replace').splitlines(); starts=[]; dones=[]
for i,l in enumerate(lines,1):
    m=re.search(r"Started downloading '([^']+)'",l)
    if m: starts.append((i,m.group(1),l))
    m=re.search(r"Downloaded '([^']+)'",l)
    if m: dones.append((i,m.group(1),l))
done={x[1] for x in dones}; seen=set(); pending=[]
for x in reversed(starts):
    if x[1] not in done and x[1] not in seen: pending.append(x); seen.add(x[1])
pending.reverse()
print('=== STARTED BUT NOT CONFIRMED DOWNLOADED ===')
for x in pending[-150:]: print(x[2])
print('\n=== LAST STARTED ===')
for x in starts[-150:]: print(x[2])
print('\n=== LAST DOWNLOADED ===')
for x in dones[-150:]: print(x[2])
PY

python3 - "$W" > "$E" 2>&1 <<'PY'
from pathlib import Path
import sys
w=Path(sys.argv[1])
keys=('error','failed','failure','curl','librepo','timeout','timed out','checksum','mirror','ssl','tls','404','403','connection reset','connection refused','network is unreachable','download')
for name in ('dnf.librepo.log','packaging.log','dnf.log','anaconda.log','program.log','syslog'):
    p=w/name
    if not p.exists(): continue
    hit=[l for l in p.read_text(errors='replace').splitlines() if any(k in l.lower() for k in keys)]
    print('\n===== '+name+' =====')
    for l in hit[-300:]: print(l)
PY

printf '\n===== KERNEL WARNINGS =====\n' >> "$R"
command -v dmesg >/dev/null 2>&1 && dmesg 2>&1 | tail -n 1000 >> "$R" || true
command -v journalctl >/dev/null 2>&1 && journalctl -b -p warning --no-pager 2>&1 | tail -n 1000 >> "$R" || true

printf '%s\n' '2/4 Testando IPv4/IPv6 e mirror...'
: > "$N"
SRC=https://download.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os/repodata/repomd.xml
for af in default ipv4 ipv6; do
  case "$af" in ipv4) opt=-4;; ipv6) opt=-6;; *) opt=;; esac
  printf '\n===== %s =====\n' "$af" >> "$N"
  curl $opt -LsS --connect-timeout 10 --max-time 40 -o /dev/null -w 'http=%{http_code} ip=%{remote_ip} time=%{time_total} speed=%{speed_download} url=%{url_effective}\n' "$SRC" >> "$N" 2>&1 || true
done
python3 - "$SRC" "$W" >> "$N" 2>&1 <<'PY'
import hashlib,subprocess,sys
src,w=sys.argv[1],sys.argv[2]
for af in ('-4','-6'):
    print('\nrepeat',af); hs=[]
    for i in range(3):
        out=f'{w}/net-{af[1:]}-{i}.xml'
        r=subprocess.run(['curl',af,'-fLsS','--retry','2','--connect-timeout','10','--max-time','60',src,'-o',out],capture_output=True,text=True)
        if r.returncode: print('FAIL',i,r.returncode,r.stderr.strip()); continue
        b=open(out,'rb').read(); h=hashlib.sha256(b).hexdigest(); hs.append(h); print('OK',i,len(b),h)
    if hs: print('same_hash =',len(set(hs))==1)
PY

cat > "$W/AGENTS.md" <<'EOF'
# Fedora 44 Anaconda rescue
You are inside the temporary Fedora 44 Anaconda installer environment.
Goal: find and fix repeated package download failures.
History: COSMIC failed twice around 1.52-1.53 GiB/2.34 GiB; Workstation failed around 1.58 GiB/2.06 GiB.
Disk safety: /dev/nvme0n1p1 shared EFI PRESERVE; /dev/nvme0n1p2 NIXOS-ROOT Btrfs PRESERVE; /dev/nvme0n1p3 Fedora target disposable only with explicit approval; /dev/nvme1n1p1 plataforma IMPORTANT DATA PRESERVE.
Rules: diagnose read-only first. Never reboot, kill Anaconda/pyanaconda, alter partition tables, format/fsck, mount/unmount target filesystems, write to nvme devices, or change EFI/bootloader without explicit user approval. Correlate exact pending RPMs with DNF/librepo/curl errors; inspect mirror behavior, IPv4/IPv6, NIC errors, NVMe/I/O and kernel logs. Prefer the smallest reversible fix. Ask before any write outside /tmp/f44-rescue.
EOF
cat > "$W/PROMPT.txt" <<'EOF'
Read AGENTS.md, diagnostics.txt, packages.txt, errors.txt, network.txt and all copied Anaconda/DNF/librepo logs. Diagnose the repeated Fedora 44 package-download failures and determine the actual root cause, not just the generic PayloadInstallationError. Run additional non-destructive checks as needed. Correlate pending RPMs with transport errors and test whether mirror selection, IPv4/IPv6, NIC, NVMe/I/O or memory/hardware evidence explains it. Give the shortest safe fix and ask before applying any change outside this workspace.
EOF

printf '%s\n' "Diagnostico salvo em $W" '3/4 Instalando Codex CLI standalone...'
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ASSET=codex-x86_64-unknown-linux-musl.tar.gz;;
  aarch64|arm64) ASSET=codex-aarch64-unknown-linux-musl.tar.gz;;
  *) echo "Arquitetura nao suportada: $ARCH"; exit 2;;
esac
ARC=$W/$ASSET
URL=https://github.com/openai/codex/releases/latest/download/$ASSET
curl -fL --retry 3 --connect-timeout 15 "$URL" -o "$ARC" || exit 3
rm -rf "$W/dist"; mkdir -p "$W/dist"
python3 - "$ARC" "$W/dist" <<'PY'
import sys,tarfile
with tarfile.open(sys.argv[1],'r:gz') as t: t.extractall(sys.argv[2])
PY
BIN=$(python3 - "$W/dist" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
for f in p.rglob('codex*'):
    if f.is_file(): print(f); break
PY
)
[ -n "$BIN" ] || exit 4
chmod +x "$BIN"
mkdir -p /usr/local/bin 2>/dev/null || true
cp -f "$BIN" /usr/local/bin/codex 2>/dev/null || true
if ! command -v codex >/dev/null 2>&1; then cp -f "$BIN" "$W/codex"; chmod +x "$W/codex"; PATH="$W:$PATH"; export PATH; fi
codex --version || exit 4

printf '%s\n' '4/4 Login do Codex por device code...'
cd "$W"
if ! codex login status >/dev/null 2>&1; then
  codex login --device-auth || { echo 'Login nao concluiu. Rode: codex login --device-auth'; exit 5; }
fi
PROMPT=$(cat "$W/PROMPT.txt")
echo 'Abrindo Codex com diagnostico carregado...'
exec codex --sandbox workspace-write --ask-for-approval on-request "$PROMPT"
