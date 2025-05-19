#!/opt/homebrew/bin/bash

rm "./rls/storage/readed_files_1.txt"
rm "./rls/storage/readed_files_2.txt"
rm "./rls/storage/readed_files_3.txt"

rm "./rls/storage/found_targets_1.txt"
rm "./rls/storage/found_targets_2.txt"
rm "./rls/storage/found_targets_3.txt"

touch "./rls/storage/readed_files_1.txt"
touch "./rls/storage/readed_files_2.txt"
touch "./rls/storage/readed_files_3.txt"

touch "./rls/storage/found_targets_1.txt"
touch "./rls/storage/found_targets_2.txt"
touch "./rls/storage/found_targets_3.txt"

rm -rf "./rls/Log"
mkdir -p "./rls/Log"

rm "./zrdn/storage/readed_files_1.txt"
rm "./zrdn/storage/readed_files_2.txt"
rm "./zrdn/storage/readed_files_3.txt"

rm "./zrdn/storage/found_targets_1.txt"
rm "./zrdn/storage/found_targets_2.txt"
rm "./zrdn/storage/found_targets_3.txt"

touch "./zrdn/storage/readed_files_1.txt"
touch "./zrdn/storage/readed_files_2.txt"
touch "./zrdn/storage/readed_files_3.txt"

touch "./zrdn/storage/found_targets_1.txt"
touch "./zrdn/storage/found_targets_2.txt"
touch "./zrdn/storage/found_targets_3.txt"

rm -rf "./zrdn/Log"
mkdir -p "./zrdn/Log"

rm "./spro/storage/readed_files.txt"
rm "./spro/storage/found_targets.txt"

touch "./spro/storage/readed_files.txt"
touch "./spro/storage/found_targets.txt"

rm -rf "./spro/Log"
mkdir -p "./spro/Log"

rm "./pro.log"
touch "./pro.log"
