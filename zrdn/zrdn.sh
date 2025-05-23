#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/.."

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --n) zrdn_number="$2"; shift 2 ;;
            --x) zrdn_x="$2"; shift 2 ;;
            --y) zrdn_y="$2"; shift 2 ;;
            --radius) zrdn_radius="$2"; shift 2 ;;
            --secret) secret="$2"; shift 2 ;;
            *)
                echo "Ошибка: Неизвестный параметр: $1"
                exit 1
                ;;
        esac
    done

    # Проверяем, переданы ли все обязательные параметры
    if [[ -z "$zrdn_number" || -z "$zrdn_x" || -z "$zrdn_y" || -z "$zrdn_radius" || -z "$secret" ]]; then
        echo "Ошибка: Необходимо передать все параметры!"
        echo "Использование: $0 --n <value> --x <value> --y <value> --radius <value> --secret <value>"
        exit 1
    fi
}

parse_args "$@"

TARGETS_DIR="$BASE/GenTargets/Targets"
DESTROY_DIR="$BASE/GenTargets/Destroy"
KP_MESSAGES_DIR="$BASE/kp/Messages"
ZRDN_MESSAGES_DIR="$BASE/zrdn/Messages"
STORAGE_DIR="$BASE/zrdn/storage"
NSD_DIR="$BASE/nsd"
DB_FILE="$STORAGE_DIR/zrdn_$zrdn_number.db"

mkdir -p "$STORAGE_DIR"
mkdir -p "$KP_MESSAGES_DIR"
mkdir -p "$ZRDN_MESSAGES_DIR"
mkdir -p "$NSD_DIR"

declare -A prev_coords
declare -A destroyed_targets
declare -A fired_targets

messages_sent=0
iteration=0
shots=0
success=0
fail=0
rockets=20
reloads=0
empty=0
nsd=0

echo "$secret $(date +"%T") $zrdn_number $zrdn_x, $zrdn_y, $zrdn_radius" >> "${KP_MESSAGES_DIR}/zrdn_${zrdn_number}_start"
(( messages_sent++ ))

zrdn_x=$(( zrdn_x * 1000 ))
zrdn_y=$(( zrdn_y * 1000 ))
zrdn_radius=$(( zrdn_radius * 1000 ))

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

# Функция для проверки попадания цели в круг обзора ЗРДН
is_target_in_view() {
    local target_x="$1"
    local target_y="$2"
    local zrdn_x="$3"
    local zrdn_y="$4"
    local zrdn_radius="$5"

    # Проверка расстояния цели от ЗРДН
    distance=$(echo "scale=4; sqrt(($target_x - $zrdn_x)^2 + ($target_y - $zrdn_y)^2)" | bc -l)
    if (( $(echo "$distance > $zrdn_radius" | bc -l) )); then
        return 1
    else
        return 0
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

    messages=($(find "$ZRDN_MESSAGES_DIR" -type f))

    for msg in "${messages[@]}"; do
        msg_name="$(basename "$msg")"

        if [[ "$msg_name" == zrdn_${zrdn_number}* ]]; then
            if ! verify_message "$ZRDN_MESSAGES_DIR/$msg_name"; then
                (( nsd++ ))
                echo "$secret ${msg_name}_${nsd}" >> "${KP_MESSAGES_DIR}/zrdn_${zrdn_number}_nsd_${nsd}"
                mv "$ZRDN_MESSAGES_DIR/$msg_name" "$NSD_DIR/${msg_name}_${nsd}"
                continue
            fi
        fi

        if [[ $msg_name =~ ^zrdn_"$zrdn_number"_reload_([0-9]+)$ ]]; then
            time=$(date +"%T")
            read -r _ cnt < "$msg"
            (( rockets += cnt ))
            (( empty-- ))
            (( reloads++ ))
            echo "$secret $time $cnt" >> "${KP_MESSAGES_DIR}/zrdn_${zrdn_number}_reload_${reloads}"
            rm "$ZRDN_MESSAGES_DIR/$msg_name"
        elif [[ $msg_name =~ ^zrdn_"$zrdn_number"_ping_([0-9]+)$ ]]; then
            echo "$secret" >> "${KP_MESSAGES_DIR}/zrdn_${zrdn_number}_pong_${iteration}"
            rm "$ZRDN_MESSAGES_DIR/$msg_name"
        fi
    done

    target_files=($(find "$TARGETS_DIR" -type f -printf "%T@ %p\n" | sort -nr | head -n 100 | cut -d' ' -f2-))
    # target_files=($(find "$TARGETS_DIR" -type f -exec stat -c "%Y %n" {} + | sort -nr | head -n 100 | cut -d ' ' -f2-))
    # target_files=($(find "$TARGETS_DIR" -type f -exec stat -f "%m %N" {} + | sort -nr | head -n 100 | cut -d ' ' -f2-))

    seen_targets=() # Цели, замеченные в текущей итерации

    for target_file in "${target_files[@]}"; do
        filename="$(basename "$target_file")"

        if [[ ${#filename} -eq 2 ]]; then
            continue
        fi

        if [[ $(grep $filename "$STORAGE_DIR/readed_files_${zrdn_number}.txt" | wc -l) -gt 0 ]]; then
            continue
        fi

        echo "$filename" >> "$STORAGE_DIR/readed_files_${zrdn_number}.txt"

        read -r _ current_x _ current_y < "$target_file"

        if is_target_in_view "$current_x" "$current_y" "$zrdn_x" "$zrdn_y" "$zrdn_radius"; then
            time=$(date +"%T")
            target_id=$(get_target_id "$filename")

            if [[ -v prev_coords[$target_id] ]]; then
                prev_x=$(echo "${prev_coords[$target_id]}" | cut -d ' ' -f 1)
                prev_y=$(echo "${prev_coords[$target_id]}" | cut -d ' ' -f 2)
                speed=$(get_target_speed "$current_x" "$current_y" "$prev_x" "$prev_y")
                type=$(get_target_type "$speed")
                if [[ "$type" == "самолет" || "$type" == "крылатая_ракета" ]]; then
                    if [[ $(grep $target_id "$STORAGE_DIR/found_targets_${zrdn_number}.txt" | wc -l) -eq 0 ]]; then
                        (( messages_sent++ ))
                        echo "$secret $time $target_id $current_x $current_y $type $speed" >> "${KP_MESSAGES_DIR}/zrdn_${zrdn_number}_message_${messages_sent}"
                        echo "$target_id" >> "$STORAGE_DIR/found_targets_${zrdn_number}.txt"
                    fi

                    if [[ -z "${destroyed_targets[$target_id]}" && -z "${fired_targets[$target_id]}" ]]; then
                        if (( rockets > 0 )); then
                            echo "zrdn-${zrdn_number}" >> "$DESTROY_DIR/$target_id"
                            fired_targets[$target_id]="$iteration:0"
                            (( rockets-- ))
                            (( shots++ ))
                            echo "$secret $time $target_id" >> "${KP_MESSAGES_DIR}/zrdn_${zrdn_number}_shot_${messages_sent}"
                        elif (( empty == 0 )); then
                            (( empty++ ))
                            echo "$secret $time" >> "${KP_MESSAGES_DIR}/zrdn_${zrdn_number}_empty"
                        fi
                    fi
                fi

                seen_targets+=("$target_id")
            fi

            prev_coords[$target_id]="$current_x $current_y"
        fi
    done

    # Обработка сбития целей
    for id in "${!fired_targets[@]}"; do
        IFS=":" read -r fire_iter seen_after <<< "${fired_targets[$id]}"

        if (( fire_iter == iteration )); then
            continue
        fi

        if [[ "$seen_after" -eq 0 ]]; then
            for seen_id in "${seen_targets[@]}"; do
                if [[ "$seen_id" == "$id" ]]; then
                    seen_after=1
                    break
                fi
            done
        fi

        fired_targets[$id]="$fire_iter:$seen_after"

        if (( iteration - fire_iter >= 2 )); then
            time=$(date +"%T")
            if [[ "$seen_after" -eq 0 ]]; then
                (( success++ ))
                echo "$secret $time $id" >> "${KP_MESSAGES_DIR}/zrdn_${zrdn_number}_success_${success}"
                destroyed_targets[$id]=1
            else
                (( fail++ ))
                echo "$secret $time $id" >> "${KP_MESSAGES_DIR}/zrdn_${zrdn_number}_fail_${fail}"
            fi
            unset fired_targets[$id]
        fi
    done

    sleep 0.5
done
