#!/usr/bin/env bash
# 一键启动全部 VINS 任务（每个任务一个独立终端窗口）
#
# 终端 1: MAVROS  （连接飞控，读取 IMU；串口断开自动重连）
# 终端 2: 相机    （RealSense D430 红外立体）
# 终端 3: IMU 桥接（/mavros/imu/data_raw -> /vins/imu）
# 终端 4: VINS    （VINS-Fusion 估计器）
# 终端 5: RViz    （可视化界面）
#
# 用法:
#   ./launch_all.sh
#   可用环境变量覆盖:
#     FCU_URL=/dev/ttyACM0:921600   飞控串口
#     TERM_EMU=gnome-terminal       终端模拟器(自动检测)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_DIR="${VINS_WS:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CONFIG="$SCRIPT_DIR/config/realsense_d435i/px4_d435i_stereo_imu_config.yaml"
RVIZ_CONFIG="$SCRIPT_DIR/config/vins_rviz_config.rviz"
FCU_URL="${FCU_URL:-/dev/ttyACM0:921600}"

# 图形显示：如果当前 shell 没有 DISPLAY，尝试默认的 :1（本机 X 会话）
[ -z "${DISPLAY:-}" ] && { [ -e /tmp/.X11-unix/X1 ] && export DISPLAY=:1; }

# 终端模拟器选择
TERM_EMU="${TERM_EMU:-}"
if [ -z "$TERM_EMU" ]; then
    for t in gnome-terminal terminator xfce4-terminal konsole x-terminal-emulator; do
        if command -v "$t" >/dev/null 2>&1; then TERM_EMU="$t"; break; fi
    done
fi
[ -z "$TERM_EMU" ] && { echo "未找到可用的终端模拟器"; exit 1; }

# 公共 ROS 环境
ROS_ENV="source /opt/ros/humble/setup.bash && source $WS_DIR/install/setup.bash"
GEO_ENV="export GEOGRAPHICLIB_DATA=\$HOME/GeographicLib"

# 各任务命令（MAVROS 带自动重连）
CMD_MAVROS="$ROS_ENV && $GEO_ENV && while true; do ros2 run mavros mavros_node --ros-args -p fcu_url:=$FCU_URL; echo 'MAVROS 已退出，3 秒后重连...'; sleep 3; done"
CMD_CAMERA="$ROS_ENV && ros2 launch realsense2_camera rs_launch.py enable_infra1:=true enable_infra2:=true enable_color:=false enable_depth:=false"
CMD_IMU="$ROS_ENV && ros2 run vins_bridge imu_scale"
CMD_VINS="$ROS_ENV && ros2 run vins vins_node $CONFIG"
CMD_RVIZ="$ROS_ENV && rviz2 -d $RVIZ_CONFIG"

open_term() {
    local title="$1"; shift
    local cmd="$*"
    echo "[launch] 打开终端: $title"
    case "$TERM_EMU" in
        gnome-terminal)
            gnome-terminal --title="$title" -- bash -c "$cmd; exec bash" ;;
        terminator)
            terminator -T "$title" -x bash -c "$cmd; exec bash" ;;
        xfce4-terminal)
            xfce4-terminal --title="$title" --command="bash -c \"$cmd; exec bash\"" ;;
        konsole)
            konsole --title "$title" -e bash -c "$cmd; exec bash" ;;
        x-terminal-emulator)
            x-terminal-emulator -T "$title" -e bash -c "$cmd; exec bash" ;;
    esac
}

open_term "MAVROS"     "$CMD_MAVROS"
sleep 1
open_term "Camera"     "$CMD_CAMERA"
sleep 1
open_term "IMU-Bridge" "$CMD_IMU"
sleep 1
open_term "VINS"       "$CMD_VINS"
sleep 2
open_term "RViz"       "$CMD_RVIZ"

echo ""
echo "已启动 5 个终端。若 VINS 需要重新初始化，可在 VINS 终端按 Ctrl+C 后重新运行:"
echo "  $SCRIPT_DIR/start_vins.sh vins"
