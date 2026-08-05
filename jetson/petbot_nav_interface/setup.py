from setuptools import find_packages, setup

package_name = 'petbot_nav_interface'

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
    description='Nav2 SimpleCommander를 감싼 공용 이동 인터페이스(MoveInterface). 좌표를 넘기면 이동/취소/피드백 조회가 가능한 액션을 제공한다.',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
    'console_scripts': [
        'move_test = petbot_nav_interface.move_test_node:main',
      ],
    },
)
