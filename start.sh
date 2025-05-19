#!/opt/homebrew/bin/bash

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

rm -rf "./GenTargets/Targets"
mkdir "./GenTargets/Targets"

cd "./run/start"

./kp.sh "$secret"
./rls1.sh "$secret"
./rls2.sh "$secret"
./rls3.sh "$secret"
./zrdn1.sh "$secret"
./zrdn2.sh "$secret"
./zrdn3.sh "$secret"
./spro.sh "$secret"
