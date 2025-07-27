#!/bin/bash
#
# kubeadm-join.sh — Шаблон команды для присоединения рабочих нод к кластеру.
#
# Этот скрипт заполняется автоматически после запуска `scripts/kubeadm-init.sh`
# на контроллере.  По умолчанию он содержит пример команды.  Замените строку
# ниже на вывод `kubeadm token create --print-join-command` из кластера и
# выполните скрипт на каждой рабочей ноде.

set -euo pipefail

echo "This script must be replaced by the actual join command from the control plane."
echo "Example:"
echo "sudo kubeadm join 203.0.113.10:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"