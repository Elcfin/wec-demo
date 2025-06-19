#!/bin/bash

x_values=(4 8 12 16 20 24 28 32 36 40 44 48 52 56 60 64)

for x in "${x_values[@]}"; do
    echo "执行命令: ./part_chunk_demo -v -o k64_m4_b32_s16 -x $x"
    ./part_chunk_demo -v -o ./res/k64_m4_b32_s16_x$x.csv -x $x
    echo "------------------------"
done