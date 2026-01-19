# GitHub Actions CI/CD 與主機防火牆安全策略完整指南

## 文件資訊
- 主題：如何安全地讓 GitHub Actions 部署到私有主機
- 適用對象：DevOps 工程師、後端開發者、系統管理員
- 關鍵字：GitHub Actions, CI/CD, 防火牆, UFW, Self-hosted Runner, 資安

---

## 第一章：問題背景

### 1.1 什麼是 CI/CD？

CI/CD 是持續整合（Continuous Integration）和持續部署（Continuous Deployment）的縮寫。它是一種軟體開發實踐，讓程式碼的測試和部署自動化。

GitHub Actions 是 GitHub 提供的 CI/CD 服務，當你推送程式碼到 GitHub 時，它可以自動執行測試、建置、部署等任務。

### 1.2 遇到的問題

當我們想用 GitHub Actions 自動部署程式碼到自己的主機時，會遇到一個安全困境：

**困境描述**：
- GitHub Actions 需要透過 SSH 連線到我們的主機進行部署
- 但主機的防火牆預設會阻擋外部連線以確保安全
- 如果完全開放 SSH 端口（22），主機會暴露在網路攻擊風險中

**核心問題**：如何在維持主機安全的前提下，允許 GitHub Actions 進行自動部署？

### 1.3 為什麼這很重要？

- SSH 是伺服器管理的重要入口，一旦被入侵，攻擊者可以完全控制主機
- 每天有大量自動化工具在掃描網路上開放的 SSH 端口
- 暴力破解攻擊（Brute Force Attack）非常常見

---

## 第二章：初步解決方案 - 動態 IP 白名單

### 2.1 方案概述

GitHub 提供了一個 API，可以查詢 GitHub Actions 使用的 IP 位址範圍。我們可以利用這個資訊，只允許這些 IP 連線到我們的主機。

**API 網址**：https://api.github.com/meta

### 2.2 實作方式

撰寫一個 Shell 腳本，自動完成以下步驟：
1. 從 GitHub API 獲取最新的 IP 清單
2. 備份現有的防火牆規則
3. 移除舊的 GitHub IP 規則
4. 新增最新的 IP 白名單規則
5. 重新載入防火牆

### 2.3 程式碼範例

```bash
#!/bin/bash
# 從 GitHub API 獲取 Actions IP 範圍
IP_RANGES=$(curl -s https://api.github.com/meta | jq -r '.actions[]')

# 為每個 IP 新增防火牆規則
for ip in $IP_RANGES; do
    # 允許該 IP 存取 SSH 端口
    echo "-A ufw-before-input -p tcp --dport 22 -s $ip -j ACCEPT"
done
```

### 2.4 這個方案的優點

1. **實作簡單**：只需要一個 Shell 腳本
2. **成本為零**：不需要額外的基礎設施
3. **快速部署**：幾分鐘就能設定完成

### 2.5 這個方案的缺點與安全風險

1. **IP 範圍過大**：GitHub Actions 的 IP 範圍包含數千個 IP 位址
2. **IP 是公開的**：任何人都可以查詢這些 IP
3. **共用 IP 風險**：這些 IP 是所有 GitHub 用戶共用的，攻擊者也能使用 GitHub Actions 來嘗試連線你的主機
4. **維護成本**：需要定期更新 IP 清單，因為 GitHub 可能會變更 IP 範圍

**安全評級**：中低風險（比完全開放好，但仍有隱患）

---

## 第三章：業界標準解決方案比較

### 3.1 方案總覽

| 方案名稱 | 安全性 | 複雜度 | 成本 | 推薦程度 |
|---------|--------|--------|------|----------|
| 動態 IP 白名單 | 低 | 低 | 免費 | 僅適合測試 |
| Self-hosted Runner | 高 | 中 | 低 | 強烈推薦 |
| VPN/Tailscale | 高 | 中 | 免費/低 | 推薦 |
| Bastion Host | 高 | 高 | 中 | 企業適用 |
| GitOps (ArgoCD) | 最高 | 高 | 低 | K8s 環境適用 |

### 3.2 Self-hosted Runner（自架執行器）

**這是 GitHub 官方推薦的正統做法。**

#### 運作原理

傳統方式（動態 IP 白名單）：
```
GitHub Actions 伺服器 ──(主動連線)──→ 你的主機
                        入站連線
                        需要開放防火牆
```

Self-hosted Runner 方式：
```
GitHub 伺服器 ←──(主動輪詢)── 你的 Runner ──(本地)──→ 你的主機
               出站連線          內部網路
               不需開放防火牆
```

#### 核心概念

Self-hosted Runner 是你自己架設的 GitHub Actions 執行環境。它會主動連線到 GitHub 伺服器，詢問「有沒有工作要給我做？」

**關鍵優勢**：連線方向是由內向外（Outbound），不是由外向內（Inbound）。這意味著你的防火牆完全不需要開放任何入站連線。

#### 安裝步驟

1. 前往 GitHub 專案的 Settings > Actions > Runners
2. 點選 New self-hosted runner
3. 依照指示下載並設定 Runner
4. 將 Runner 設定為系統服務，讓它持續運行

#### 使用方式

在 GitHub Actions 的 workflow 檔案中，將 `runs-on` 改為 `self-hosted`：

```yaml
jobs:
  deploy:
    runs-on: self-hosted
    steps:
      - name: 部署應用程式
        run: ./deploy.sh
```

#### 優點

1. 防火牆完全不需開放入站連線
2. 只有你的 Runner 能執行部署任務
3. GitHub 官方支援，穩定可靠
4. Runner 會自動更新

#### 缺點

1. 需要維護 Runner 主機
2. Runner 需要保持運行狀態
3. 需要一些初始設定時間

### 3.3 VPN 解決方案（Tailscale / WireGuard）

#### 運作原理

讓 GitHub Actions 的執行環境透過 VPN 加入你的私有網路，在加密通道中進行通訊。

```
GitHub Actions ──→ VPN 隧道（加密）──→ 你的主機
              加入同一個虛擬私有網路
```

#### Tailscale 簡介

Tailscale 是一個基於 WireGuard 的零配置 VPN 服務。它的特點是設定極為簡單，且提供免費方案。

#### 在 GitHub Actions 中使用 Tailscale

```yaml
steps:
  - name: 連接 Tailscale VPN
    uses: tailscale/github-action@v2
    with:
      oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
      oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
      tags: tag:ci

  - name: 部署到主機
    run: ssh user@your-server-tailscale-ip "./deploy.sh"
```

#### 優點

1. 強加密通道，資料傳輸安全
2. 可以細粒度控制存取權限
3. 適合需要多服務互通的架構

#### 缺點

1. 需要管理 VPN 憑證
2. 免費版有設備數量限制
3. 每次 CI 執行都要建立 VPN 連線，增加時間

### 3.4 Bastion Host（堡壘機/跳板機）

#### 運作原理

只暴露一台經過安全強化的跳板機到公網，所有內部主機都隱藏在私有網路中。

```
GitHub Actions ──→ Bastion Host（公網）──→ 內部主機（私網）
                   唯一對外入口            完全隔離
```

#### 安全強化措施

Bastion Host 通常會實施以下安全措施：
- 僅允許 SSH Key 登入，禁用密碼
- 啟用 Fail2ban 防止暴力破解
- 啟用完整的審計日誌
- 定期安全更新
- 最小化安裝，移除不必要服務

#### 優點

1. 企業級安全架構
2. 可集中審計所有存取日誌
3. 內部主機完全隔離

#### 缺點

1. 需要額外維護一台主機
2. 架構較為複雜
3. 有額外的主機成本

### 3.5 GitOps 解決方案（ArgoCD / Flux）

#### 運作原理

這是一種「拉取式」（Pull-based）部署模式。部署工具在叢集內部運行，主動監聽 Git 倉庫的變更，發現變更後自動部署。

```
GitHub Repo ←──(監聽變更)── ArgoCD/Flux ──→ Kubernetes 叢集
            部署工具主動拉取          自動部署
            完全不需入站連線
```

#### 優點

1. 最高安全性：完全不需要任何入站連線
2. 完整的 GitOps 工作流程
3. 自動化程度最高
4. 支援回滾、版本追蹤

#### 缺點

1. 需要 Kubernetes 環境
2. 學習曲線較高
3. 不適合簡單的專案

---

## 第四章：安全性深度分析

### 4.1 連線方向的重要性

**入站連線（Inbound）**：外部主動連線到你的主機
- 需要開放防火牆端口
- 攻擊者可以主動嘗試連線
- 暴露攻擊面

**出站連線（Outbound）**：你的主機主動連線到外部
- 不需要開放防火牆端口
- 攻擊者無法主動連線
- 大幅降低攻擊面

**結論**：優先選擇只需要出站連線的方案（Self-hosted Runner、GitOps）

### 4.2 零信任架構

零信任（Zero Trust）是現代資安的核心原則：「永不信任，持續驗證」

**IP 白名單的問題**：基於「信任特定 IP」的假設，但 IP 可以被偽造或濫用。

**Self-hosted Runner 的優勢**：不依賴 IP 信任，而是基於 Runner 的身份認證。

### 4.3 各方案安全性排名

從最安全到最不安全：

1. **GitOps（ArgoCD/Flux）**：完全無入站連線，最高安全性
2. **Self-hosted Runner**：連線由內向外，高安全性
3. **VPN/Tailscale**：加密通道，中高安全性
4. **Bastion Host**：集中管控，中高安全性
5. **動態 IP 白名單**：IP 公開共用，中低安全性
6. **完全開放 SSH**：最危險，不建議

---

## 第五章：實務建議與選擇指南

### 5.1 根據場景選擇方案

**個人專案 / 小型團隊**：
- 推薦：Self-hosted Runner
- 原因：設定簡單、免費、安全性足夠

**中型團隊 / 多服務架構**：
- 推薦：VPN（Tailscale）或 Bastion Host
- 原因：可以統一管理多個服務的存取

**大型企業 / 高安全需求**：
- 推薦：Bastion Host + 完整審計
- 原因：符合合規要求，可追蹤所有存取

**Kubernetes 環境**：
- 推薦：GitOps（ArgoCD / Flux）
- 原因：雲原生最佳實踐，最高安全性

### 5.2 遷移建議

如果你目前使用動態 IP 白名單方案，建議按以下步驟遷移到 Self-hosted Runner：

1. 在主機上安裝並設定 Self-hosted Runner
2. 修改 GitHub Actions workflow，使用 self-hosted runner
3. 測試部署流程是否正常運作
4. 確認無誤後，移除防火牆上的 GitHub IP 白名單規則
5. 關閉 SSH 入站連線（如果不需要其他用途）

### 5.3 額外安全建議

無論選擇哪種方案，都建議實施以下安全措施：

1. **使用 SSH Key 而非密碼**：禁用密碼登入
2. **啟用 Fail2ban**：自動封鎖暴力破解攻擊
3. **定期更新系統**：修補安全漏洞
4. **最小權限原則**：部署用的帳號只給必要權限
5. **啟用審計日誌**：記錄所有存取行為
6. **使用非標準端口**：將 SSH 從 22 改到其他端口（可選）

---

## 第六章：總結

### 6.1 核心觀念

1. **連線方向很重要**：出站連線比入站連線更安全
2. **不要信任 IP**：IP 白名單有其限制，公開的 IP 範圍風險更高
3. **官方方案通常最好**：Self-hosted Runner 是 GitHub 官方推薦的做法
4. **根據需求選擇**：沒有一體適用的方案，要根據實際情況選擇

### 6.2 方案對照表

| 考量因素 | 動態 IP 白名單 | Self-hosted Runner |
|---------|---------------|-------------------|
| 防火牆設定 | 需開放入站連線 | 不需開放 |
| 誰能連線 | 任何用 GitHub Actions 的人 | 只有你的 Runner |
| 維護成本 | 需定期更新 IP | Runner 自動維護 |
| 安全模型 | 基於 IP 信任 | 基於身份認證 |
| 適用場景 | 快速測試 | 正式環境 |

### 6.3 最終建議

對於大多數使用者，**Self-hosted Runner 是最佳選擇**。它提供了足夠的安全性，同時保持了相對簡單的設定流程。GitHub 官方支援這個方案，文件完善，社群資源豐富。

如果你目前使用動態 IP 白名單方案，建議在有時間時遷移到 Self-hosted Runner，以獲得更好的安全性。

---

## 附錄：名詞解釋

- **CI/CD**：持續整合/持續部署，自動化軟體開發流程
- **GitHub Actions**：GitHub 提供的 CI/CD 服務
- **UFW**：Uncomplicated Firewall，Ubuntu 的防火牆工具
- **SSH**：Secure Shell，安全的遠端連線協定
- **Self-hosted Runner**：自架的 GitHub Actions 執行環境
- **VPN**：虛擬私人網路，加密的網路通道
- **Bastion Host**：堡壘機/跳板機，安全強化的入口主機
- **GitOps**：以 Git 為核心的運維方式
- **ArgoCD**：Kubernetes 的 GitOps 工具
- **Tailscale**：基於 WireGuard 的 VPN 服務
- **零信任**：永不信任、持續驗證的安全原則

---

## 簡報大綱建議

如果要製作簡報，建議使用以下結構：

1. **封面**：GitHub Actions CI/CD 安全部署策略
2. **問題陳述**：CI/CD 部署的安全困境
3. **初步方案**：動態 IP 白名單（優缺點分析）
4. **正統方案**：Self-hosted Runner（重點說明）
5. **其他方案**：VPN、Bastion、GitOps（簡要介紹）
6. **安全性比較**：各方案安全等級圖表
7. **實務建議**：根據場景選擇方案
8. **總結**：核心觀念回顧
9. **Q&A**：問答時間
