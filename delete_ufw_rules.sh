# ./delete_ufw_rules.sh 22/tcp > delete_ufw_rules.log 2>&1 &

#!/bin/bash
# 檢查是否提供了參數
if [ -z "$1" ]; then
  echo "Usage: $0 <port/proto>"
  echo "Example: $0 22/tcp"
  exit 1
fi

# 將參數賦值給變數
RULE_PATTERN=$1

# 顯示總共預計刪除數量
RULE_COUNT=$(sudo ufw status numbered | grep "22/tcp" | grep "ALLOW" | wc -l)
echo "Total rules to delete: $RULE_COUNT"

# 刪除所有符合指定規則的 ALLOW 規則
while true; do
  # 抓取當前所有符合規則的 ALLOW 規則的編號，僅抓取第一個，以避免編號變動問題
  RULE=$(sudo ufw status numbered | grep "$RULE_PATTERN" | grep "ALLOW" | awk '{print $1}' | sed 's/[][]//g' | head -n 1)

  # 如果沒有規則符合條件則跳出循環
  if [ -z "$RULE" ]; then
    echo -e "\nNo more $RULE_PATTERN ALLOW rules found to delete."
    break
  fi

  # 靜默模式刪除找到的第一條規則，並隱藏操作過程的輸出
  yes | sudo ufw delete "$RULE" &> /dev/null
  # 每刪除一個規則，輸出一個「.」
  echo -n "."
done

echo -e "\nAll $RULE_PATTERN ALLOW rules have been deleted."