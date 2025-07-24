#!/bin/bash
# 定义运行次数（可修改为需要的次数）
RUN_TIMES=10
SH=code_run_k_noperf.sh

# 循环运行
for ((i=1; i<=RUN_TIMES; i++)); do
  echo -e "\n===== 开始第 $i 次运行 ====="
  # 执行目标脚本
  bash $SH
  # 检查上一次运行是否失败
  if [ $? -ne 0 ]; then
    echo "===== 第 $i 次运行失败！终止后续运行 ====="
    exit 1  # 失败则退出循环
  fi
  echo "===== 第 $i 次运行完成 ====="
done

echo -e "\n所有 $RUN_TIMES 次运行已完成！"