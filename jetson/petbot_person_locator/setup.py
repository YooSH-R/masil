from setuptools import find_packages, setup

package_name = 'petbot_person_locator'

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
    description='YOLO(카메라)와 라이다를 융합해 사람의 상대 위치를 추정하고, MoveInterface로 Nav2 목표를 전송해 접근하는 노드.',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
    	'console_scripts': [
        	'person_locator = petbot_person_locator.person_locator:main',
            'person_approach = petbot_person_locator.person_approach:main',
    	],
    },
)
