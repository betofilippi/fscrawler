#!/usr/bin/env bash
set -u

KS=/run/install/ks.cfg
BAK=/tmp/ks.cfg.before-workstation

echo "== Fedora 44 Workstation helper =="

if [ ! -f "$KS" ]; then
  echo "ERRO: $KS nao existe. Abra o shell do Anaconda depois que o instalador carregar."
  exit 1
fi

cp -f "$KS" "$BAK"

python3 - "$KS" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text()
lines = text.splitlines()

out = []
in_packages = False
inserted = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith('%packages'):
        in_packages = True
        out.append(line)
        if not inserted:
            out.append('@^workstation-product-environment')
            inserted = True
        continue
    if stripped == '%end' and in_packages:
        in_packages = False
        out.append(line)
        continue
    if in_packages and 'cosmic-desktop-environment' in stripped:
        continue
    if in_packages and 'cosmic-desktop-apps' in stripped:
        continue
    if in_packages and 'workstation-product-environment' in stripped:
        continue
    out.append(line)

if not inserted:
    out.extend(['', '%packages', '@^workstation-product-environment', '%end'])

p.write_text('\n'.join(out) + '\n')
PY

echo "Kickstart alterado para Fedora Workstation:"
grep -n workstation-product-environment "$KS" || true

# Tenta atualizar tambem a selecao que o Anaconda ja carregou em memoria.
# Se o DBus ainda nao estiver pronto, o arquivo ks.cfg continua preparado.
python3 <<'PY'
try:
    from pyanaconda.payload.dnf.payload import DNFPayload
    p = DNFPayload(None)
    s = p.get_packages_selection()
    s.core_group_enabled = True
    s.default_environment_enabled = False
    s.environment = 'workstation-product-environment'
    s.groups = [x for x in s.groups if 'cosmic' not in x.lower()]
    s.excluded_groups = [x for x in s.excluded_groups if 'workstation' not in x.lower()]
    s.packages = [x for x in s.packages if 'cosmic' not in x.lower()]
    p.set_packages_selection(s)
    print('Selecao ativa do Anaconda alterada para workstation-product-environment.')
except Exception as e:
    print('Aviso: nao foi possivel alterar a selecao ativa do Anaconda:', e)
    print('O ks.cfg em /run/install ja foi preparado para Workstation.')
PY

echo
echo "OK. Nao mata processo e nao reinicia por este script."
echo "Backup: $BAK"
echo "Depois volte ao menu principal do Anaconda e confira Selecao de programas."
