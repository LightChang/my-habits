#!/bin/bash
# 更新 GitHub Actions IP 的防火牆規則到 /etc/ufw/after.rules

echo "Fetching GitHub Actions IP ranges..."
# 從 GitHub 獲取 IP 列表
IP_RANGES=$(curl -s https://api.github.com/meta | jq -r '.actions[]')

# 確認是否成功獲取 IP 列表
if [[ -z "$IP_RANGES" ]]; then
  echo "Error: Failed to fetch GitHub Actions IP ranges."
  exit 1
fi

# 備份現有的 /etc/ufw/after.rules
AFTER_RULES="/etc/ufw/after.rules"
BACKUP_AFTER_RULES="${AFTER_RULES}.bak"
sudo cp "$AFTER_RULES" "$BACKUP_AFTER_RULES"

# 添加標記，方便之後自動管理 GitHub IP 範圍
START_MARKER="# Start GitHub Actions IP Rules"
END_MARKER="# End GitHub Actions IP Rules"

# 移除現有的 GitHub IP 區塊
sudo sed -i "/$START_MARKER/,/$END_MARKER/d" "$AFTER_RULES"

# 在 /etc/ufw/after.rules 中檢查並添加所需的鏈接定義
if ! grep -q "^*filter" "$AFTER_RULES"; then
  echo "*filter" | sudo tee -a "$AFTER_RULES" > /dev/null
fi

if ! grep -q "^:ufw-before-input " "$AFTER_RULES"; then
  echo ":ufw-before-input - [0:0]" | sudo tee -a "$AFTER_RULES" > /dev/null
fi

# 在 /etc/ufw/after.rules 中添加新的 GitHub IP 區塊
{
  echo "$START_MARKER"
  for ip in $IP_RANGES; do
    echo "-A ufw-before-input -p tcp --dport 22 -s $ip -j ACCEPT"
  done
  echo "$END_MARKER"
  echo "COMMIT"
} | sudo tee -a "$AFTER_RULES" > /dev/null

# 重新啟動 UFW
echo "Reloading UFW to apply new rules..."
sudo ufw reload

echo "UFW rules updated successfully with GitHub Actions in /etc/ufw/after.rules."
