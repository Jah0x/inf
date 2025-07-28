#!/bin/bash
# deploy.sh — полное развёртывание инфраструктуры VPN
#
# Этот скрипт предназначен для запуска на мастер-ноде после того, как кластер
# Kubernetes и рабочие ноды уже инициализированы (kubeadm init / join).
# Он применяет все манифесты и необходимые секреты.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if ! command -v kubectl >/dev/null; then
  echo "kubectl не установлен. Пожалуйста, установите kubectl и повторите." >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Файл .env не найден в корне репозитория. Заполните его на основе config/.env.example" >&2
  exit 1
fi

# Создаём namespace и секреты
kubectl create namespace vpn-infra || true
kubectl delete secret vpn-infra-env -n vpn-infra >/dev/null 2>&1 || true
kubectl create secret generic vpn-infra-env --from-env-file="$ENV_FILE" -n vpn-infra

# Применяем манифесты
MANIFESTS=(
  namespace.yaml
  postgres-configmap.yaml
  postgres-statefulset.yaml
  xray-configmap.yaml
  marzban-deployment.yaml
  headlamp-configmap.yaml
  headlamp-deployment.yaml
  grafana-deployment.yaml
  network-policy.yaml
)

for m in "${MANIFESTS[@]}"; do
  echo "[+] kubectl apply -f manifests/$m"
  kubectl apply -f "$REPO_ROOT/manifests/$m"
  sleep 1
done

# Опциональные манифесты
if [ -f "$REPO_ROOT/manifests/metallb-config.yaml" ]; then
  echo "[+] Применяем MetalLB"
  kubectl apply -f "$REPO_ROOT/manifests/metallb-config.yaml"
fi

if [ -f "$REPO_ROOT/manifests/cert-manager.yaml" ]; then
  echo "[+] Применяем cert-manager и сертификаты"
  kubectl apply -f "$REPO_ROOT/manifests/cert-manager.yaml"
fi

# Ingress с подстановкой переменных окружения
if [ -f "$REPO_ROOT/manifests/ingress.yaml" ]; then
  echo "[+] Применяем ingress"
  envsubst < "$REPO_ROOT/manifests/ingress.yaml" | kubectl apply -f -
fi

echo "[+] Готово. Проверяйте статус pod'ов командой kubectl get pods -n vpn-infra"

