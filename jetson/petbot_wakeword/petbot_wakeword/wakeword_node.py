import os
import queue
import threading
import time

import rclpy
import sounddevice as sd
from ament_index_python.packages import get_package_share_directory
from rclpy.node import Node
from std_msgs.msg import Bool

# Max queued audio chunks before dropping the oldest (~4s of audio at 80ms/chunk)
AUDIO_QUEUE_MAXSIZE = 50


class WakewordNode(Node):
    def __init__(self):
        super().__init__('wakeword_node')

        share_dir = get_package_share_directory('petbot_wakeword')

        self.declare_parameter('mic_device_index', -1)
        self.declare_parameter('mic_device_name', 'ReSpeaker')
        self.declare_parameter('model_path',
                                os.path.join(share_dir, 'models', 'masila.onnx'))
        self.declare_parameter('threshold', 0.5)
        self.declare_parameter('debounce_sec', 3.0)
        self.declare_parameter('chunk_size', 1280)

        mic_device_index = self.get_parameter('mic_device_index').value
        mic_device_name = self.get_parameter('mic_device_name').value
        if mic_device_index < 0:
            mic_device_index = self._find_input_device(mic_device_name)
        model_path = self.get_parameter('model_path').value
        self.threshold = self.get_parameter('threshold').value
        self.debounce_sec = self.get_parameter('debounce_sec').value
        self.chunk_size = self.get_parameter('chunk_size').value

        if not os.path.exists(model_path):
            raise RuntimeError(f'웨이크워드 모델 파일이 없습니다: {model_path}')

        from openwakeword.model import Model
        self._model = Model(wakeword_models=[model_path], inference_framework='onnx')
        self._model_name = list(self._model.models.keys())[0]

        self._publisher = self.create_publisher(Bool, '/wakeword_detected', 10)
        self._last_trigger_time = 0.0

        # Audio callback only enqueues raw PCM; inference/publish happens on a worker
        # thread so the realtime PortAudio callback thread never blocks on model inference.
        self._audio_queue: queue.Queue = queue.Queue(maxsize=AUDIO_QUEUE_MAXSIZE)
        self._stop_event = threading.Event()
        self._worker_thread = threading.Thread(target=self._inference_worker, daemon=True)
        self._worker_thread.start()

        self._stream = sd.InputStream(
            samplerate=16000,
            blocksize=self.chunk_size,
            device=mic_device_index,
            channels=1,
            dtype='int16',
            callback=self._audio_callback,
        )
        self._stream.start()

        self.get_logger().info(
            f'웨이크워드 노드 시작 (mic_device={mic_device_index}, model={self._model_name}, '
            f'threshold={self.threshold})')

    def _find_input_device(self, name_substring):
        for i, d in enumerate(sd.query_devices()):
            if d['max_input_channels'] > 0 and name_substring.lower() in d['name'].lower():
                self.get_logger().info(f"마이크 자동탐색: index={i} ({d['name']})")
                return i
        raise RuntimeError(f'"{name_substring}"가 포함된 입력 장치를 찾을 수 없습니다.')

    def _audio_callback(self, indata, frames, time_info, status):
        # Runs on PortAudio's realtime thread: keep this as cheap as possible.
        if status:
            self.get_logger().warn(f'오디오 스트림 상태: {status}')

        try:
            self._audio_queue.put_nowait(indata[:, 0].copy())
        except queue.Full:
            # Consumer can't keep up; drop the oldest chunk to make room rather than
            # blocking the realtime callback.
            try:
                self._audio_queue.get_nowait()
            except queue.Empty:
                pass
            try:
                self._audio_queue.put_nowait(indata[:, 0].copy())
            except queue.Full:
                pass

    def _inference_worker(self):
        while not self._stop_event.is_set():
            try:
                pcm = self._audio_queue.get(timeout=0.5)
            except queue.Empty:
                continue

            prediction = self._model.predict(pcm)
            score = prediction[self._model_name]

            if score > self.threshold:
                now = time.monotonic()
                if now - self._last_trigger_time < self.debounce_sec:
                    continue
                self._last_trigger_time = now

                self.get_logger().info(f'웨이크워드 감지: 마실아 (score={score:.3f})')
                msg = Bool()
                msg.data = True
                self._publisher.publish(msg)

    def destroy_node(self):
        self._stream.stop()
        self._stream.close()
        self._stop_event.set()
        self._worker_thread.join(timeout=2.0)
        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = WakewordNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
