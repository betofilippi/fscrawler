#!/usr/bin/env bash
set -u
LOG=/tmp/packaging.log

echo "== Diagnostico download Anaconda =="
python3 <<'PY'
import re
from pathlib import Path
p=Path('/tmp/packaging.log')
if not p.exists():
    print('ERRO: /tmp/packaging.log nao existe')
    raise SystemExit(1)
started=[]
done=[]
for line in p.read_text(errors='replace').splitlines():
    m=re.search(r"Started downloading '([^']+)'", line)
    if m: started.append(m.group(1))
    m=re.search(r"Downloaded '([^']+)'", line)
    if m: done.append(m.group(1))
from collections import Counter
cs=Counter(started); cd=Counter(done)
pending=[]
for pkg,n in cs.items():
    rem=n-cd[pkg]
    if rem>0:
        pending.extend([pkg]*rem)
print('Downloads iniciados:', len(started))
print('Downloads concluidos:', len(done))
print('Provaveis pacotes que ficaram pendentes:')
if pending:
    for x in pending[-30:]: print('  '+x)
else:
    print('  nenhum identificado pelo pareamento Started/Downloaded')
print('\nUltimos 20 downloads iniciados:')
for x in started[-20:]: print('  '+x)
print('\nUltimos 20 downloads concluidos:')
for x in done[-20:]: print('  '+x)
PY

echo
echo "== Erros recentes no packaging.log =="
grep -i -E 'error|failed|timeout|checksum|mirror|curl|librepo|download' /tmp/packaging.log | tail -40 || true

echo
echo "== dnf.librepo.log =="
if [ -f /tmp/dnf.librepo.log ]; then
  tail -60 /tmp/dnf.librepo.log
else
  echo "nao existe"
fi

echo
echo "== dnf.log final =="
tail -40 /tmp/dnf.log 2>/dev/null || true
