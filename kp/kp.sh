#!/opt/homebrew/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/.."

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --secret) secret="$2"; shift 2 ;;
            *)
                echo "Ошибка: Неизвестный параметр: $1"
                exit 1
                ;;
        esac
    done

    # Проверяем, переданы ли все обязательные параметры
    if [[ -z "$secret" ]]; then
        echo "Ошибка: Необходимо передать все параметры!"
        echo "Использование: $0 --secret <value>"
        exit 1
    fi
}

parse_args "$@"

KP_DB_FILE="$BASE/kp/kp.db"
KP_LOG_FILE="$BASE/kp/kp.log"
LOG_FILE="$BASE/pro.log"
KP_MESSAGES_DIR="$BASE/kp/Messages"
RLS_MESSAGES_DIR="$BASE/rls/Messages"
ZRDN_MESSAGES_DIR="$BASE/zrdn/Messages"
SPRO_MESSAGES_DIR="$BASE/spro/Messages"
RLS_LOG_DIR="$BASE/rls/Log"
ZRDN_LOG_DIR="$BASE/zrdn/Log"
SPRO_LOG_DIR="$BASE/spro/Log"
NSD_DIR="$BASE/nsd"

mkdir -p "$KP_MESSAGES_DIR"
mkdir -p "$RLS_MESSAGES_DIR"
mkdir -p "$ZRDN_MESSAGES_DIR"
mkdir -p "$SPRO_MESSAGES_DIR"
mkdir -p "$RLS_LOG_DIR"
mkdir -p "$ZRDN_LOG_DIR"
mkdir -p "$SPRO_LOG_DIR"
mkdir -p "$NSD_DIR"

states=(1 1 1 1 1 1 1)
pongs_it=(0 0 0 0 0 0 0)
iteration=0
reloads=0
nsd=0
pings=0
it_freq=20

initialize_db() {
    sqlite3 "$KP_DB_FILE" <<EOF
DROP TABLE IF EXISTS shots;
DROP TABLE IF EXISTS targets;
CREATE TABLE IF NOT EXISTS shots (
    name TEXT,
    target_id TEXT,
    PRIMARY KEY (name, target_id)
);
CREATE TABLE IF NOT EXISTS targets (
    id TEXT PRIMARY KEY,
    x INTEGER,
    y INTEGER,
    speed FLOAT,
    killer TEXT,
    to_spro INTEGER DEFAULT 0,
    target_type TEXT,
    updated_at TEXT,
    FOREIGN KEY(killer) REFERENCES shots(name)
);
EOF
}

query_db() {
    sqlite3 "$KP_DB_FILE" "$1"
}

verify_message() {
    local source="$1"
    read -r sec _ < "$source"
    if [[ "$sec" != "$secret" ]]; then
        return 1
    else
        return 0
    fi
}

initialize_db

while true; do
    (( iteration++ ))

    files=($(find "$KP_MESSAGES_DIR" -type f))

    for file in "${files[@]}"; do
        filename="$(basename "$file")"
        time=$(date +"%T")

        if ! verify_message "$KP_MESSAGES_DIR/$filename"; then
            (( nsd++ ))
            echo "[$time] [КП] файл='${filename}_${nsd}' ПОПЫТКА НСД!" >> "$LOG_FILE"
            echo "[$time] файл='${filename}_${nsd}' ПОПЫТКА НСД!" >> "$KP_LOG_FILE"
            mv "$KP_MESSAGES_DIR/$filename" "$NSD_DIR/${filename}_${nsd}"
            continue
        fi

        if [[ $filename =~ ^rls_([0-9]+)_message_([0-9]+)$ ]]; then
            rls_number="${BASH_REMATCH[1]}"
            read -r _ timestamp target_id x y type speed to_spro < "$file"
            if (( to_spro == 0 )); then
                query_db "INSERT INTO targets (id, x, y, speed, target_type, updated_at) VALUES ('$target_id', $x, $y, $speed, '$type', '$timestamp') ON CONFLICT(id) DO NOTHING;"
                echo "[$timestamp] [РЛС-$rls_number] цель ID=$target_id тип=$type с координатами X=$x Y=$y движется со скоростью $speed м/с" >> "$LOG_FILE"
                echo "[$timestamp] цель ID=$target_id тип=$type с координатами X=$x Y=$y движется со скоростью $speed м/с" >> "$RLS_LOG_DIR/rls_$rls_number.log"
            else
                query_db "INSERT INTO targets (id, x, y, speed, target_type, to_spro, updated_at) VALUES ('$target_id', $x, $y, $speed, '$type', 1, '$timestamp') ON CONFLICT(id) DO NOTHING;"
                echo "[$timestamp] [РЛС-$rls_number] цель ID=$target_id тип=$type с координатами X=$x Y=$y движется со скоростью $speed м/с в направлении СПРО" >> "$LOG_FILE"
                echo "[$timestamp] цель ID=$target_id тип=$type с координатами X=$x Y=$y движется со скоростью $speed м/с в сторону СПРО" >> "$RLS_LOG_DIR/rls_$rls_number.log"
            fi

        elif [[ $filename =~ ^zrdn_([0-9]+)_message_([0-9]+)$ ]]; then
            zrdn_number="${BASH_REMATCH[1]}"
            read -r _ timestamp target_id x y type speed < "$file"
            query_db "INSERT INTO targets (id, x, y, speed, target_type, updated_at) VALUES ('$target_id', $x, $y, $speed, '$type', '$timestamp') ON CONFLICT(id) DO NOTHING;"
            echo "[$timestamp] [ЗРДН-$zrdn_number] цель ID=$target_id тип=$type с координатами X=$x Y=$y движется со скоростью $speed м/с" >> "$LOG_FILE"
            echo "[$timestamp] цель ID=$target_id тип=$type с координатами X=$x Y=$y движется со скоростью $speed м/с" >> "$ZRDN_LOG_DIR/zrdn_$zrdn_number.log"

        elif [[ $filename =~ ^spro_message_([0-9]+)$ ]]; then
            read -r _ timestamp target_id x y type speed < "$file"
            query_db "INSERT INTO targets (id, x, y, speed, target_type, updated_at) VALUES ('$target_id', $x, $y, $speed, '$type', '$timestamp') ON CONFLICT(id) DO NOTHING;"
            echo "[$timestamp] [СПРО] цель ID=$target_id тип=$type с координатами X=$x Y=$y движется со скоростью $speed м/с" >> "$LOG_FILE"
            echo "[$timestamp] цель ID=$target_id тип=$type с координатами X=$x Y=$y движется со скоростью $speed м/с" >> "$SPRO_LOG_DIR/spro.log"

        elif [[ $filename =~ ^zrdn_([0-9]+)_shot_([0-9]+)$ ]]; then
            zrdn_number="${BASH_REMATCH[1]}"
            read -r _ timestamp target_id < "$file"
            query_db "INSERT INTO shots (name, target_id) VALUES ('zrdn-$zrdn_number', '$target_id');"

        elif [[ $filename =~ ^zrdn_([0-9]+)_success_([0-9]+)$ ]]; then
            zrdn_number="${BASH_REMATCH[1]}"
            read -r _ timestamp target_id < "$file"
            query_db "UPDATE targets SET killer='zrdn-$zrdn_number', updated_at='$timestamp' WHERE id='$target_id';"
            echo "[$timestamp] [ЗРДН-$zrdn_number] цель ID=$target_id СБИТА" >> "$LOG_FILE"
            echo "[$timestamp] цель ID=$target_id СБИТА" >> "$ZRDN_LOG_DIR/zrdn_$zrdn_number.log"

        elif [[ $filename =~ ^zrdn_([0-9]+)_fail_([0-9]+)$ ]]; then
            zrdn_number="${BASH_REMATCH[1]}"
            read -r _ timestamp target_id < "$file"
            echo "[$timestamp] [ЗРДН-$zrdn_number] цель ID=$target_id ПРОМАХ" >> "$LOG_FILE"
            echo "[$timestamp] цель ID=$target_id ПРОМАХ" >> "$ZRDN_LOG_DIR/zrdn_$zrdn_number.log"

        elif [[ $filename =~ ^zrdn_([0-9]+)_empty$ ]]; then
            zrdn_number="${BASH_REMATCH[1]}"
            read -r _ timestamp < "$file"
            echo "[$timestamp] [ЗРДН-$zrdn_number] боекомлект пуст" >> "$LOG_FILE"
            echo "[$timestamp] боекомлект пуст" >> "$ZRDN_LOG_DIR/zrdn_$zrdn_number.log"
            (( reloads++ ))
            echo "$secret 20" >> "$ZRDN_MESSAGES_DIR/zrdn_${zrdn_number}_reload_$reloads"

        elif [[ $filename =~ ^zrdn_([0-9]+)_reload_([0-9]+)$ ]]; then
            zrdn_number="${BASH_REMATCH[1]}"
            read -r _ timestamp cnt < "$file"
            echo "[$timestamp] [ЗРДН-$zrdn_number] боекомлект пополнен на $cnt ракет" >> "$LOG_FILE"
            echo "[$timestamp] боекомлект пополнен на $cnt ракет" >> "$ZRDN_LOG_DIR/zrdn_$zrdn_number.log"

        elif [[ $filename =~ ^spro_shot_([0-9]+)$ ]]; then
            read -r _ timestamp target_id < "$file"
            query_db "INSERT INTO shots (name, target_id) VALUES ('spro', '$target_id');"

        elif [[ $filename =~ ^spro_success_([0-9]+)$ ]]; then
            read -r _ timestamp target_id < "$file"
            query_db "UPDATE targets SET killer='spro', updated_at='$timestamp' WHERE id='$target_id';"
            echo "[$timestamp] [СПРО] цель ID=$target_id СБИТА" >> "$LOG_FILE"
            echo "[$timestamp] цель ID=$target_id СБИТА" >> "$SPRO_LOG_DIR/spro.log"

        elif [[ $filename =~ ^spro_fail_([0-9]+)$ ]]; then
            read -r _ timestamp target_id < "$file"
            echo "[$timestamp] [СПРО] цель ID=$target_id ПРОМАХ" >> "$LOG_FILE"
            echo "[$timestamp] цель ID=$target_id ПРОМАХ" >> "$SPRO_LOG_DIR/spro.log"

        elif [[ $filename =~ ^spro_empty$ ]]; then
            read -r _ timestamp < "$file"
            echo "[$timestamp] [СПРО] боекомлект пуст" >> "$LOG_FILE"
            echo "[$timestamp] боекомлект пуст" >> "$SPRO_LOG_DIR/spro.log"
            (( reloads++ ))
            echo "$secret 10" >> "$SPRO_MESSAGES_DIR/spro_reload_$reloads"

        elif [[ $filename =~ ^spro_reload_([0-9]+)$ ]]; then
            read -r _ timestamp cnt < "$file"
            echo "[$timestamp] [СПРО] боекомлект пополнен на $cnt ракет" >> "$LOG_FILE"
            echo "[$timestamp] боекомлект пополнен на $cnt ракет" >> "$SPRO_LOG_DIR/spro.log"

        elif [[ $filename =~ ^rls_([0-9]+)_pong_([0-9]+)$ ]]; then
            rls_number="${BASH_REMATCH[1]}"
            if (( states[rls_number - 1] == 0 )); then
                echo "[$time] [РЛС-$rls_number] РАБОТОСПОСОБНОСТЬ ВОССТАНОВЛЕНА" >> "$LOG_FILE"
                echo "[$time] РАБОТОСПОСОБНОСТЬ ВОССТАНОВЛЕНА" >> "$RLS_LOG_DIR/rls_$rls_number.log"
                (( states[rls_number - 1]++ ))
            fi
            (( pongs_it[rls_number - 1] = iteration ))

        elif [[ $filename =~ ^zrdn_([0-9]+)_pong_([0-9]+)$ ]]; then
            zrdn_number="${BASH_REMATCH[1]}"
            if (( states[zrdn_number + 2] == 0 )); then
                echo "[$time] [ЗРДН-$zrdn_number] РАБОТОСПОСОБНОСТЬ ВОССТАНОВЛЕНА" >> "$LOG_FILE"
                echo "[$time] РАБОТОСПОСОБНОСТЬ ВОССТАНОВЛЕНА" >> "$ZRDN_LOG_DIR/zrdn_$zrdn_number.log"
                (( states[zrdn_number + 2]++ ))
            fi
            (( pongs_it[zrdn_number + 2] = iteration ))

        elif [[ $filename =~ ^spro_pong_([0-9]+)$ ]]; then
            if (( states[6] == 0 )); then
                echo "[$time] [СПРО] РАБОТОСПОСОБНОСТЬ ВОССТАНОВЛЕНА" >> "$LOG_FILE"
                echo "[$time] РАБОТОСПОСОБНОСТЬ ВОССТАНОВЛЕНА" >> "$SPRO_LOG_DIR/spro.log"
                (( states[6]++ ))
            fi
            (( pongs_it[6] = iteration ))

        elif [[ $filename =~ ^rls_([0-9]+)_nsd_([0-9]+)$ ]]; then
            rls_number="${BASH_REMATCH[1]}"
            read -r _ nsd_name < "$file"
            echo "[$time] [РЛС-$rls_number] файл='$nsd_name' ПОПЫТКА НСД!" >> "$LOG_FILE"
            echo "[$time] файл='$nsd_name' ПОПЫТКА НСД!" >> "$RLS_LOG_DIR/rls_$rls_number.log"

        elif [[ $filename =~ ^zrdn_([0-9]+)_nsd_([0-9]+)$ ]]; then
            zrdn_number="${BASH_REMATCH[1]}"
            read -r _ nsd_name < "$file"
            echo "[$time] [ЗРДН-$zrdn_number] файл='$nsd_name' ПОПЫТКА НСД!" >> "$LOG_FILE"
            echo "[$time] файл='$nsd_name' ПОПЫТКА НСД!" >> "$ZRDN_LOG_DIR/zrdn_$zrdn_number.log"

        elif [[ $filename =~ ^spro_nsd_([0-9]+)$ ]]; then
            read -r _ nsd_name < "$file"
            echo "[$time] [СПРО] файл='$nsd_name' ПОПЫТКА НСД!" >> "$LOG_FILE"
            echo "[$time] файл='$nsd_name' ПОПЫТКА НСД!" >> "$SPRO_LOG_DIR/spro.log"

#        else
#            echo "unhandled file: filename='$filename'"

        fi

        rm "$KP_MESSAGES_DIR/$filename"
    done

    if (( iteration % it_freq == 0 )); then
        time=$(date +"%T")
        if (( pongs_it[0] + 3*it_freq < iteration )) && (( states[0] == 1 )); then
            echo "[$time] [РЛС-1] СЛОМАЛАСЬ" >> "$LOG_FILE"
            echo "[$time] СЛОМАЛАСЬ" >> "$RLS_LOG_DIR/rls_1.log"
            (( states[0]-- ))
        fi
        if (( pongs_it[1] + 3*it_freq < iteration )) && (( states[1] == 1 )); then
            echo "[$time] [РЛС-2] СЛОМАЛАСЬ" >> "$LOG_FILE"
            echo "[$time] СЛОМАЛАСЬ" >> "$RLS_LOG_DIR/rls_2.log"
            (( states[1]-- ))
        fi
        if (( pongs_it[2] + 3*it_freq < iteration )) && (( states[2] == 1 )); then
            echo "[$time] [РЛС-3] СЛОМАЛАСЬ" >> "$LOG_FILE"
            echo "[$time] СЛОМАЛАСЬ" >> "$RLS_LOG_DIR/rls_3.log"
            (( states[2]-- ))
        fi
        if (( pongs_it[3] + 3*it_freq < iteration )) && (( states[3] == 1 )); then
            echo "[$time] [ЗРДН-1] СЛОМАЛАСЬ" >> "$LOG_FILE"
            echo "[$time] СЛОМАЛАСЬ" >> "$ZRDN_LOG_DIR/zrdn_1.log"
            (( states[3]-- ))
        fi
        if (( pongs_it[4] + 3*it_freq < iteration )) && (( states[4] == 1 )); then
            echo "[$time] [ЗРДН-2] СЛОМАЛАСЬ" >> "$LOG_FILE"
            echo "[$time] СЛОМАЛАСЬ" >> "$ZRDN_LOG_DIR/zrdn_2.log"
            (( states[4]-- ))
        fi
        if (( pongs_it[5] + 3*it_freq < iteration )) && (( states[5] == 1 )); then
            echo "[$time] [ЗРДН-3] СЛОМАЛАСЬ" >> "$LOG_FILE"
            echo "[$time] СЛОМАЛАСЬ" >> "$ZRDN_LOG_DIR/zrdn_1.log"
            (( states[5]-- ))
        fi
        if (( pongs_it[6] + 3*it_freq < iteration )) && (( states[6] == 1 )); then
            echo "[$time] [СПРО] СЛОМАЛАСЬ" >> "$LOG_FILE"
            echo "[$time] СЛОМАЛАСЬ" >> "$SPRO_LOG_DIR/spro.log"
            (( states[6]-- ))
        fi

        (( pings++ ))
        echo "$secret" >> "$RLS_MESSAGES_DIR/rls_1_ping_$pings"
        echo "$secret" >> "$RLS_MESSAGES_DIR/rls_2_ping_$pings"
        echo "$secret" >> "$RLS_MESSAGES_DIR/rls_3_ping_$pings"
        echo "$secret" >> "$ZRDN_MESSAGES_DIR/zrdn_1_ping_$pings"
        echo "$secret" >> "$ZRDN_MESSAGES_DIR/zrdn_2_ping_$pings"
        echo "$secret" >> "$ZRDN_MESSAGES_DIR/zrdn_3_ping_$pings"
        echo "$secret" >> "$SPRO_MESSAGES_DIR/spro_ping_$pings"
    fi

    sleep 0.2
done
