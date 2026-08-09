from setuptools import find_packages, setup

package_name = 'petbot_odom_tf'

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
    maintainer='jetson',
    maintainer_email='jetson@todo.todo',
    description='RPi5의 /odom을 구독해 odom->base_link TF를 브로드캐스트하는 노드.',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            'odom_tf_broadcaster = petbot_odom_tf.odom_tf_broadcaster:main',
        ],
    },
)
