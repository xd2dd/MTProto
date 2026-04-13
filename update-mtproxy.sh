#!/bin/bash

# Обновление конфигурации MTProto proxy (fake TLS)

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONFIG_FILE="${HOME}/mtproto_config.txt"
CONTAINER_NAME="mtproto-proxy"

echo -e "${BLUE}🔧 Обновление MTProto proxy${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Загружаем существующую конфигурацию
if [ -f "${CONFIG_FILE}" ]; then
  source "${CONFIG_FILE}" 2>/dev/null || true
  echo -e "📄 Текущая конфигурация из ${YELLOW}${CONFIG_FILE}${NC}:"
  echo "   Сервер:      ${SERVER:-не задан}"
  echo "   Порт:        ${PORT:-не задан}"
  echo "   Секрет:      ${SECRET:-не задан}"
  echo "   Fake домен:  ${DOMAIN:-не задан}"
  echo "   Ad Tag:      ${AD_TAG:-не задан}"
  echo "   MTU:         ${MTU:-не задан}"
  echo "   Ссылка:      ${LINK:-не задана}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo -e "${YELLOW}⚠️  Файл конфигурации не найден: ${CONFIG_FILE}${NC}"
  echo "Продолжаем без предыдущих настроек..."
fi

prompt_keep() {
  local prompt_text="$1"
  local current="$2"
  if [ -n "${current}" ]; then
    read -p "${prompt_text} [Enter = оставить '${current}']: " input
  else
    read -p "${prompt_text}: " input
  fi
  if [ -z "${input}" ]; then
    echo "${current}"
  else
    echo "${input}"
  fi
}

echo ""
echo "Нажмите Enter, чтобы оставить текущее значение. Введите новое — чтобы изменить."
echo ""

# 1) Порт
NEW_PORT=$(prompt_keep "Порт (443, 8443 и т.д.)" "${PORT:-443}")

# 2) Fake TLS домен
NEW_DOMAIN=$(prompt_keep "Fake TLS домен (под который маскируем трафик)" "${DOMAIN:-ya.ru}")

# 3) Секрет
echo ""
read -p "Изменить секрет? (y/N): " change_secret
change_secret=$(echo "${change_secret:-n}" | tr '[:upper:]' '[:lower:]')

if [ "${change_secret}" = "y" ]; then
  read -p "Сгенерировать новый секрет автоматически? (Y/n): " gen_new
  gen_new=$(echo "${gen_new:-y}" | tr '[:upper:]' '[:lower:]')
  if [ "${gen_new}" = "n" ]; then
    read -p "Введите секрет вручную (hex, с префиксом 'ee' для fake TLS): " NEW_SECRET
  else
    DOMAIN_HEX=$(echo -n "${NEW_DOMAIN}" | xxd -ps | tr -d '\n')
    DOMAIN_LEN=${#DOMAIN_HEX}
    NEEDED=$((30 - DOMAIN_LEN))
    if [ "${NEEDED}" -le 0 ]; then
      RANDOM_HEX=""
    else
      RANDOM_HEX=$(openssl rand -hex $(((NEEDED+1)/2)) 2>/dev/null | cut -c1-${NEEDED})
    fi
    NEW_SECRET="ee${DOMAIN_HEX}${RANDOM_HEX}"
    echo -e "Сгенерирован секрет: ${YELLOW}${NEW_SECRET}${NC}"
  fi
else
  NEW_SECRET="${SECRET}"
fi

# 4) Рекламный тег (Ad Tag) от @MTProxybot
echo ""
echo -e "${BLUE}ℹ️  Ad Tag можно получить у бота @MTProxybot в Telegram (команда /newproxy).${NC}"
NEW_AD_TAG=$(prompt_keep "Рекламный тег Ad Tag (hex, 32 символа) или пусто чтобы убрать" "${AD_TAG:-}")

# 5) MTU
echo ""
read -p "Изменить MTU? (y/N): " change_mtu
change_mtu=$(echo "${change_mtu:-n}" | tr '[:upper:]' '[:lower:]')
NEW_MTU="${MTU:-}"
if [ "${change_mtu}" = "y" ]; then
  read -p "Введите MTU (1400-1500) или Enter чтобы убрать: " input_mtu
  NEW_MTU="${input_mtu}"
fi

# Итог — показываем что изменится
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}📋 Новые параметры:${NC}"
echo "   Порт:        ${NEW_PORT}"
echo "   Fake домен:  ${NEW_DOMAIN}"
echo "   Секрет:      ${NEW_SECRET}"
echo "   Ad Tag:      ${NEW_AD_TAG:-не задан}"
echo "   MTU:         ${NEW_MTU:-не задан}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

read -p "Применить и перезапустить контейнер? (Y/n): " confirm
confirm=$(echo "${confirm:-y}" | tr '[:upper:]' '[:lower:]')
if [ "${confirm}" != "y" ]; then
  echo "Отменено."
  exit 0
fi

# Останавливаем старый контейнер
echo -n "🛑 Остановка контейнера ${CONTAINER_NAME}... "
sudo docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
sudo docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
echo -e "${GREEN}готово${NC}"

# Настройка сети с MTU
NET_NAME=""
if [ -n "${NEW_MTU}" ] && [[ "${NEW_MTU}" =~ ^[0-9]+$ ]]; then
  NET_NAME="mtproto-net-${NEW_PORT}"
  echo "⚙️  Настройка Docker сети с MTU=${NEW_MTU}..."
  if sudo docker network inspect "${NET_NAME}" >/dev/null 2>&1; then
    echo "   Сеть ${NET_NAME} уже существует."
  else
    if sudo docker network create --driver bridge --opt com.docker.network.driver.mtu="${NEW_MTU}" "${NET_NAME}" >/dev/null 2>&1; then
      echo -e "   ${GREEN}Сеть создана: ${NET_NAME}${NC}"
    else
      echo -e "   ${YELLOW}Не удалось создать сеть с MTU. Запускаем в стандартной сети.${NC}"
      NET_NAME=""
    fi
  fi
fi

# Строим команду запуска
DOCKER_RUN_CMD=(sudo docker run -d --name "${CONTAINER_NAME}" --restart unless-stopped)

if [ -n "${NET_NAME}" ]; then
  DOCKER_RUN_CMD+=(--network "${NET_NAME}")
fi

DOCKER_RUN_CMD+=(-p "${NEW_PORT}":443)
DOCKER_RUN_CMD+=(-e "SECRET=${NEW_SECRET}")

# Добавляем Ad Tag если задан
if [ -n "${NEW_AD_TAG}" ]; then
  DOCKER_RUN_CMD+=(-e "TAG=${NEW_AD_TAG}")
fi

DOCKER_RUN_CMD+=(telegrammessenger/proxy)

# Запуск
echo -n "📦 Запуск контейнера... "
if "${DOCKER_RUN_CMD[@]}" >/dev/null 2>&1; then
  sleep 2
  if sudo docker ps --filter "name=${CONTAINER_NAME}" --filter "status=running" --format '{{.Names}}' | grep -q "${CONTAINER_NAME}"; then

    # Получаем внешний IPv4
    SERVER_IP=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s ipinfo.io/ip 2>/dev/null || echo "${SERVER:-}")
    if [ -z "${SERVER_IP}" ]; then
      read -p "Введите внешний IPv4 адрес вашего сервера: " SERVER_IP
    fi

    NEW_LINK="tg://proxy?server=${SERVER_IP}&port=${NEW_PORT}&secret=${NEW_SECRET}"

    echo -e "${GREEN}✅ УСПЕШНО${NC}"
    echo ""
    echo "📊 НОВЫЕ ДАННЫЕ ДЛЯ ПОДКЛЮЧЕНИЯ:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌐 Сервер (IPv4): ${SERVER_IP}"
    echo "🔌 Порт:          ${NEW_PORT}"
    echo "🔑 Секрет:        ${NEW_SECRET}"
    echo "🌐 Fake домен:    ${NEW_DOMAIN}"
    [ -n "${NEW_AD_TAG}" ] && echo "📢 Ad Tag:         ${NEW_AD_TAG}"
    [ -n "${NEW_MTU}" ]    && echo "⚙️  MTU:            ${NEW_MTU}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔗 Ссылка для Telegram:"
    echo -e "${GREEN}${NEW_LINK}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Сохраняем обновлённую конфигурацию
    cat > "${CONFIG_FILE}" <<EOF
SERVER=${SERVER_IP}
PORT=${NEW_PORT}
SECRET=${NEW_SECRET}
DOMAIN=${NEW_DOMAIN}
AD_TAG=${NEW_AD_TAG}
LINK=${NEW_LINK}
MTU=${NEW_MTU}
EOF
    echo -e "✅ Конфигурация обновлена: ${YELLOW}${CONFIG_FILE}${NC}"

    echo ""
    echo "📋 Последние логи контейнера:"
    sudo docker logs --tail 5 "${CONTAINER_NAME}" || true

  else
    echo -e "\n${RED}❌ Контейнер не запущен. Проверьте логи:${NC}"
    sudo docker logs "${CONTAINER_NAME}" || true
    exit 1
  fi
else
  echo -e "\n${RED}❌ Ошибка при запуске контейнера.${NC}"
  exit 1
fi
