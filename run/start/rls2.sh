#!/opt/homebrew/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/../.."

NAME="РЛС-2"
PID_FILE="$BASE/run/pids/rls2.pid"
CMD="$BASE/rls/rls.sh --n 2 --x 3100 --y 3000 --azimuth 180 --view_angle 120 --radius 3500 --secret $1"

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
