#!/bin/sh
set -eu

export HOME=/root
export CODEX_HOME=/root/.codex
export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
WORK=/root/f44-rescue
mkdir -p "$WORK" "$CODEX_HOME" /usr/local/bin

printf '%s\n' '== Fedora 44 Anaconda - Codex root rescue =='
printf '%s\n' 'Instalando Codex em /usr/local/bin e usando / como area de trabalho.'

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ASSET=codex-x86_64-unknown-linux-musl.tar.gz ;;
  aarch64|arm64) ASSET=codex-aarch64-unknown-linux-musl.tar.gz ;;
  *) echo "Arquitetura nao suportada: $ARCH"; exit 2 ;;
esac

ARC="$WORK/$ASSET"
URL="https://github.com/openai/codex/releases/latest/download/$ASSET"

if ! command -v codex >/dev/null 2>&1; then
  echo 'Baixando Codex oficial...'
  curl -fL --retry 4 --retry-all-errors --connect-timeout 15 "$URL" -o "$ARC"
  rm -rf "$WORK/dist"
  mkdir -p "$WORK/dist"
  python3 - "$ARC" "$WORK/dist" <<'PY'
import sys, tarfile
arc,out=sys.argv[1:]
with tarfile.open(arc,'r:gz') as t:
    t.extractall(out)
PY
  BIN=$(find "$WORK/dist" -type f -name 'codex*' | head -n 1)
  [ -n "$BIN" ] || { echo 'ERRO: binario Codex nao encontrado'; exit 3; }
  cp -f "$BIN" /usr/local/bin/codex
  chmod 755 /usr/local/bin/codex
fi

echo "Codex: $(/usr/local/bin/codex --version 2>/dev/null || echo instalado)"

# Preserve the live installer diagnostics under /root, not /tmp.
for f in anaconda.log packaging.log dnf.log dnf.librepo.log program.log storage.log syslog dbus.log; do
  [ -f "/tmp/$f" ] && cp -f "/tmp/$f" "$WORK/$f" 2>/dev/null || true
done
[ -f /run/install/ks.cfg ] && cp -f /run/install/ks.cfg "$WORK/ks.cfg" 2>/dev/null || true
lsblk -f > "$WORK/lsblk.txt" 2>&1 || true
mount > "$WORK/mount.txt" 2>&1 || true
cat /proc/cmdline > "$WORK/cmdline.txt" 2>&1 || true
ip addr > "$WORK/ip-addr.txt" 2>&1 || true
ip route > "$WORK/ip-route.txt" 2>&1 || true

cat > /root/AGENTS.md <<'EOF'
# Fedora 44 Anaconda recovery environment

You are root inside the LIVE Fedora 44 Anaconda installer environment. You have full filesystem and command access. Diagnose and repair the repeated Fedora installation download failure, not just summarize it.

Known disk map from direct inspection:
- /dev/nvme0n1p1 = shared EFI. PRESERVE.
- /dev/nvme0n1p2 = NIXOS-ROOT Btrfs. PRESERVE.
- /dev/nvme0n1p3 = Fedora target partition. It is disposable for Fedora installation, but do not format or repartition until you have diagnosed the failure and told the user exactly why.
- /dev/nvme1n1p1 = important data volume labelled plataforma. NEVER modify, format, fsck, repartition, or overwrite it.

Installation history:
- COSMIC selection failed twice during package download around 1.52-1.53 GiB / 2.34 GiB.
- Selection was then changed live to Fedora Workstation (workstation-product-environment).
- Workstation download passed the COSMIC failure point but failed around 1.58 GiB / 2.06 GiB.
- Therefore do not assume COSMIC is the sole cause. Investigate package/mirror/librepo/network/NIC/storage/RAM/kernel evidence.

Operating rules:
1. You may freely inspect the whole live system, /run, /tmp, /sys, /proc, Anaconda DBus state, network state, logs, package caches, and repositories.
2. You may make reversible runtime fixes needed to diagnose downloads (network/repository/curl/DNF settings) and create files under /root or /tmp.
3. Before destructive disk operations, partition-table changes, filesystem creation, EFI changes, bootloader writes, or modifying nvme0n1p1/nvme0n1p2/nvme1n1p1, explain and obtain explicit user approval.
4. Do not kill Anaconda/pyanaconda services or reboot unless the user explicitly approves.
5. Find the actual root cause. Correlate Started downloading vs Downloaded entries, dnf.librepo.log, packaging.log, syslog/journal, NIC counters, DNS/IPv4/IPv6, mirror redirects, checksums, I/O errors, OOM/MCE/PCIe/AER events.
6. If a safe runtime fix can be tested without reinstalling, test it. Then explain the shortest path to complete Fedora Workstation 44.
EOF

cat > "$WORK/PROMPT.txt" <<'EOF'
Read /root/AGENTS.md first. Then investigate the Fedora 44 Anaconda failure directly on this live machine. Use /root/f44-rescue plus the live /tmp logs, /run/install/ks.cfg, Anaconda DBus state, journal/dmesg, network and hardware state. Determine the actual package/download/mirror/network/storage/hardware root cause and make safe reversible diagnostic fixes as needed. Do not just tell me commands to run: you are already root here, so inspect the system yourself. Do not perform destructive disk/EFI/bootloader operations without asking me first.
EOF

if ! /usr/local/bin/codex login status >/dev/null 2>&1; then
  echo
  echo 'Codex precisa autenticar. Siga o device code que aparecer.'
  /usr/local/bin/codex login --device-auth
fi

echo
echo 'Abrindo Codex como ROOT, cwd=/, sandbox=danger-full-access.'
echo 'Ele pode ler e escrever fora de /root; as protecoes dos discos estao no AGENTS.md.'
PROMPT=$(cat "$WORK/PROMPT.txt")
cd /
exec /usr/local/bin/codex --sandbox danger-full-access -C / "$PROMPT"
