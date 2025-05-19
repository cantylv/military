#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/.."

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --n) rls_number="$2"; shift 2 ;;
            --x) rls_x="$2"; shift 2 ;;
            --y) rls_y="$2"; shift 2 ;;
            --azimuth) rls_azimuth="$2"; shift 2 ;;
            --view_angle) rls_view_angle="$2"; shift 2 ;;
            --radius) rls_radius="$2"; shift 2 ;;
            --secret) secret="$2"; shift 2 ;;
            *)
                echo "Ошибка: Неизвестный параметр: $1"
                exit 1
                ;;
        esac
    done

    # Проверяем, переданы ли все обязательные параметры
    if [[ -z "$rls_number" || -z "$rls_x" || -z "$rls_y" || -z "$rls_azimuth" || -z "$rls_view_angle" || -z "$rls_radius" || -z "$secret" ]]; then
        echo "Ошибка: Необходимо передать все параметры!"
        echo "Использование: $0 --n <value> --x <value> --y <value> --azimuth <value> --view_angle <value> --radius <value> --secret <value>"
        exit 1
    fi
}

parse_args "$@"

TARGETS_DIR="$BASE/GenTargets/Targets"
KP_MESSAGES_DIR="$BASE/kp/Messages"
RLS_MESSAGES_DIR="$BASE/rls/Messages"
STORAGE_DIR="$BASE/rls/storage"
NSD_DIR="$BASE/nsd"
DB_FILE="$STORAGE_DIR/rls_$rls_number.db"

mkdir -p "$STORAGE_DIR"
mkdir -p "$KP_MESSAGES_DIR"
mkdir -p "$NSD_DIR"
mkdir -p "$RLS_MESSAGES_DIR"

declare -A prev_coords

messages_sent=0
iteration=0
nsd=0

echo "$secret $(date +"%T") $rls_number $rls_x, $rls_y, $rls_azimuth, $rls_view_angle, $rls_radius" >> "${KP_MESSAGES_DIR}/rls_${rls_number}_start"
(( messages_sent++ ))

rls_x=$(( rls_x * 1000 ))
rls_y=$(( rls_y * 1000 ))
rls_view_angle=$(( rls_view_angle / 2 ))
rls_radius=$(( rls_radius * 1000 ))

spro_x=3100000
spro_y=3800000
spro_radius=1200000

verify_message() {
    local source="$1"
    read -r sec _ < "$source"
    if [[ "$sec" != "$secret" ]]; then
        return 1
    else
        return 0
    fi
}

# Функция для получения ID цели из имени файла
get_target_id() {
    local filename="$1"
    local target_id_hex=""

    for ((i=2; i<${#filename}; i+=4)); do
        target_id_hex+=${filename:i:2}
    done

    echo -n "$target_id_hex" | xxd -r -p
}

arctangens() {
    local target_x="$1"
    local target_y="$2"
    local rls_x="$3"
    local rls_y="$4"

    angle=0.0
    if (( $(echo "$target_x == $rls_x" | bc -l) )); then
        if (( $(echo "$target_y >= $rls_y") | bc -l )); then
            angle=90
        else
            angle=270
        fi
    else
        angle=$(echo "scale=4; a(($target_y - $rls_y)/($target_x - $rls_x))*180/3.1415927" | bc -l)
        angle=$(echo "scale=4; if($angle < 0) direction_angle+=360; $angle" | bc -l)
    fi

    echo "$angle"
}

# Функция для определения факта движения в сторону СПРО
is_to_spro() {
    local target_x_1="$1"
    local target_y_1="$2"
    local target_x_2="$3"
    local target_y_2="$4"
    local spro_x="$5"
    local spro_y="$6"
    local spro_radius="$7"

    dx=$(echo "$target_x_2 - $target_x_1" | bc)
    dy=$(echo "$target_y_2 - $target_y_1" | bc)
    numerator=$(echo "($dx * ($target_y_1 - $spro_y)) - (($target_x_1 - $spro_x) * $dy)" | bc)
    numerator_abs=$(echo "$numerator" | awk '{print ($1<0)?-$1:$1}')
    denominator=$(echo "scale=10; sqrt($dx^2 + $dy^2)" | bc -l)
    distance=$(echo "scale=10; $numerator_abs / $denominator" | bc -l)

    if (( $(echo "$distance > $spro_radius" | bc -l) )); then
        return 1
    else
        dist_1=$(echo "scale=10; sqrt(($target_x_1 - $spro_x)^2 + ($target_y_1 - $spro_y)^2)" | bc -l)
        dist_2=$(echo "scale=10; sqrt(($target_x_2 - $spro_x)^2 + ($target_y_2 - $spro_y)^2)" | bc -l)
        if (( $(echo "$dist_1 > $dist_2" | bc -l) )); then
            return 0
        else  # движется от СПРО
            return 1
        fi
    fi
}

# Функция для проверки попадания цели в сектор обзора РЛС
is_target_in_view() {
    local target_x="$1"
    local target_y="$2"
    local rls_x="$3"
    local rls_y="$4"
    local rls_azimuth="$5"
    local rls_view_angle="$6"
    local rls_radius="$7"

    # Вычисление угла между РЛС и целью в градусах
    angle=$(arctangens "$current_x" "$current_y" "$rls_x" "$rls_y")

    # Вычисление угла обзора РЛС
    rls_view_angle_left=$(echo "scale=4; $rls_azimuth - $rls_view_angle" | bc -l)
    rls_view_angle_right=$(echo "scale=4; $rls_azimuth + $rls_view_angle" | bc -l)

    # Корректировка углов обзора в диапазон [0, 360)
    if (( $(echo "$rls_view_angle_left < 0" | bc -l) )); then
        rls_view_angle_left=$(echo "scale=4; $rls_view_angle_left + 360" | bc -l)
    fi
    if (( $(echo "$rls_view_angle_right >= 360" | bc -l) )); then
        rls_view_angle_right=$(echo "scale=4; $rls_view_angle_right - 360" | bc -l)
    fi

    # Проверка расстояния цели от РЛС
    distance=$(echo "scale=4; sqrt(($target_x - $rls_x)^2 + ($target_y - $rls_y)^2)" | bc -l)
    if (( $(echo "$distance > $rls_radius" | bc -l) )); then
        return 1
    else
        # Проверка попадания угла цели в угол обзора РЛС
        if (( $(echo "$rls_view_angle_left < $rls_view_angle_right" | bc -l) )); then
            if (( $(echo "$angle >= $rls_view_angle_left && $angle <= $rls_view_angle_right" | bc -l) )); then
                return 0
            else
                return 1
            fi
        else
            if (( $(echo "$angle >= $rls_view_angle_left || $angle <= $rls_view_angle_right" | bc -l) )); then
                return 0
            else
                return 1
            fi
        fi
    fi
}

# Функция для определения скорости цели
get_target_speed() {
    local current_x="$1"
    local current_y="$2"
    local prev_x="$3"
    local prev_y="$4"

    speed=$(echo "scale=4; sqrt(($current_x - $prev_x)^2 + ($current_y - $prev_y)^2)" | bc -l)

    echo "$speed"
}

# Функция для определения типа цели по ее скорости
get_target_type() {
    local type=""
    if (( $(echo "$speed >= 8000 && $speed <= 10000" | bc -l) )); then
        type="ББ_БР"
    elif (( $(echo "$speed >= 250 && $speed <= 1000" | bc -l) )); then
        type="крылатая_ракета"
    elif (( $(echo "$speed >= 50 && $speed <= 249" | bc -l) )); then
        type="самолет"
    else
        type="неизвестный_тип"
    fi

    echo "$type"
}

while true; do
    (( iteration++ ))

    messages=($(find "$RLS_MESSAGES_DIR" -type f))

    for msg in "${messages[@]}"; do
        msg_name="$(basename "$msg")"

        if [[ "$msg_name" == rls_${rls_number}* ]]; then
            if ! verify_message "$RLS_MESSAGES_DIR/$msg_name"; then
                (( nsd++ ))
                echo "$secret ${msg_name}_${nsd}" >> "${KP_MESSAGES_DIR}/rls_${rls_number}_nsd_${nsd}"
                mv "$RLS_MESSAGES_DIR/$msg_name" "$NSD_DIR/${msg_name}_${nsd}"
                continue
            fi
        fi

        if [[ $msg_name =~ ^rls_"$rls_number"_ping_([0-9]+)$ ]]; then
            echo "$secret" >> "${KP_MESSAGES_DIR}/rls_${rls_number}_pong_${iteration}"
            rm "$RLS_MESSAGES_DIR/$msg_name"
        fi
    done

    target_files=($(find "$TARGETS_DIR" -type f -printf "%T@ %p\n" | sort -n | head -n 100 | cut -d' ' -f2-))
    # target_files=($(find "$TARGETS_DIR" -type f -exec stat -c "%Y %n" {} + | sort -nr | head -n 100 | cut -d ' ' -f2-))
    # target_files=($(find "$TARGETS_DIR" -type f -exec stat -f "%m %N" {} + | sort -nr | head -n 100 | cut -d' ' -f2-))

    for target_file in "${target_files[@]}"; do
        filename="$(basename "$target_file")"

        if [[ ${#filename} -eq 2 ]]; then
            continue
        fi

        if [[ $(grep $filename "$STORAGE_DIR/readed_files_${rls_number}.txt" | wc -l) -gt 0 ]]; then
            continue
        fi

        echo "$filename" >> "$STORAGE_DIR/readed_files_${rls_number}.txt"

        read -r _ current_x _ current_y < "$target_file"

        if is_target_in_view "$current_x" "$current_y" "$rls_x" "$rls_y" "$rls_azimuth" "$rls_view_angle" "$rls_radius"; then
            time=$(date +"%T")
            target_id=$(get_target_id "$filename")

            if [[ -v prev_coords[$target_id] ]]; then
                prev_x=$(echo "${prev_coords[$target_id]}" | cut -d ' ' -f 1)
                prev_y=$(echo "${prev_coords[$target_id]}" | cut -d ' ' -f 2)

                speed=$(get_target_speed "$current_x" "$current_y" "$prev_x" "$prev_y")
                type=$(get_target_type "$speed")

                to_spro=0
                if is_to_spro "$prev_x" "$prev_y" "$current_x" "$current_y" "$spro_x" "$spro_y" "$spro_radius"; then
                    to_spro=1
                fi

                if [[ "$type" == "ББ_БР" ]]; then
                    if [[ $(grep $target_id "$STORAGE_DIR/found_targets_${rls_number}.txt" | wc -l) -eq 0 ]]; then
                        echo "$secret $time $target_id $current_x $current_y $type $speed $to_spro" >> "${KP_MESSAGES_DIR}/rls_${rls_number}_message_${messages_sent}"
                        (( messages_sent++ ))
                        echo "$target_id" >> "$STORAGE_DIR/found_targets_${rls_number}.txt"
                    fi
                fi
            fi

            prev_coords[$target_id]="$current_x $current_y"
        fi
    done

    sleep 0.5
done
