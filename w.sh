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
lines = p.read_text().splitlines()
out = []
in_packages = False
inserted = False
for line in lines:
    s = line.strip()
    if s.startswith('%packages'):
        in_packages = True
        out.append(line)
        if not inserted:
            out.append('@^workstation-product-environment')
            inserted = True
        continue
    if s == '%end' and in_packages:
        in_packages = False
        out.append(line)
        continue
    if in_packages and ('cosmic-desktop-environment' in s or 'cosmic-desktop-apps' in s):
        continue
    if in_packages and 'workstation-product-environment' in s:
        continue
    out.append(line)
if not inserted:
    out += ['', '%packages', '@^workstation-product-environment', '%end']
p.write_text('\n'.join(out) + '\n')
PY

echo "Kickstart preparado:"
grep -n workstation-product-environment "$KS" || true

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
    print('Selecao ativa alterada para Fedora Workstation.')
except Exception as e:
    print('Kickstart alterado. Selecao ativa nao alterada:', e)
PY

echo "OK. Nao altera o particionamento e nao mata o Anaconda."
echo "Backup em $BAK"
