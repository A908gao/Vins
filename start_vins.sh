#!/usr/bin/env bash
# 分别启动 VINS 与 IMU 节点
#
# 用法:
#   ./start_vins.sh imu   启动 IMU 单位转换节点 (vins_bridge imu_scale)
#   ./start_vins.sh vins  启动 VINS-Fusion 估计器 (vins_node)
#   ./start_vins.sh all   同时启动 IMU(后台) + VINS(前台)
#
# 前提:
#   1) 已安装 ROS2 Humble 并编译好本工作区
#   2) 相机节点 (realsense2_camera) 与 MAVROS 节点已在别的终端启动
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 工作区根目录：本脚本位于 <ws>/src/VINS-Fusion-ROS2-Humble/ 下，
# 上一级是 src，再上一级是工作区根目录。可用 VINS_WS 环境变量覆盖。
WS_DIR="${VINS_WS:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CONFIG="$SCRIPT_DIR/config/realsense_d435i/px4_d435i_stereo_imu_config.yaml"

source /opt/ros/humble/setup.bash
[ -f "$WS_DIR/install/setup.bash" ] && source "$WS_DIR/install/setup.bash"

usage() {
    echo "用法: $0 {imu|vins|all}"
    echo "  imu   启动 IMU 单位转换节点 (/mavros/imu/data_raw -> /vins/imu)"
    echo "  vins  启动 VINS-Fusion 估计器"
    echo "  all   同时启动 IMU(后台) + VINS(前台)"
    exit 1
}

case "${1:-}" in
    imu)
        echo "[imu] ros2 run vins_bridge imu_scale"
        exec ros2 run vins_bridge imu_scale
        ;;
    vins)
        echo "[vins] config: $CONFIG"
        exec ros2 run vins vins_node "$CONFIG"
        ;;
    all)
        echo "[all] 启动 IMU(后台) + VINS(前台)"
        ros2 run vins_bridge imu_scale &
        IMU_PID=$!
        trap 'kill $IMU_PID 2>/dev/null || true' EXIT INT TERM
        exec ros2 run vins vins_node "$CONFIG"
        ;;
    *)
        usage
        ;;
esac
