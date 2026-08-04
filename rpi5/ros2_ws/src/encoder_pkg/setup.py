from setuptools import find_packages, setup

package_name = 'encoder_pkg'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='root',
    maintainer_email='dannychhv@gmail.com',
    description='TODO: Package description',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            'encoder_node = encoder_pkg.encoder_node:main',
            'motor_control_node = encoder_pkg.motor_control_node:main',
            'imu_node = encoder_pkg.imu_node:main',
        ],
    },
)
