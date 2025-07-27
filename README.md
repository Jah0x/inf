# VPN‑infra Kubernetes Repository
#
# Этот репозиторий содержит скрипты и манифесты для автоматизированного
# развёртывания VPN‑сервиса на базе Kubernetes.  Инфраструктура объединяет
# графическую панель Headlamp, админ‑панель Marzban для управления Xray,
# frontend и backend из проекта VPN, сервис подписок, базу данных PostgreSQL
# и Grafana для мониторинга.  Все компоненты развёртываются в рамках
# пространства имён `vpn‑infra` и могут быть масштабированы независимо.

## Структура репозитория

```
config/     # примеры конфигураций и файлы инициализации
manifests/  # Kubernetes‑манифесты
scripts/    # вспомогательные скрипты для настройки кластера
docs/       # дополнительная документация
```

## Обзор компонентов

- **Headlamp** – веб‑интерфейс для управления кластером Kubernetes.  При
  развёртывании в кластере Headlamp использует сервисный аккаунт по
  умолчанию; при необходимости можно смонтировать собственный kubeconfig
  и указать переменную `KUBECONFIG`【45099263155973†L77-L84】.
- **Marzban** – админ‑панель для Xray.  Переменные окружения Marzban
  описаны в официальной документации: параметры `SUDO_USERNAME`,
  `SUDO_PASSWORD`, `SQLALCHEMY_DATABASE_URL`, `XRAY_JSON` и другие можно
  задавать через `.env` файл【46485567583785†L334-L444】.
- **VPN‑backend / API** – серверная часть проекта [vpn_project](https://github.com/Jah0x/vpn_project).  Для
  корректной работы необходимо указать `DATABASE_URL` и `SERVER_PORT`
  (по умолчанию 8080)【897932875963233†L88-L91】, а также параметры
  логирования `LOG_LEVEL`, `LOG_FILE_ENABLED` и `PINO_PRETTY_DISABLE`【897932875963233†L101-L107】.
- **VPN‑frontend** – клиентская часть, которая обращается к API по пути `/api`.
- **PostgreSQL** – база данных, используемая как Marzban, так и VPN‑backend.
- **Subscription service** – простая статическая страница, отдающая ссылки на
  подписку.  Реализована как контейнер Nginx и может быть заменена на
  полноценный сервис.
- **Grafana** – инструмент визуализации метрик и дашбордов.

Более подробная схема доменов и IP‑адресов приведена в файле
[`ip_tree.md`](docs/ip_tree.md).

## Предварительные требования

1. **Аппаратное обеспечение.**  Минимум три сервера (или виртуальные
   машины) с Ubuntu 20.04/22.04, один из которых временно выполняет роль
   control‑plane.  Две или более рабочих ноды предназначены для VPN‑трафика,
   ещё одна — для внутренней инфраструктуры.
2. **Статические IP‑адреса.**  По одному IP для каждой ноды, обслуживающей
   VPN‑трафик, и один IP для ingress‑балансировщика.  Схема приведена в
  [`ip_tree.md`](docs/ip_tree.md).
3. **Доменное имя.**  Настройте записи A для всех поддоменов (headlamp,
   marzban, api, sub, grafana и основной домен) на IP ingress‑балансировщика.
4. **Программное обеспечение.**  kubeadm, kubelet, kubectl, Calico или
   другой CNI, nginx‑ingress‑controller и (опционально) MetalLB и
   cert‑manager.

## Шаг 1. Инициализация кластера

На первой ноде выполните скрипт `scripts/kubeadm-init.sh`:

```bash
sudo bash scripts/kubeadm-init.sh
```

Скрипт запустит `kubeadm init` с подсетью Pod‑ов (по умолчанию `10.244.0.0/16`),
сохранит команду для присоединения рабочих нод в файл `~/kubeadm_join.sh` и
применит Calico как CNI.  Затем скопируйте файл `~/kubeadm_join.sh` на каждую
рабочую ноду и выполните его с правами root.  После того как все рабочие ноды
подключены, control‑plane может быть выключен (его конфигурация сохранена в
`/etc/kubernetes/admin.conf`).

## Шаг 2. Маркировка нод

Для разделения трафика назначьте метки на рабочие ноды:

```bash
# Ноды для внутренней инфраструктуры (Headlamp, Marzban, API, Grafana)
kubectl label node INFRA_NODE_NAME vpn-infra-role=infra

# Ноды для VPN‑трафика (Xray)
kubectl label node TRAFFIC_NODE_NAME vpn-infra-role=traffic
```

Манифесты в каталоге `manifests/` используют `nodeSelector` для
распределения компонентов по ролям.  При необходимости можно изменить
метки в манифестах.

## Шаг 3. Построение и публикация образов

В репозитории [vpn_project](https://github.com/Jah0x/vpn_project) отсутствуют
готовые образы для Kubernetes, поэтому необходимо собрать собственные:

```bash
# Соберите образ backend
docker build -t your-registry/vpn-backend:latest -f apps/server/Dockerfile .

# Соберите образ frontend (React/Vite)
docker build -t your-registry/vpn-frontend:latest -f Dockerfile.frontend .

# Опубликуйте образы в своём реестре
docker push your-registry/vpn-backend:latest
docker push your-registry/vpn-frontend:latest
```

Затем отредактируйте манифесты `vpn-backend-deployment.yaml` и
`vpn-frontend-deployment.yaml`, указав правильные имена образов.

## Шаг 4. Настройка переменных окружения

Скопируйте файл `config/.env.example` в `.env` и заполните все переменные.
Значения по умолчанию указаны для примера; не забудьте задать сложные
пароли и ключи.

Создайте секрет в Kubernetes из заполненного `.env` файла:

```bash
kubectl create namespace vpn-infra || true
kubectl create secret generic vpn-infra-env \
  --from-env-file=.env \
  -n vpn-infra
```

Секрет будет использоваться всеми Deployment’ами через `envFrom`.

## Шаг 5. Применение манифестов


Примените конфигурации вручную, как показано ниже, или воспользуйтесь
автоматическим скриптом `scripts/deploy.sh`, который выполнит эти
действия за вас:

```bash
bash scripts/deploy.sh
```

Если предпочитаете выполнять команды вручную:

```bash
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/postgres-configmap.yaml
kubectl apply -f manifests/postgres-statefulset.yaml
kubectl apply -f manifests/xray-configmap.yaml
kubectl apply -f manifests/marzban-deployment.yaml
kubectl apply -f manifests/headlamp-configmap.yaml
kubectl apply -f manifests/headlamp-deployment.yaml
kubectl apply -f manifests/vpn-backend-deployment.yaml
kubectl apply -f manifests/vpn-frontend-deployment.yaml
kubectl apply -f manifests/subscription-configmap.yaml
kubectl apply -f manifests/subscription-deployment.yaml
kubectl apply -f manifests/grafana-deployment.yaml
kubectl apply -f manifests/network-policy.yaml
```

Если вы используете MetalLB, примените также `manifests/metallb-config.yaml` и
предварительно установите MetalLB в кластер.  При желании настройте
сертификаты Let’s Encrypt с помощью cert‑manager, применив
`manifests/cert-manager.yaml`.  Файл `manifests/ingress.yaml` содержит
Ingress‑правила для всех доменов; перед применением выполните
`envsubst` для подстановки значений из `.env`:

```bash
envsubst < manifests/ingress.yaml | kubectl apply -f -
```

## Шаг 6. Инициализация базы данных

Контейнер PostgreSQL запускает файл `init.sql`, который создаёт
расширение `pgcrypto`.  После запуска StatefulSet примените миграции для
backend‑проекта:

```bash
kubectl exec -n vpn-infra deploy/vpn-backend -- npx prisma migrate deploy
```

Marzban создаёт структуру своей базы автоматически при первом запуске, в том
числе пользователей супер‑администратора, указанных в `.env`【46485567583785†L334-L444】.

## Доступ к сервисам

После успешного развёртывания настройте DNS и получите TLS‑сертификаты.  В
итоге сервисы будут доступны по следующим адресам (предполагается, что
переменные в `.env` заполнены):

- **Headlamp:** `https://$HEADLAMP_SUBDOMAIN` — веб‑UI для управления Kubernetes.
- **Marzban:** `https://$MARZBAN_SUBDOMAIN` — админ‑панель для Xray.  Логин
  и пароль определяются переменными `SUDO_USERNAME` и `SUDO_PASSWORD`.
- **VPN API:** `https://$VPN_API_SUBDOMAIN` — backend, реализующий API и
  аутентификацию.  Точка `/health` возвращает состояние сервиса.
- **Основной сайт:** `https://$VPN_FRONTEND_SUBDOMAIN` — клиентское
  приложение, автоматически обращается к API по `/api`.
- **Подписки:** `https://$SUBSCRIPTION_SUBDOMAIN` — простая страница с
  информацией о подписках.  В будущем здесь можно разместить генерацию
  ссылок V2Ray/Clash.
- **Grafana:** `https://$GRAFANA_SUBDOMAIN` — мониторинг.  Войти можно под
  учётной записью `GRAFANA_ADMIN_USER`/`GRAFANA_ADMIN_PASSWORD`.

## Безопасность и надёжность

- **Firewall и сетевые политики.**  Разрешите входящий трафик только на
  необходимые порты (80/443 на ingress, 5432 для PostgreSQL — только из
  внутренней сети).  В репозитории присутствуют примеры NetworkPolicy,
  запрещающие весь трафик по умолчанию и разрешающие доступ к PostgreSQL
  только от backend и Marzban.
- **Изоляция узлов.**  Разделите ноды по ролям (трафик/инфраструктура), как
  описано выше.  Для Xray рекомендуется выделять отдельные IP‑адреса, чтобы
  сократить риск блокировок.
- **Масштабируемость.**  Увеличивайте количество реплик backend и frontend
  через параметр `replicas` в манифестах.  Для Xray (Marzban nodes)
  используйте дополнительные рабочие ноды с меткой `vpn-infra-role=traffic`.
- **Отказоустойчивость.**  Используйте как минимум две реплики backend и
  frontend.  Для базы данных можно настроить репликацию или использовать
  управляемый PostgreSQL‑кластер.
- **Бэкапы.**  Регулярно выполняйте бэкапы директории `postgres-data` и
  `marzban-data`.  Для Marzban предусмотрен встроенный механизм резервного
  копирования, описанный в документации【46485567583785†L474-L488】.

## FAQ

**Как изменить CIDR для Pod‑ов?**

Укажите переменную окружения `POD_NETWORK_CIDR` перед запуском
`kubeadm-init.sh`, например:

```bash
export POD_NETWORK_CIDR=192.168.0.0/16
sudo bash scripts/kubeadm-init.sh
```

**Как добавить ещё один VPN‑узел?**

Разверните новую ноду, присоедините её к кластеру при помощи
`kubeadm_join.sh`, пометьте меткой `vpn-infra-role=traffic` и добавьте её IP
и DNS в [`ip_tree.md`](docs/ip_tree.md).  Marzban автоматически будет управлять узлом через
свой REST API.

**Где найти переменные окружения для Marzban?**

Полный список переменных приведён в документации Marzban【46485567583785†L334-L444】.  В
файле `config/.env.example` присутствуют наиболее важные из них с пояснениями.

**Как настроить Headlamp с несколькими kubeconfig’ами?**

Можно смонтировать несколько kubeconfig файлов и указать переменную
`KUBECONFIG` с путями, разделёнными двоеточием, как описано в документации
Headlamp【45099263155973†L77-L84】.