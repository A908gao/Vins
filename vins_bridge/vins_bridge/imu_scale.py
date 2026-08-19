#!/usr/bin/env python3
"""Scale MAVROS IMU raw (mG, mrad/s) to SI units (m/s^2, rad/s).

MAVROS publishes PX4's HIGHRES_IMU un-scaled on /mavros/imu/data_raw:
  - linear_acceleration  in milli-g (mG)
  - angular_velocity     in milli-rad/s (mrad/s)
VINS-Fusion expects standard SI units, so this node rescales and republishes
to /vins/imu with the original header timestamps preserved.
"""
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Imu

G_PER_MG = 9.80665 / 1000.0   # m/s^2 per mG
RAD_PER_MRAD = 1e-3           # rad/s per mrad/s


class ImuScaleNode(Node):
    def __init__(self):
        super().__init__('imu_scale')
        self.sub = self.create_subscription(
            Imu, '/mavros/imu/data_raw', self.callback, 200)
        self.pub = self.create_publisher(Imu, '/vins/imu', 200)
        self.get_logger().info(
            'Scaling /mavros/imu/data_raw (mG, mrad/s) -> /vins/imu (m/s^2, rad/s)')

    def callback(self, msg):
        out = Imu()
        out.header = msg.header
        out.orientation = msg.orientation
        out.orientation_covariance = msg.orientation_covariance

        out.angular_velocity.x = msg.angular_velocity.x * RAD_PER_MRAD
        out.angular_velocity.y = msg.angular_velocity.y * RAD_PER_MRAD
        out.angular_velocity.z = msg.angular_velocity.z * RAD_PER_MRAD
        out.angular_velocity_covariance = msg.angular_velocity_covariance

        out.linear_acceleration.x = msg.linear_acceleration.x * G_PER_MG
        out.linear_acceleration.y = msg.linear_acceleration.y * G_PER_MG
        out.linear_acceleration.z = msg.linear_acceleration.z * G_PER_MG
        out.linear_acceleration_covariance = msg.linear_acceleration_covariance

        self.pub.publish(out)


def main(args=None):
    rclpy.init(args=args)
    node = ImuScaleNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
