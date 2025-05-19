#!/opt/homebrew/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/../.."

NAME="СПРО"
PID_FILE="$BASE/run/pids/spro.pid"

if [[ ! -f "$PID_FILE" ]]; then
    echo "$NAME не запущен (PID-файл не найден)"
    exit 1
fi

PID=$(cat "$PID_FILE")
kill "$PID" 2>/dev/null

# Ожидаем завершения
wait "$PID" 2>/dev/null

rm "$PID_FILE"
echo "$NAME остановлен"
