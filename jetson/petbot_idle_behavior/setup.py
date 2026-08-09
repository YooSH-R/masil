from setuptools import find_packages, setup

package_name = 'petbot_idle_behavior'

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
    description='Idle 상태에서 REST/PATROL/CHECK_OWNER/DOCKING을 오가며 배회하는 상태 머신 노드. /person_location을 구독해 사람 위치를 확인하고, MoveInterface로 Nav2 목표를 전송한다.',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            'idle_wander = petbot_idle_behavior.idle_wander:main',
            'idle_wander2 = petbot_idle_behavior.idle_wander2:main',
            'demo_square_path = petbot_idle_behavior.demo_square_path:main',
        ],
    },
)
