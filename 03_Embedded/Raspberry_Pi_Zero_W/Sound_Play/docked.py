from audio import SoundPlayer

audio = SoundPlayer("sounds")   # 생성 순간: 음량 67% 설정 + keep-alive 자동 시작
audio.play("docked")            # sounds/docked.wav 논블로킹 재생
