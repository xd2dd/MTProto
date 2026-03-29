#!/bin/bash

# Цвета для красивого вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONTAINER_NAME="mtproto-proxy"
PORT="443"
FAKE_DOMAIN="ya.ru"  # Домен для Fake TLS

echo "🚀 Запуск MTProto прокси с Fake TLS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "📌 Используем домен: ${BLUE}${FAKE_DOMAIN}${NC}"

# Генерируем правильный секрет для Fake TLS (формат: ee + 16 байт ключа + hex домена)
echo -n "🔑 Генерация Fake TLS секрета... "

# Генерируем 16 случайных байт (32 hex символа)
KEY=$(openssl rand -hex 16)

# Получаем hex домена
DOMAIN_HEX=$(echo -n $FAKE_DOMAIN | xxd -ps | tr -d '\n')

# Собираем секрет в правильном формате
SECRET="ee${KEY}${DOMAIN_HEX}"

echo -e "${GREEN}готово${NC}"
echo -e "   Секрет: ${YELLOW}${SECRET}${NC}"
echo "   Длина: ${#SECRET} символов (должно быть 44)"

# Удаляем старый контейнер ДО проверки порта
echo -n "🛑 Удаление старого контейнера... "
sudo docker rm -f ${CONTAINER_NAME} >/dev/null 2>&1
echo -e "${GREEN}готово${NC}"

# Проверяем, свободен ли порт (только IPv4)
echo -n "🔍 Проверка порта ${PORT} (IPv4)... "
if ss -4tuln | grep -q ":${PORT} "; then
    echo -e "${YELLOW}порт занят${NC}"
    # Ищем альтернативный порт
    for alt_port in 8443 8444 8445; do
        if ! ss -4tuln | grep -q ":${alt_port} "; then
            PORT=$alt_port
            echo "   Используем порт: ${PORT}"
            break
        fi
    done
else
    echo -e "${GREEN}свободен${NC}"
fi

# Определяем IPv4 адрес сервера
echo -n "🌐 Определение IPv4 адреса... "
SERVER_IP=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null || curl -4 -s ipinfo.io/ip 2>/dev/null)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi
echo -e "${GREEN}${SERVER_IP}${NC}"

# Запускаем контейнер с правильным образом (nineseconds/mtg)
echo -n "📦 Запуск контейнера... "
sudo docker run -d \
  --name ${CONTAINER_NAME} \
  --restart unless-stopped \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  -p ${PORT}:443 \
  nineseconds/mtg:2 \
  simple-run -n 1.1.1.1 -i prefer-ipv4 0.0.0.0:${PORT} ${SECRET} > /dev/null 2>&1

# Проверяем результат
sleep 3
if sudo docker ps | grep -q ${CONTAINER_NAME}; then
    echo -e "${GREEN}✅ УСПЕШНО${NC}"
    echo ""
    echo "📊 ИНФОРМАЦИЯ ДЛЯ ПОДКЛЮЧЕНИЯ:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌐 Сервер (IPv4): ${SERVER_IP}"
    echo "🔌 Порт: ${PORT}"
    echo "🔑 Секрет: ${SECRET}"
    echo "🌐 Fake TLS домен: ${FAKE_DOMAIN}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔗 Ссылка для Telegram (нажмите для автоподключения):"
    echo -e "${GREEN}tg://proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Сохраняем конфигурацию
    cat > ~/mtproto_config.txt << EOF
SERVER=${SERVER_IP}
PORT=${PORT}
SECRET=${SECRET}
DOMAIN=${FAKE_DOMAIN}
LINK=tg://proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}
EOF
    echo "✅ Конфигурация сохранена в ~/mtproto_config.txt"
    
    # Показываем последние логи
    echo ""
    echo "📋 Логи контейнера:"
    sudo docker logs --tail 5 ${CONTAINER_NAME}
    
    # Проверяем, что контейнер использует порт
    echo ""
    echo "🔍 Проверка сетевых привязок (только IPv4):"
    sudo ss -4tulpn | grep ${PORT} || echo "   Порт ${PORT} не найден в IPv4"
else
    echo -e "${RED}❌ ОШИБКА${NC}"
    sudo docker logs ${CONTAINER_NAME}
fi
