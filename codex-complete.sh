#!/bin/sh
set -eu

VER=0.151.0
TAG=rust-v0.151.0
ARCH=$(uname -m)

case "$ARCH" in
  x86_64|amd64)
    PLATFORM=x86_64-unknown-linux-musl
    ;;
  aarch64|arm64)
    PLATFORM=aarch64-unknown-linux-musl
    ;;
  *)
    echo "ERRO: arquitetura nao suportada: $ARCH"
    exit 1
    ;;
esac

URL="https://github.com/openai/codex/releases/download/$TAG/codex-package-$PLATFORM.tar.gz"
ARC=/root/codex-package.tar.gz
EXTRACT=/root/codex-package-extract
DEST=/opt/codex-$VER

export HOME=/root
mkdir -p /root /opt /usr/local/bin

echo "== Instalando pacote COMPLETO do Codex $VER =="
echo "Baixando pacote oficial: $PLATFORM"
curl -fL --retry 4 --retry-all-errors --connect-timeout 15 "$URL" -o "$ARC"

rm -rf "$EXTRACT" "$DEST"
mkdir -p "$EXTRACT"

python3 - "$ARC" "$EXTRACT" "$DEST" <<'PY'
import os, shutil, sys, tarfile
from pathlib import Path

arc, extract, dest = map(Path, sys.argv[1:])
with tarfile.open(arc, "r:gz") as t:
    t.extractall(extract)

hosts = list(extract.rglob("codex-code-mode-host"))
if not hosts:
    raise SystemExit("ERRO: codex-code-mode-host nao encontrado no pacote oficial")

pkgroot = None
for host in hosts:
    if host.parent.name == "bin":
        candidate = host.parent.parent
        if (candidate / "codex").is_file():
            pkgroot = candidate
            break

if pkgroot is None:
    # fallback: locate a directory containing both the main binary and bin/host
    for codex in extract.rglob("codex"):
        if codex.is_file() and (codex.parent / "bin" / "codex-code-mode-host").is_file():
            pkgroot = codex.parent
            break

if pkgroot is None:
    raise SystemExit("ERRO: estrutura completa do pacote Codex nao encontrada")

shutil.copytree(pkgroot, dest)
for p in dest.rglob("*"):
    if p.is_file() and (p.name == "codex" or p.parent.name == "bin"):
        try:
            p.chmod(p.stat().st_mode | 0o111)
        except OSError:
            pass
print("Pacote instalado em", dest)
print("Conteudo bin:")
for p in sorted((dest / "bin").glob("*")):
    print(" ", p.name)
PY

ln -sfn "$DEST/codex" /usr/local/bin/codex

# Link every packaged helper executable so Codex can spawn its companions.
if [ -d "$DEST/bin" ]; then
  for f in "$DEST"/bin/*; do
    [ -f "$f" ] || continue
    chmod +x "$f" 2>/dev/null || true
    ln -sfn "$f" "/usr/local/bin/$(basename "$f")"
  done
fi

# Explicitly verify the tool host that was missing.
if [ ! -x /usr/local/bin/codex-code-mode-host ]; then
  echo "ERRO: /usr/local/bin/codex-code-mode-host continua ausente"
  exit 2
fi

cat > /root/AGENTS.md <<'EOF'
# Fedora 44 Anaconda live rescue

You are running as root inside the live Fedora 44 Anaconda installer environment. You have full local system access and your working directory is `/`.

Primary goal: diagnose and fix the repeated Fedora 44 package-download failure and complete the Fedora Workstation installation safely.

Known disk map from direct inspection:
- /dev/nvme0n1p1 = shared EFI. PRESERVE.
- /dev/nvme0n1p2 = NIXOS-ROOT Btrfs. PRESERVE.
- /dev/nvme0n1p3 = Fedora target. This is the disposable Fedora partition.
- /dev/nvme1n1p1 = important data volume labeled plataforma. PRESERVE ABSOLUTELY.

Known failure history:
- COSMIC selection failed twice around 1.52-1.53 GiB of 2.34 GiB.
- Workstation selection (workstation-product-environment) later failed around 1.58 GiB of 2.06 GiB.
- The generic Anaconda exception is PayloadInstallationError / failed to download packages.

Operating rules:
1. Diagnose first from the live machine and all current logs: /tmp/anaconda.log, /tmp/packaging.log, /tmp/dnf.log, /tmp/dnf.librepo.log if present, /tmp/program.log, /tmp/syslog, /tmp/storage.log, /run/install/ks.cfg and /root/f44-rescue if present.
2. You may freely run non-destructive diagnostic commands, inspect the full filesystem, network, DNF/librepo state, kernel logs, NIC, NVMe SMART, memory and Anaconda DBus state.
3. You may make reversible software/network/repository changes needed to fix the installer.
4. Do NOT format, repartition, fsck, wipe, write raw blocks, alter EFI/bootloader, or modify NixOS or the plataforma data volume without first explaining the exact action and receiving explicit user approval.
5. Do not reboot or power off unless the user explicitly approves.
6. Do not merely summarize. Determine the root cause, implement the smallest safe fix, validate it, and then help resume/complete Fedora Workstation installation.
EOF

mkdir -p /root/f44-rescue

# Preserve the current installer evidence for Codex.
for f in anaconda.log packaging.log dnf.log dnf.librepo.log program.log storage.log syslog dbus.log; do
  [ -f "/tmp/$f" ] && cp -f "/tmp/$f" "/root/f44-rescue/$f" 2>/dev/null || true
done
[ -f /run/install/ks.cfg ] && cp -f /run/install/ks.cfg /root/f44-rescue/ks.cfg 2>/dev/null || true

echo
echo "Verificando instalacao:"
/usr/local/bin/codex --version
ls -l /usr/local/bin/codex /usr/local/bin/codex-code-mode-host

echo
echo "Codex completo instalado. Iniciando com acesso integral ao live system..."
cd /
exec /usr/local/bin/codex --dangerously-bypass-approvals-and-sandbox "Read /root/AGENTS.md first. Then diagnose and fix the Fedora 44 Anaconda repeated package-download failure directly on this live machine. Inspect all live /tmp Anaconda/DNF/librepo logs and /root/f44-rescue. Correlate incomplete package downloads with the actual transfer errors, test mirror/network/IPv4/IPv6/NIC/storage/memory hypotheses, implement the smallest safe fix, validate it, and help complete the Fedora Workstation installation. Do not perform destructive disk, EFI, bootloader, NixOS, or plataforma-volume operations without asking me first."
