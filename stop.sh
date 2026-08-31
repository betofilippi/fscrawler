#!/usr/bin/env bash
set -u
python3 <<'PY'
import time
from pyanaconda.core.dbus import DBus
from pyanaconda.modules.common.constants.services import BOSS

boss = BOSS.get_proxy()
path = boss.ActiveInstallationTask
if not path:
    print('Nenhuma instalacao ativa encontrada.')
    raise SystemExit(0)

print('Cancelando tarefa ativa:', path)
task = DBus.get_proxy(BOSS.service_name, path)
task.Cancel()

for _ in range(50):
    try:
        if not task.IsRunning:
            print('Instalacao interrompida.')
            break
    except Exception:
        break
    time.sleep(0.2)
else:
    print('Cancelamento solicitado; tarefa ainda encerrando.')
PY
