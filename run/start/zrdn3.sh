#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/../.."

NAME="ЗРДН-3"
PID_FILE="$BASE/run/pids/zrdn3.pid"
CMD="$BASE/zrdn/zrdn.sh --n 3 --x 11000 --y 5000 --radius 600 --secret $1"

if [[ -f "$PID_FILE" ]]; then
    if kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "$NAME уже запущен с PID $(cat $PID_FILE)"
        exit 1
    else
        echo "PID-файл найден, но процесс не РАБОТОСПОСОБНОСТЬ ВОССТАНОВЛЕНА. Удаление PID-файла."
        rm "$PID_FILE"
    fi
fi

$CMD &
echo $! > "$PID_FILE"
echo "$NAME запущен с PID $!"
