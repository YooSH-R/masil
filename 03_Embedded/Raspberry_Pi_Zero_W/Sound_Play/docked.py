import time

from audio import SoundPlayer

audio = SoundPlayer("sounds")   # 생성 순간: 음량 67% 설정 + keep-alive 자동 시작
audio.play("docked")            # sounds/docked.wav 논블로킹 재생

# play()는 subprocess.Popen으로 논블로킹 재생됩니다. 여기서 기다리지 않으면
# 스크립트가 즉시 종료되어 재생이 끝나기 전에 aplay가 끊깁니다.
while audio.is_playing():
    time.sleep(0.05)

audio.close()
