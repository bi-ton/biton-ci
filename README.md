## Biton CI/CD

### Подготовка серверов

Шаг 1. Инициализация SSH ключей. Добавление открытого SSH ключа в аккаунт github для доступа к приватным репозиториям с deploy сервера.
Выполняется удаленно, без захода на deploy сервер. Альтернативный вариант - перенести файл ssh/init.sh на deploy сервер и запустить его там.

Шаг 2. Подключение по SSH к deploy серверу.

Шаг 3. Клонирование репозитория с CI/CD системой.

Шаг 4. Подготовка файлов с переменными окружения, содержащих, в основном, секретные данные (адреса, пароли, ключи и т.д.).
В файле `.env` в переменной `COMPONENTS` перечисляются через запятую компоненты системы, которые будет обслуживать CI/CD.
В зависимости от суффикса в имени файла `env/.env*`, файл применяется к соответствующей ветке репозитория по имени суффикса, например, `env/.env.dev` - используется для ветки `dev`, если суффикса нет - `env/.env` - используется для ветки прода, название ветки прода определяется в файле `.env` (файл в корне репозитория) в переменной `PROD_BRANCH`.
Примеры env-файлов:
[.env.example](https://github.com/bi-ton/biton-ci/blob/main/.env.example)
[env/.env.example](https://github.com/bi-ton/biton-ci/blob/main/env/.env.example)

Шаг 5. Запуск инициализации.
На данном шаге осуществляется установка необходимых зависимостей на сервер:
`docker-compose` - для управления контейнерами
`python3-pip` - для установки paramiko
`paramiko` - для возможности удаленного управления контейнерами на серверах.
В `/etc/docker/daemon.json` помещается информация о доверенном нашем docker registry, который будет развернут на deploy сервере.
Устанавливается наш локальный docker registry - [docreg](https://github.com/msw-x/docreg).
Клонируется из репозитория, собирается и пушится [hwmon](https://github.com/msw-x/hwmon)  в наш docker registry. `hwmon` - система мониторинга аппаратных ресурсов на основе grafana и prometheus.
Утанавливается hwmon из нашего docker registry на deploy сервер.
Клонируется из репозитория, собирается и пушится [sws](https://github.com/msw-x/sws) - Simple Web server.
Для каждой ветки (на основе `env/.env*` файлов) и каждого компонента (на основе `COMPONENTS` из `.env`) клонируются репозитории компонентов и переключаются на соответствующие ветки.
Копирование публичного ключа deploy сервера на сервера с компонентами.
Установка необходимых зависимостей на серверах с компонентами: `docker-compose` и `hwmon`.

Шаг 6. [Build and deploy all](#build-and-deploy-all)


### Servers preparation

1. init SSH remotely (DEPLOY_HOST - address of deploy server):
```
cd ssh
./remote.sh DEPLOY_HOST
```

2. connect to deploy server:
```
ssh root@DEPLOY_HOST
```

3. clone deploy repository:
```
mkdir /opt/biton
cd /opt/biton
git clone git@github.com:bi-ton/biton-ci.git
cd biton-ci
```

4. preparing environment files:
```
cp .env.example .env
nano .env
cd env
cp .env.example .env
nano .env
cp .env.example .env.dev
nano .env.dev
cd ..
```

5. run init command:
```
./cmd.sh init
```


### Build components

```
ci build COMPONENT [BRANCH]
```
example build `biton-ui` for `dev`:
```
ci build biton-ui dev
```


### Deploy components

```
ci deploy COMPONENT [BRANCH]
```
example deploy `biton-ui` for `dev`:
```
ci deploy biton-ui dev
```


### Build and deploy all

```
ci update-all
```

### Down components

```
ci down COMPONENT [BRANCH]
```
example down `biton-ui` for `dev`:
```
ci down biton-ui dev
```

### Restart components

```
ci restart COMPONENT [BRANCH]
```
example restart `biton-ui` for `dev`:
```
ci restart biton-ui dev
```
