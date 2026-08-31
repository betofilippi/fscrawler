#!/usr/bin/env bash
set -u

python3 <<'PY'
import sys
import time

from pyanaconda.payload.dnf.payload import DNFPayload
from pyanaconda.core.dbus import DBus
from pyanaconda.modules.common.constants.services import BOSS

p = DNFPayload(None)
s = p.get_packages_selection()
print('Selecao atual:', s.environment)
if s.environment != 'workstation-product-environment':
    print('ERRO: a selecao ativa NAO e Fedora Workstation. Abortando sem iniciar instalacao.')
    sys.exit(2)

boss = BOSS.get_proxy()
paths = boss.InstallWithTasks()
if not paths:
    print('ERRO: Anaconda nao retornou uma nova tarefa de instalacao.')
    sys.exit(3)

task = DBus.get_proxy(BOSS.service_name, paths[0])
print('Iniciando nova tarefa do Anaconda para Fedora Workstation 44...')
task.Start()
last = None
while True:
    try:
        progress = task.Progress
        running = task.IsRunning
    except Exception as e:
        print('ERRO consultando tarefa:', e)
        sys.exit(4)
    if progress != last:
        try:
            step, message = progress
            if message:
                print(f'[{step}/{task.Steps}] {message}', flush=True)
        except Exception:
            print('Progresso:', progress, flush=True)
        last = progress
    if not running:
        break
    time.sleep(1)

try:
    task.Finish()
except Exception as e:
    print('INSTALACAO FALHOU:', e)
    sys.exit(5)

print('INSTALACAO CONCLUIDA COM SUCESSO.')
PY
