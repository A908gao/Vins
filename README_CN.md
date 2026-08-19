# VINS-Fusion (ROS2 Humble) + RealSense D430 + PX4 MAVLink IMU

本仓库在 [VINS-Fusion ROS2 移植版](https://github.com/fanhong-li/VINS-Fusion-ROS2-Humble) 基础上做了以下适配：

- 适配 **PX4 飞控 IMU**（经 MAVLink / MAVROS 输入）
- 适配 **RealSense D430/D435i** 红外双目
- 新增 `vins_bridge` 包（IMU 话题桥接 + 单位处理）
- 新增 `start_vins.sh`（分步启动）与 `launch_all.sh`（一键多终端启动）
- 修复：RViz `world` TF、`/image_track` 编码、相机 640×480、Ceres/CMake 编译问题

## 目录结构

```
Vins/                        # 本仓库
├── setup.sh                 # 一键环境安装（新设备初始化）
├── launch_all.sh            # 一键启动全部节点（5 个终端）
├── start_vins.sh            # 分步启动（imu / vins / all）
├── README_CN.md             # 本文档
├── vins_bridge/             # IMU 桥接节点
├── vins/ camera_models/ loop_fusion/ global_fusion/
└── config/realsense_d435i/  # 配置文件
```

## 一、新设备初始化

### 1. 创建 ROS2 工作区并拉取代码

```bash
mkdir -p ~/vins_ros2_ws/src
cd ~/vins_ros2_ws/src
git clone git@github.com:A908gao/Vins.git
```

### 2. 运行一键安装脚本（需要 sudo 密码）

```bash
cd ~/vins_ros2_ws/src/Vins
bash setup.sh
```

脚本会自动完成：ROS2 Humble 安装 → VINS/相机/MAVROS 依赖 → RealSense SDK + udev → GeographicLib 数据集（`~/GeographicLib`）→ 编译。

### 3. 安装后处理

1. **重新登录**（或重启）让 `video` 组生效；
2. **拔插一次相机 USB** 让 udev 规则生效；
3. 验证相机（`realsense-viewer` 若未安装可跳过）：
   ```bash
   lsusb | grep -i intel        # 应看到 RealSense Depth Camera 430
   ```

## 二、运行

### 方式 A：一键启动（推荐，自动开 5 个终端）

```bash
cd ~/vins_ros2_ws/src/Vins
./launch_all.sh
```

| 终端 | 任务 |
|------|------|
| 1 | MAVROS（连飞控读 IMU，串口断开自动重连） |
| 2 | RealSense 相机（红外双目 640×480） |
| 3 | IMU 桥接 `imu_scale`（`/mavros/imu/data_raw` → `/vins/imu`） |
| 4 | VINS-Fusion 估计器 |
| 5 | RViz 可视化（轨迹 / 相机位姿 / 跟踪图像） |

- 串口覆盖：`FCU_URL=/dev/ttyACM0:921600 ./launch_all.sh`
- RViz 在 VMware 虚拟机里默认用软件渲染（`RViz_SOFTWARE_GL=0` 可关闭）

### 方式 B：手动分步

每个命令开一个终端，先 `source /opt/ros/humble/setup.bash && source ~/vins_ros2_ws/install/setup.bash`：

```bash
# 1) MAVROS（真实飞控 USB 串口，按实际设备名改）
export GEOGRAPHICLIB_DATA=$HOME/GeographicLib
ros2 run mavros mavros_node --ros-args -p fcu_url:=/dev/ttyACM0:921600

# 2) 相机
ros2 launch realsense2_camera rs_launch.py enable_infra1:=true enable_infra2:=true \
  enable_color:=false enable_depth:=false depth_module.infra_profile:=640x480x30

# 3) IMU 桥接
ros2 run vins_bridge imu_scale

# 4) VINS
ros2 run vins vins_node ~/vins_ros2_ws/src/Vins/config/realsense_d435i/px4_d435i_stereo_imu_config.yaml

# 5) RViz
LIBGL_ALWAYS_SOFTWARE=1 rviz2 -d ~/vins_ros2_ws/src/Vins/config/vins_rviz_config.rviz
```

## 三、话题与数据流

```
PX4 飞控 ──MAVLink──▶ MAVROS (/mavros/imu/data_raw, BEST_EFFORT)
                          │
                          ▼
                    imu_scale (/vins/imu)   ← 单位处理：本分支已发 SI 单位，默认直通
                          │
RealSense ──▶ /camera/camera/infra1|2/image_rect_raw ──┐
                          │                            │
                          ▼                            ▼
                    VINS-Fusion (vins_node)
                          │
              ┌───────────┼───────────────┐
              ▼           ▼               ▼
         /odometry     /path       /image_track
      /camera_pose_visual  /point_cloud  ...  ──▶ RViz
```

## 四、注意事项

- **IMU 单位**：本工程的 PX4 分支（`A908gao/FCCU_PX4`）在 HIGHRES_IMU 里直接发 SI 单位（m/s²、rad/s），所以 `imu_scale` 默认直通（`accel_scale=1.0, gyro_scale=1.0`）。若换标准 PX4 固件（mG、mrad/s），用参数覆盖：
  ```bash
  ros2 run vins_bridge imu_scale --ros-args -p accel_scale:=0.00980665 -p gyro_scale:=0.001
  ```
- **相机内参**：`config/realsense_d435i/left.yaml`、`right.yaml` 目前是示例值，建议用 `ros2 topic echo /camera/camera/infra1/camera_info --once` 的实际值更新。
- **IMU 断流**：VINS 对 IMU 断流不鲁棒，飞控复位导致 IMU 中断后会发散，需重启 VINS（`./start_vins.sh vins`）。MAVROS 已带自动重连。
- **特征点少**：相机对准纹理丰富、光线充足的场景；相机尽量插 USB3（蓝口）。

## 五、常见问题

- **RViz 崩溃 / `OpenGl version: 2.1`**：VMware 虚拟机虚拟显卡只支持 OpenGL 2.1。`launch_all.sh` 已默认对 RViz 用软件渲染（`LIBGL_ALWAYS_SOFTWARE=1`，OpenGL 4.5）。正式解决：VMware 设置勾选「3D 加速」+ `sudo apt install open-vm-tools-desktop`，重启后 `RViz_SOFTWARE_GL=0 ./launch_all.sh`。
- **RViz 报 `Frame [world] does not exist`**：`world` 帧要等 VINS 初始化成功后才发布，刚启动前几秒属正常。
- **MAVROS 刷 `FCU: EVENT ...` / `VER: don't support AUTOPILOT_VERSION`**：都是无害日志，飞控事件流和版本协商，不影响 IMU 读取。
- **MAVROS 启动报 `egm96-5.pgm` 缺失**：GeographicLib 数据集没装好，重跑 `setup.sh` 第 4 步或手动 `export GEOGRAPHICLIB_DATA=$HOME/GeographicLib`。
- **编译报 ceres 错误**：`sudo apt install libceres-dev` 后重跑 `colcon build`；仍不行再源码装 Ceres 2.1。

## 六、提交改动到本仓库

```bash
cd ~/vins_ros2_ws/src/Vins
git add -A
git commit -m "..." 
git push origin main
```
