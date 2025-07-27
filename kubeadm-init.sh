#!/bin/bash
#
# kubeadm-init.sh — Инициализация Kubernetes‑кластера
#
# Этот скрипт необходимо выполнить на первой (мастер) ноде.  Он устанавливает
# Kubernetes control plane, создаёт конфигурационный файл и выводит команду,
# которую нужно выполнить на рабочих нодах для присоединения к кластеру.

set -euo pipefail

## Настраиваемые параметры

# CIDR подсети для Pod‑ов.  Calico и большинство CNI по умолчанию используют
# диапазон 192.168.0.0/16 или 10.244.0.0/16.  Можно переопределить через
# переменную окружения.
POD_NETWORK_CIDR=${POD_NETWORK_CIDR:-"10.244.0.0/16"}

echo "[+] Initialising Kubernetes control plane..."

sudo kubeadm init \
  --pod-network-cidr="${POD_NETWORK_CIDR}" \
  --upload-certs 2>&1 | tee /tmp/kubeadm-init.log

echo "[+] Kubernetes control plane initialised."

echo "[+] Configuring kubectl for the current user..."
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown $(id -u):$(id -g) "$HOME/.kube/config"

echo "[+] Generating worker join command..."
# Сохраняем команду присоединения для рабочих нод.  После выполнения
# kubeadm init, токен действителен 24 часа.  При необходимости можно
# пересоздать токен с помощью kubeadm token create.
kubeadm token create --print-join-command --ttl 24h > "$HOME/kubeadm_join.sh"
chmod +x "$HOME/kubeadm_join.sh"

echo "[+] Applying Calico CNI plugin..."
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

echo "[+] Kubernetes control plane is ready.  Use the generated join script"
echo "    $HOME/kubeadm_join.sh on each worker node."