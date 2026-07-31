from setuptools import find_packages, setup
import os
from glob import glob

package_name = 'petbot_wakeword'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'models'),
            glob('petbot_wakeword/models/*.onnx') + glob('petbot_wakeword/models/*.onnx.data')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='jetson',
    maintainer_email='jetson@todo.todo',
    description='"마실아" 웨이크워드 인식 노드 (openWakeWord 커스텀 모델 기반)',
    license='TODO: License declaration',
    extras_require={
        'test': [
            'pytest',
        ],
    },
    entry_points={
        'console_scripts': [
            'wakeword_node = petbot_wakeword.wakeword_node:main',
        ],
    },
)
