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

        dev_info = sd.query_devices(mic_device_index)
        mic_channels = int(dev_info.get('max_input_channels', 1))

        self.get_logger().info(f"마이크 스트림 개설 중... (channels={mic_channels}, samplerate=16000)")

        self._stream = sd.InputStream(
            device=mic_device_index,
            channels=mic_channels,          # ReSpeaker 지원 채널 수에 자동 맞춤
            samplerate=16000,
            callback=self._audio_callback,
            blocksize=1280
        )
        self._stream.start()

        self.get_logger().info(
            f'웨이크워드 노드 시작 (mic_device={mic_device_index}, model={self._model_name}, '
            f'threshold={self.threshold})')

    def _find_input_device(self, name_substring="respeaker"):
        import sounddevice as sd
        devices = sd.query_devices()
        
        # 1. 이름에 "respeaker"가 들어가고 '입력 채널(max_input_channels > 0)'이 존재하는 장치 탐색
        for idx, dev in enumerate(devices):
            dev_name = dev.get('name', '')
            if name_substring.lower() in dev_name.lower() and dev.get('max_input_channels', 0) > 0:
                self.get_logger().info(f"마이크 발견(sounddevice): index={idx} ({dev_name}), 입력채널={dev['max_input_channels']}")
                return idx
                
        # 2. 키워드 탐색 실패 시 입력 채널이 존재하는 첫 번째 장치 사용 (중단 방지)
        for idx, dev in enumerate(devices):
            if dev.get('max_input_channels', 0) > 0:
                self.get_logger().warn(f"ReSpeaker 검색 실패 - 유효한 첫 번째 입력 장치 사용: index={idx} ({dev.get('name')})")
                return idx

        self.get_logger().error("입력 가능한 마이크 장치를 찾지 못했습니다.")
        return 0

    def _audio_callback(self, indata, frames, time, status):
        if status:
            self.get_logger().warn(f"Audio status: {status}")

        # 다채널(2채널 등)로 들어올 경우 첫 번째 채널(Mono)만 추출
        if indata.ndim > 1 and indata.shape[1] > 1:
            audio_data = indata[:, 0]
        else:
            audio_data = indata.squeeze()

        try:
            self._audio_queue.put_nowait(audio_data.copy())    # ✅ 정제된 audio_data 입력
        except queue.Full:
            try:
                self._audio_queue.get_nowait()
            except queue.Empty:
                pass
            try:
                self._audio_queue.put_nowait(audio_data.copy())   # ✅ 정제된 audio_data 입력
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
