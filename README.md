# IPv4 借用工具

让 IPv6-only VPS 通过 WireGuard 隧道借用其他 VPS 的 IPv4 访问能力。

## 快速开始

### 推荐方式：下载后执行

```bash
# 下载脚本
wget https://raw.githubusercontent.com/88899/gitmen-vps/main/ipv4-proxy.sh
# 或使用 curl
# curl -O https://raw.githubusercontent.com/88899/gitmen-vps/main/ipv4-proxy.sh

# 添加执行权限
chmod +x ipv4-proxy.sh

# 运行（需要 root 权限）
sudo ./ipv4-proxy.sh
```

### 方式二：一键执行

```bash
# 直接下载并运行（需要 root 权限）
curl -fsSL https://raw.githubusercontent.com/88899/gitmen-vps/main/ipv4-proxy.sh | sudo bash
```

或使用 wget：

```bash
wget -qO- https://raw.githubusercontent.com/88899/gitmen-vps/main/ipv4-proxy.sh | sudo bash
```

> **注意**：一键执行方式需要确保系统支持从 `/dev/tty` 读取输入

## 功能菜单

### 安装功能
- **菜单 1**：在有 IPv4 的 VPS 上安装服务器端
- **菜单 2**：在 IPv6-only VPS 上安装客户端
- **菜单 3**：将客户端添加到服务器（在服务器上操作）

### 检测功能
- **菜单 4**：检测系统环境
  - 操作系统信息
  - 网络接口和 IP 地址
  - 已安装的软件包
  - 现有配置文件
  - 防火墙端口状态
  - 系统配置（IPv4 转发等）

- **菜单 5**：查看服务器配置信息
  - 服务器公钥
  - 监听端口和隧道地址
  - 已添加的客户端列表
  - NAT 配置详情
  - 连接状态
  - **提供给客户端的配置信息**（IPv6 地址、公钥、端口）

- **菜单 6**：查看客户端配置信息
  - 客户端公钥
  - 隧道配置
  - 分流域名列表
  - 策略路由规则
  - 流量标记规则
  - DNS 配置
  - 连接状态
  - 连通性测试

### 管理功能
- **菜单 7**：管理分流域名（添加/删除需要走 IPv4 的网站）
- **菜单 8**：查看运行状态
- **菜单 9**：启动服务
- **菜单 10**：停止服务
- **菜单 11**：完全卸载

## 使用流程

### 推荐流程（带检测）

#### 第一步：在服务器上检测环境
1. 运行脚本：`./ipv4-proxy.sh`
2. 选择菜单 `4`（检测系统环境）
3. 查看系统是否满足要求
4. 选择菜单 `1`（安装服务器端）
5. 选择菜单 `5`（查看服务器配置信息）
6. 记录显示的服务器 IPv6 地址、公钥和端口

#### 第二步：在客户端上安装
1. 运行脚本：`./ipv4-proxy.sh`
2. 选择菜单 `4`（检测系统环境）
3. 选择菜单 `2`（安装客户端）
4. 输入服务器的 IPv6 地址和公钥
5. 选择菜单 `6`（查看客户端配置信息）
6. 记录显示的客户端公钥

#### 第三步：添加客户端到服务器
1. 回到服务器 VPS，运行脚本
2. 选择菜单 `3`（添加客户端）
3. 输入客户端公钥
4. 选择菜单 `5`（查看服务器配置信息）验证客户端已添加

#### 第四步：验证
在客户端选择菜单 `6` 或 `8` 查看连接状态和测试连通性。

## 默认分流的网站

- Google (google.com, googlevideo.com)
- YouTube (youtube.com)
- TikTok (tiktok.com)
- OpenAI (openai.com, chatgpt.com)
- Anthropic (anthropic.com, claude.ai)

可通过菜单 7 添加更多网站。

## 系统要求

- Debian 12+
- Ubuntu 20.04+
- Alpine Linux 3.17+
- root 权限
- 服务器端需要有 IPv4 地址
- 客户端需要能通过 IPv6 访问服务器

## 工作原理

使用 WireGuard 建立加密隧道，通过 nftables + dnsmasq 实现域名级别的智能分流，只有指定的网站流量会走 IPv4，其他流量保持原样。

## 特性

- ✅ 支持多种操作系统（Debian、Ubuntu、Alpine）
- ✅ 统一菜单界面，操作简单
- ✅ 完整的环境检测功能
- ✅ 详细的配置信息查看
- ✅ 自动化安装和配置
- ✅ 域名级别智能分流
- ✅ 彩色日志输出
- ✅ 完善的错误处理

## 许可证

MIT
