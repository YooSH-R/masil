from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    motor_control_node = Node(
        package='encoder_pkg',
        executable='motor_control_node',
        name='motor_control_node',
        output='screen',
    )

    imu_node = Node(
        package='encoder_pkg',
        executable='imu_node',
        name='imu_node',
        output='screen',
    )

    ekf_config = '/root/ros2_ws/src/encoder_pkg/config/ekf.yaml'
    ekf_node = Node(
        package='robot_localization',
        executable='ekf_node',
        name='ekf_filter_node',
        output='screen',
        parameters=[ekf_config],
        remappings=[('odometry/filtered', 'odom')],
    )

    return LaunchDescription([
        motor_control_node,
        imu_node,
        ekf_node,
    ])
