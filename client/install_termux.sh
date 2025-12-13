#!/data/data/com.termux/files/usr/bin/bash
#############################################################################
# Open-AutoGLM Termux 端一键部署脚本
# 
# 功能:
#   - 安装所有依赖（Python, ADB, FRP, WebSocket）
#   - 创建 Python 虚拟环境
#   - 配置 FRP 客户端
#   - 配置 WebSocket 客户端
#   - 创建启动/停止脚本
#   - 自动启动所有服务
#
# 使用方法:
#   在 Termux 中运行:
#   bash <(curl -s https://raw.githubusercontent.com/YOUR_USERNAME/Open-AutoGLM/main/client/install_termux.sh)
#   
#   或下载后运行:
#   wget https://raw.githubusercontent.com/YOUR_USERNAME/Open-AutoGLM/main/client/install_termux.sh
#   chmod +x install_termux.sh
#   bash install_termux.sh
#############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# 检查是否在 Termux 中运行
check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        log_error "此脚本只能在 Termux 中运行!"
        log_info "请先安装 Termux: https://f-droid.org/packages/com.termux/"
        exit 1
    fi
}

# 修复 Termux 依赖问题
fix_termux_repos() {
    log_step "步骤 0/8: 修复 Termux 环境"
    
    log_info "检查 Termux 仓库配置..."
    
    # 检查是否有 libandroid-posix-semaphore 错误
    if pkg list-installed 2>&1 | grep -q "CANNOT LINK"; then
        log_warn "检测到 Termux 依赖库问题，正在修复..."
        
        # 更新 Termux 仓库源（使用清华镜像）
        log_info "更新仓库源为国内镜像..."
        sed -i 's@^\(deb.*stable main\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/termux-packages-24 stable main@' $PREFIX/etc/apt/sources.list
        sed -i 's@^\(deb.*games stable\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/game-packages-24 games stable@' $PREFIX/etc/apt/sources.list.d/game.list 2>/dev/null || true
        sed -i 's@^\(deb.*science stable\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/science-packages-24 science stable@' $PREFIX/etc/apt/sources.list.d/science.list 2>/dev/null || true
        
        log_info "清理包缓存..."
        apt clean
        pkg clean
        
        log_info "更新包列表..."
        pkg update -y || {
            log_error "更新失败，尝试强制更新..."
            pkg upgrade -y -o Dpkg::Options::="--force-confnew"
        }
    fi
    
    log_info "✅ Termux 环境检查完成"
}

# 获取配置（精简版 - 只询问必要参数）
get_config() {
    log_step "步骤 1/7: 配置参数"
    
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}请输入以下必要配置（其他将自动设置）${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # 服务器地址（必填 - 支持IP或域名）
    echo -e "${CYAN}[提示] 服务器地址可以是 IP 地址或域名${NC}"
    echo -e "${CYAN}       示例: 123.45.67.89 或 api.phoneagent.com${NC}"
    read -p "📡 服务器地址: " SERVER_IP
    while [ -z "$SERVER_IP" ]; do
        log_warn "服务器地址不能为空"
        read -p "📡 服务器地址 (IP或域名): " SERVER_IP
    done
    
    # FRP Token（必填）
    read -p "🔑 FRP Token: " FRP_TOKEN
    while [ -z "$FRP_TOKEN" ]; do
        log_warn "Token 不能为空"
        read -p "🔑 FRP Token: " FRP_TOKEN
    done
    
    # 设备编号（必填）
    read -p "🔢 设备编号 (1-100): " DEVICE_NUM
    while [ -z "$DEVICE_NUM" ] || ! [[ "$DEVICE_NUM" =~ ^[0-9]+$ ]] || [ "$DEVICE_NUM" -lt 1 ] || [ "$DEVICE_NUM" -gt 100 ]; do
        log_warn "请输入 1-100 之间的数字"
        read -p "🔢 设备编号 (1-100): " DEVICE_NUM
    done
    
    # 设备名称（可选，默认自动生成）
    read -p "📱 设备名称 (直接回车使用默认 device_${DEVICE_NUM}): " DEVICE_NAME
    DEVICE_NAME=${DEVICE_NAME:-device_${DEVICE_NUM}}
    
    # 计算端口
    REMOTE_PORT=$((6100 + DEVICE_NUM - 1))
    WS_URL="ws://${SERVER_IP}:9999/ws/device/${DEVICE_NAME}"
    
    # 保存配置
    cat > ~/.autoglm_config << EOF
SERVER_IP="$SERVER_IP"
FRP_TOKEN="$FRP_TOKEN"
DEVICE_NUM="$DEVICE_NUM"
DEVICE_NAME="$DEVICE_NAME"
REMOTE_PORT="$REMOTE_PORT"
WS_URL="$WS_URL"
EOF
    
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    log_info "配置摘要:"
    log_info "  📡 服务器地址:    $SERVER_IP"
    log_info "  🔑 FRP Token:     ${FRP_TOKEN:0:10}..."
    log_info "  📱 设备名称:      $DEVICE_NAME"
    log_info "  🔢 设备编号:      $DEVICE_NUM"
    log_info "  🔌 FRP 端口:      7000"
    log_info "  🔌 远程端口:      $REMOTE_PORT"
    log_info "  🌐 WebSocket:     $WS_URL"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read -p "确认配置并开始自动安装? (y/n, 默认y): " CONFIRM
    CONFIRM=${CONFIRM:-y}
    if [ "$CONFIRM" != "y" ]; then
        log_warn "已取消安装"
        exit 0
    fi
    
    echo ""
    log_info "开始自动安装，所有依赖将自动确认..."
    sleep 2
}

# 更新包管理器（智能检测，避免重复）
update_packages() {
    log_step "步骤 2/7: 检查包管理器"
    
    # 检查是否在过去1小时内更新过
    UPDATE_MARKER="$PREFIX/var/cache/apt/pkgcache.bin"
    if [ -f "$UPDATE_MARKER" ]; then
        LAST_UPDATE=$(stat -c %Y "$UPDATE_MARKER" 2>/dev/null || stat -f %m "$UPDATE_MARKER" 2>/dev/null || echo 0)
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - LAST_UPDATE))
        
        # 如果1小时内（3600秒）已更新，跳过
        if [ $TIME_DIFF -lt 3600 ]; then
            MINUTES_AGO=$((TIME_DIFF / 60))
            log_info "检测到 ${MINUTES_AGO} 分钟前已更新包管理器，跳过更新"
            log_info "✅ 包管理器已是最新"
            return
        fi
    fi
    
    log_info "更新 pkg（自动确认）..."
    pkg update -y 2>&1 | grep -v "^Reading\|^Building" || true
    
    log_info "升级已安装的包（自动确认）..."
    pkg upgrade -y 2>&1 | grep -v "^Reading\|^Building\|^Unpacking" || true
    
    log_info "✅ 包管理器更新完成"
}

# 安装依赖（自动确认，静默输出）
install_dependencies() {
    log_step "步骤 3/7: 安装依赖"
    
    log_info "安装基础工具（自动确认，无需人工干预）..."
    
    # 使用 -y 自动确认，过滤冗余输出
    pkg install -y \
        python \
        wget \
        curl \
        git \
        android-tools \
        termux-api \
        2>&1 | grep -E "Installing|Setting up|E:" || true
    
    # 验证安装
    log_info "验证安装..."
    if python --version >/dev/null 2>&1; then
        PYTHON_VER=$(python --version 2>&1)
        log_info "  ✅ $PYTHON_VER"
    else
        log_error "Python 安装失败"
        exit 1
    fi
    
    if adb version >/dev/null 2>&1; then
        ADB_VER=$(adb version 2>&1 | head -n1)
        log_info "  ✅ $ADB_VER"
    else
        log_error "ADB 安装失败"
        exit 1
    fi
    
    log_info "✅ 所有依赖安装成功"
}

# 安装并配置 FRP 客户端
install_frp() {
    log_step "步骤 4/7: 安装 FRP 客户端"
    
    cd ~
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        aarch64)
            FRP_ARCH="arm64"
            ;;
        armv7l|armv8l)
            FRP_ARCH="arm"
            ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    
    FRP_VERSION="0.52.0"
    FRP_FILE="frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
    FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_FILE}"
    
    if [ -d "frp" ]; then
        log_warn "FRP 目录已存在，跳过下载"
    else
        log_info "下载 FRP ${FRP_VERSION} for ${FRP_ARCH}..."
        wget -q --show-progress "$FRP_URL" -O "${FRP_FILE}"
        
        log_info "解压 FRP..."
        tar -xzf "${FRP_FILE}"
        mv "frp_${FRP_VERSION}_linux_${FRP_ARCH}" frp
        rm "${FRP_FILE}"
    fi
    
    # 创建 FRP 配置
    log_info "创建 FRP 配置..."
    cat > ~/frp/frpc.ini << EOF
[common]
server_addr = ${SERVER_IP}
server_port = 7000
authentication_method = token
token = ${FRP_TOKEN}
log_file = /data/data/com.termux/files/home/frpc.log
log_level = info
heartbeat_interval = 30
heartbeat_timeout = 90

[adb_${DEVICE_NAME}]
type = tcp
local_ip = 127.0.0.1
local_port = 5555
remote_port = ${REMOTE_PORT}
use_encryption = false
use_compression = true
EOF
    
    log_info "✅ FRP 客户端安装并配置完成"
}

# 配置 ADB
setup_adb() {
    log_step "步骤 5/7: 配置 ADB"
    
    log_info "停止可能存在的 ADB Server..."
    adb kill-server 2>/dev/null || true
    sleep 1
    
    log_info "启动 ADB Server..."
    adb start-server
    sleep 2
    
    log_info "连接本地设备..."
    # 在 Termux 中，ADB 通过 localhost 连接本机
    adb connect localhost:5555 2>/dev/null || true
    sleep 2
    
    # 验证 ADB
    log_info "验证 ADB 连接..."
    if adb devices | grep -q "localhost:5555"; then
        log_info "✅ ADB 连接成功"
    else
        log_warn "⚠️  ADB 连接未建立"
        log_warn "这是正常的，ADB 会在后台自动连接"
        log_warn "服务器端可以通过 FRP 隧道连接"
    fi
    
    log_info "✅ ADB Server 配置完成"
}

# 创建 Python 虚拟环境和 WebSocket 客户端
setup_python_client() {
    log_step "步骤 6/7: 创建 WebSocket 客户端"
    
    cd ~
    
    # 创建虚拟环境
    if [ ! -d "autoglm_venv" ]; then
        log_info "创建 Python 虚拟环境..."
        python -m venv autoglm_venv
    fi
    
    # 激活虚拟环境并安装依赖
    log_info "安装 Python 依赖..."
    source ~/autoglm_venv/bin/activate
    pip install --upgrade pip -q
    pip install websockets asyncio -q
    deactivate
    
    # 创建 WebSocket 客户端脚本
    log_info "创建 WebSocket 客户端脚本..."
    cat > ~/ws_client.py << 'EOFPYTHON'
#!/usr/bin/env python3
"""WebSocket Client for Open-AutoGLM"""

import asyncio
import json
import logging
import subprocess
import sys
from datetime import datetime

try:
    import websockets
except ImportError:
    print("Error: websockets not installed")
    sys.exit(1)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def get_device_specs():
    """获取设备信息"""
    try:
        android_version = subprocess.check_output(
            ["getprop", "ro.build.version.release"], text=True
        ).strip()
        
        model = subprocess.check_output(
            ["getprop", "ro.product.model"], text=True
        ).strip()
        
        wm_size = subprocess.check_output(
            ["wm", "size"], text=True
        ).strip()
        screen_resolution = wm_size.split(":")[-1].strip()
        
        return {
            "model": model,
            "android_version": android_version,
            "screen_resolution": screen_resolution
        }
    except Exception as e:
        logger.error(f"Failed to get specs: {e}")
        return {
            "model": "unknown",
            "android_version": "unknown",
            "screen_resolution": "unknown"
        }


def get_battery_level():
    """获取电池电量"""
    try:
        result = subprocess.check_output(
            ["termux-battery-status"], text=True
        )
        data = json.loads(result)
        return data.get("percentage", 100)
    except:
        return 100


def check_frp_status():
    """检查 FRP 状态"""
    try:
        result = subprocess.run(
            ["pgrep", "-f", "frpc"], capture_output=True
        )
        return result.returncode == 0
    except:
        return False


async def heartbeat_loop(websocket, device_id):
    """心跳循环"""
    while True:
        try:
            await asyncio.sleep(30)
            
            heartbeat = {
                "type": "heartbeat",
                "device_id": device_id,
                "status": {
                    "battery": get_battery_level(),
                    "frp_connected": check_frp_status()
                },
                "timestamp": datetime.utcnow().isoformat()
            }
            
            await websocket.send(json.dumps(heartbeat))
            logger.debug("Heartbeat sent")
            
        except Exception as e:
            logger.error(f"Heartbeat error: {e}")
            break


async def message_loop(websocket, device_id):
    """消息接收循环"""
    while True:
        try:
            message = await websocket.recv()
            data = json.loads(message)
            msg_type = data.get("type")
            
            logger.info(f"Received: {msg_type}")
            
            if msg_type == "heartbeat_ack":
                logger.debug("Heartbeat ack")
            else:
                logger.info(f"Unknown message: {msg_type}")
        
        except websockets.exceptions.ConnectionClosed:
            logger.info("Connection closed")
            break
        except Exception as e:
            logger.error(f"Message error: {e}")
            break


async def connect_websocket(ws_url, device_id, device_name, frp_port):
    """连接 WebSocket"""
    while True:
        try:
            logger.info(f"Connecting to {ws_url}...")
            
            async with websockets.connect(ws_url) as websocket:
                logger.info("Connected!")
                
                specs = get_device_specs()
                specs["frp_port"] = frp_port
                specs["device_name"] = device_name
                
                online_msg = {
                    "type": "device_online",
                    "device_id": device_id,
                    "specs": specs,
                    "timestamp": datetime.utcnow().isoformat()
                }
                
                await websocket.send(json.dumps(online_msg))
                logger.info("Device online message sent")
                
                response = await websocket.recv()
                data = json.loads(response)
                
                if data.get("type") == "registered":
                    logger.info("Registered successfully!")
                    
                    await asyncio.gather(
                        heartbeat_loop(websocket, device_id),
                        message_loop(websocket, device_id)
                    )
        
        except Exception as e:
            logger.error(f"Connection error: {e}")
            logger.info("Reconnecting in 10s...")
            await asyncio.sleep(10)


def main():
    if len(sys.argv) != 5:
        print("Usage: python ws_client.py <ws_url> <device_id> <device_name> <frp_port>")
        sys.exit(1)
    
    ws_url = sys.argv[1]
    device_id = sys.argv[2]
    device_name = sys.argv[3]
    frp_port = int(sys.argv[4])
    
    logger.info(f"Starting client for {device_name}")
    asyncio.run(connect_websocket(ws_url, device_id, device_name, frp_port))


if __name__ == "__main__":
    main()
EOFPYTHON
    
    chmod +x ~/ws_client.py
    
    log_info "✅ WebSocket 客户端创建完成"
}

# 创建管理脚本
create_management_scripts() {
    log_step "步骤 7/7: 创建管理脚本"
    
    # 启动脚本
    log_info "创建启动脚本..."
    cat > ~/start_all.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Open-AutoGLM 启动脚本

echo "🚀 启动 Open-AutoGLM 设备端服务..."
echo ""

# 加载配置
if [ -f ~/.autoglm_config ]; then
    source ~/.autoglm_config
else
    echo "❌ 配置文件不存在，请重新运行安装脚本"
    exit 1
fi

# 1. 启动 ADB
echo "1️⃣  启动 ADB Server..."
adb kill-server 2>/dev/null || true
sleep 1
adb start-server
sleep 2
adb connect localhost:5555 2>/dev/null || true
sleep 2

if adb devices | grep -q "localhost:5555"; then
    echo "   ✅ ADB Server 启动成功"
else
    echo "   ⚠️  ADB 连接未建立（这是正常的）"
fi

# 2. 启动 FRP 客户端
echo ""
echo "2️⃣  启动 FRP 客户端..."
pkill -f frpc 2>/dev/null || true
sleep 1
nohup ~/frp/frpc -c ~/frp/frpc.ini > ~/frpc.log 2>&1 &
sleep 3

if pgrep -f frpc > /dev/null; then
    echo "   ✅ FRP 客户端启动成功"
else
    echo "   ❌ FRP 客户端启动失败"
    echo "   查看日志: tail -f ~/frpc.log"
fi

# 3. 启动 WebSocket 客户端
echo ""
echo "3️⃣  启动 WebSocket 客户端..."
pkill -f ws_client.py 2>/dev/null || true
sleep 1
source ~/autoglm_venv/bin/activate
nohup python ~/ws_client.py "\${WS_URL}" "\${DEVICE_NAME}" "\${DEVICE_NAME}" \${REMOTE_PORT} > ~/ws_client.log 2>&1 &
deactivate
sleep 2

if pgrep -f ws_client.py > /dev/null; then
    echo "   ✅ WebSocket 客户端启动成功"
else
    echo "   ❌ WebSocket 客户端启动失败"
    echo "   查看日志: tail -f ~/ws_client.log"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ 所有服务已启动!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "📊 查看日志:"
echo "  FRP:       tail -f ~/frpc.log"
echo "  WebSocket: tail -f ~/ws_client.log"
echo ""
echo "🔍 检查状态:"
echo "  ps aux | grep frpc"
echo "  ps aux | grep ws_client"
echo ""
echo "🛑 停止服务:"
echo "  ~/stop_all.sh"
echo ""
EOF
    
    chmod +x ~/start_all.sh
    
    # 停止脚本
    log_info "创建停止脚本..."
    cat > ~/stop_all.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Open-AutoGLM 停止脚本

echo "🛑 停止 Open-AutoGLM 设备端服务..."
echo ""

pkill -f frpc
pkill -f ws_client.py

sleep 2

echo "✅ 所有服务已停止"
EOF
    
    chmod +x ~/stop_all.sh
    
    # 状态检查脚本
    log_info "创建状态检查脚本..."
    cat > ~/check_status.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Open-AutoGLM 状态检查脚本

echo "📊 Open-AutoGLM 服务状态"
echo "═══════════════════════════════════════════════════════════"
echo ""

# 检查 ADB
echo "1️⃣  ADB Server:"
if adb devices | grep -q "5555"; then
    echo "   ✅ 运行中"
    adb devices | grep "5555"
else
    echo "   ❌ 未运行"
fi

echo ""

# 检查 FRP
echo "2️⃣  FRP 客户端:"
if pgrep -f frpc > /dev/null; then
    echo "   ✅ 运行中 (PID: $(pgrep -f frpc))"
    echo "   最近日志:"
    tail -n 3 ~/frpc.log | sed 's/^/      /'
else
    echo "   ❌ 未运行"
fi

echo ""

# 检查 WebSocket
echo "3️⃣  WebSocket 客户端:"
if pgrep -f ws_client.py > /dev/null; then
    echo "   ✅ 运行中 (PID: $(pgrep -f ws_client.py))"
    echo "   最近日志:"
    tail -n 3 ~/ws_client.log | sed 's/^/      /'
else
    echo "   ❌ 未运行"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
EOF
    
    chmod +x ~/check_status.sh
    
    log_info "✅ 管理脚本创建完成"
}

# 启动服务（可选）
start_services() {
    echo ""
    log_info "✅ 所有配置已完成！"
    echo ""
    
    read -p "是否立即启动所有服务? (y/n, 默认y): " START_NOW
    START_NOW=${START_NOW:-y}
    
    if [ "$START_NOW" = "y" ]; then
        echo ""
        log_info "🚀 启动服务..."
        sleep 1
        bash ~/start_all.sh
    else
        echo ""
        log_info "⏭️  跳过启动，稍后可运行以下命令启动服务:"
        echo ""
        echo -e "  ${GREEN}~/start_all.sh${NC}"
        echo ""
    fi
}

# 显示完成信息
show_completion_info() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Open-AutoGLM Termux 端安装完成!                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 加载配置
    source ~/.autoglm_config
    
    echo -e "${YELLOW}📋 配置信息:${NC}"
    echo -e "  设备名称:     $DEVICE_NAME"
    echo -e "  设备编号:     $DEVICE_NUM"
    echo -e "  服务器地址:   $SERVER_IP"
    echo -e "  FRP 端口:     7000"
    echo -e "  远程端口:     $REMOTE_PORT"
    echo ""
    
    echo -e "${YELLOW}🔧 管理命令:${NC}"
    echo -e "  启动服务:    ${GREEN}~/start_all.sh${NC}"
    echo -e "  停止服务:    ${GREEN}~/stop_all.sh${NC}"
    echo -e "  检查状态:    ${GREEN}~/check_status.sh${NC}"
    echo ""
    
    echo -e "${YELLOW}📊 查看日志:${NC}"
    echo -e "  FRP:         ${GREEN}tail -f ~/frpc.log${NC}"
    echo -e "  WebSocket:   ${GREEN}tail -f ~/ws_client.log${NC}"
    echo ""
    
    echo -e "${YELLOW}🧪 验证连接:${NC}"
    echo -e "  在服务器上运行:"
    echo -e "    ${GREEN}adb connect localhost:${REMOTE_PORT}${NC}"
    echo -e "    ${GREEN}adb devices${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  保持 Termux 运行:${NC}"
    echo -e "  - 不要关闭 Termux 应用"
    echo -e "  - 建议关闭省电模式"
    echo -e "  - 建议使用 Termux:Boot 实现开机自启"
    echo ""
}

#############################################################################
# 主流程
#############################################################################

main() {
    clear
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  PhoneAgent Termux 端一键安装脚本                         ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_termux
    fix_termux_repos
    get_config
    update_packages
    install_dependencies
    install_frp
    setup_adb
    setup_python_client
    create_management_scripts
    start_services
    show_completion_info
}

# 执行主流程
main

