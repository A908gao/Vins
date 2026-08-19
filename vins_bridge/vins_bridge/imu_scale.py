#!/usr/bin/env python3
"""IMU bridge: /mavros/imu/data_raw -> /vins/imu.

在 MAVROS 与 VINS 之间做话题桥接，并对单位做可配置缩放。

重要说明（针对本工程的 PX4 分支 A908gao/FCCU_PX4）：
  该分支的 HIGHRES_IMU 流直接 `msg.xacc = accel(0)`、`msg.xgyro = gyro(0)`，
  发出来的是 SI 单位（m/s^2 与 rad/s），并不是标准 MAVLink 的 mG/mrad/s。
  因此默认 accel_scale=1.0、gyro_scale=1.0（直通）。

  若换成标准 PX4 固件（HIGHRES_IMU 为 mG、mrad/s），用参数覆盖：
    ros2 run vins_bridge imu_scale --ros-args \
      -p accel_scale:=0.00980665 -p gyro_scale:=0.001
"""
import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Imu


class ImuBridgeNode(Node):
    def __init__(self):
        super().__init__('imu_scale')
        self.declare_parameter('accel_scale', 1.0)
        self.declare_parameter('gyro_scale', 1.0)
        self.accel_scale = self.get_parameter('accel_scale').value
        self.gyro_scale = self.get_parameter('gyro_scale').value

        # MAVROS 以 BEST_EFFORT (sensor_data) 发布 IMU，订阅必须匹配
        self.sub = self.create_subscription(
            Imu, '/mavros/imu/data_raw', self.callback, qos_profile_sensor_data)
        self.pub = self.create_publisher(Imu, '/vins/imu', qos_profile_sensor_data)
        self.get_logger().info(
            f'/mavros/imu/data_raw -> /vins/imu  accel_scale={self.accel_scale}, '
            f'gyro_scale={self.gyro_scale}')

    def callback(self, msg):
        out = Imu()
        out.header = msg.header
        out.orientation = msg.orientation
        out.orientation_covariance = msg.orientation_covariance

        out.angular_velocity.x = msg.angular_velocity.x * self.gyro_scale
        out.angular_velocity.y = msg.angular_velocity.y * self.gyro_scale
        out.angular_velocity.z = msg.angular_velocity.z * self.gyro_scale
        out.angular_velocity_covariance = msg.angular_velocity_covariance

        out.linear_acceleration.x = msg.linear_acceleration.x * self.accel_scale
        out.linear_acceleration.y = msg.linear_acceleration.y * self.accel_scale
        out.linear_acceleration.z = msg.linear_acceleration.z * self.accel_scale
        out.linear_acceleration_covariance = msg.linear_acceleration_covariance

        self.pub.publish(out)


def main(args=None):
    rclpy.init(args=args)
    node = ImuBridgeNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
