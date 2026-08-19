from setuptools import find_packages, setup

package_name = 'vins_bridge'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='user',
    maintainer_email='user@todo.todo',
    description='Scale MAVROS IMU (mG, mrad/s) to SI units (m/s^2, rad/s) for VINS-Fusion',
    license='MIT',
    entry_points={
        'console_scripts': [
            'imu_scale = vins_bridge.imu_scale:main',
        ],
    },
)
