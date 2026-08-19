#!/usr/bin/env bash
# ============================================================
# A908gao/Vins 一键环境安装脚本（新设备初始化）
#
# 适用：Ubuntu 22.04 (x86_64)
# 用法：把本仓库 clone 到 <ws>/src/Vins 后，在仓库目录运行：
#     bash setup.sh
# 也可以指定工作区：
#     VINS_WS=/path/to/ws bash setup.sh
#
# 会自动完成：
#   1) ROS2 Humble 安装
#   2) VINS / RealSense / MAVROS 依赖
#   3) RealSense SDK + udev 规则
#   4) GeographicLib 地球模型数据（MAVROS 需要，装到 ~/GeographicLib）
#   5) 编译 VINS + vins_bridge
# 需要 sudo 密码（中途会提示输入）。
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 仓库默认位于 <ws>/src/Vins，上一级是 src，再上一级是工作区根目录
WS_DIR="${VINS_WS:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

echo "============================================================"
echo " 仓库目录: $SCRIPT_DIR"
echo " 工作区:   $WS_DIR"
echo "============================================================"

# ---------- 0) 清理可能残留的 RealSense 源/密钥，避免影响 apt update ----------
sudo rm -f /etc/apt/sources.list.d/librealsense.list \
           /etc/apt/keyrings/librealsense.pgp \
           /etc/apt/keyrings/librealsenseai.gpg || true

# ---------- 1) ROS2 Humble ----------
echo ">>> [1/6] 配置 ROS2 软件源并安装 ROS2 Humble"
sudo apt-get update
sudo apt-get install -y software-properties-common curl gnupg lsb-release
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
sudo apt-get update
sudo apt-get install -y ros-humble-desktop ros-dev-tools python3-colcon-common-extensions

# ---------- 2) VINS / 相机 / MAVROS 依赖 ----------
echo ">>> [2/6] 安装 VINS / RealSense / MAVROS 依赖"
sudo apt-get install -y \
  ros-humble-cv-bridge \
  ros-humble-image-transport \
  ros-humble-message-filters \
  ros-humble-tf2 \
  ros-humble-tf2-ros \
  ros-humble-realsense2-camera \
  ros-humble-realsense2-description \
  ros-humble-mavros \
  ros-humble-mavros-extras \
  ros-humble-mavros-msgs \
  libceres-dev \
  libeigen3-dev \
  libboost-filesystem-dev \
  libboost-program-options-dev \
  libboost-system-dev \
  geographiclib-tools

# ---------- 3) RealSense SDK + udev 规则 ----------
echo ">>> [3/6] RealSense SDK / udev 规则"
sudo apt-get install -y apt-transport-https || true
sudo mkdir -p /etc/apt/keyrings

REALSENSE_REPO_OK=0
if curl -sSf https://librealsense.realsenseai.com/Debian/librealsenseai.asc -o /tmp/librealsenseai.asc; then
  gpg --dearmor < /tmp/librealsenseai.asc | sudo tee /etc/apt/keyrings/librealsenseai.gpg > /dev/null
  echo "deb [signed-by=/etc/apt/keyrings/librealsenseai.gpg] https://librealsense.realsenseai.com/Debian/apt-repo $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/librealsense.list > /dev/null
  if sudo apt-get update; then
    REALSENSE_REPO_OK=1
  else
    sudo rm -f /etc/apt/sources.list.d/librealsense.list
    echo "RealSense apt 源暂不可用，已移除（不影响相机驱动，udev 规则见下）"
  fi
fi

if [ "$REALSENSE_REPO_OK" = "1" ]; then
  sudo apt-get install -y librealsense2-utils librealsense2-dev || true
  sudo apt-get install -y librealsense2-dkms || echo "librealsense2-dkms 失败(可忽略，内核 UVC 已内置)"
fi

# 无论如何都安装官方 udev 规则，保证相机 USB 可访问
sudo curl -sSL https://raw.githubusercontent.com/IntelRealSense/librealsense/master/config/99-realsense-libusb.rules \
  -o /etc/udev/rules.d/99-realsense-libusb.rules || true
sudo udevadm control --reload-rules && sudo udevadm trigger || true
sudo usermod -aG video "$USER" || true

# ---------- 4) GeographicLib 数据集（MAVROS 需要） ----------
echo ">>> [4/6] 下载 GeographicLib 地球模型数据（MAVROS 需要）"
GEO_DIR="$HOME/GeographicLib"
mkdir -p "$GEO_DIR"
if command -v geographiclib-get-geoids >/dev/null 2>&1; then
  timeout 300 geographiclib-get-geoids   -p "$GEO_DIR" egm96-5  || echo "geoid 下载失败(可稍后手动补)"
  timeout 200 geographiclib-get-gravity  -p "$GEO_DIR" egm96    || true
  timeout 200 geographiclib-get-magnetic -p "$GEO_DIR" emm2015  || true
else
  echo "未找到 geographiclib 工具，跳过（若 MAVROS 启动报 geoid 缺失再手动安装）"
fi
echo "GEOGRAPHICLIB_DATA=$GEO_DIR" | tee "$HOME/.geographiclib_env" > /dev/null

# ---------- 5) rosdep ----------
echo ">>> [5/6] rosdep 初始化与依赖安装"
sudo rosdep init || true
rosdep update
source /opt/ros/humble/setup.bash
cd "$WS_DIR"
rosdep install -i --from-path src --rosdistro humble --skip-keys=librealsense2 -y || true

# ---------- 6) 编译 ----------
echo ">>> [6/6] 编译 VINS + vins_bridge"
colcon build --symlink-install --event-handlers console_direct+

echo ""
echo "============================================================"
echo " 安装完成！"
echo " 请执行："
echo "   1) 重新登录（或重启）使 video 组生效；"
echo "   2) 拔插一次 RealSense 相机让 udev 规则生效。"
echo " 之后按 README_CN.md 中的「运行」章节启动。"
echo "============================================================"
