# Mosquitto MQTT Broker

Mosquitto는 단일 replica StatefulSet과 전용 PVC로 실행한다. 기본 Service는
클러스터 내부 Spring Boot 연결용이며, dev 오버레이만 테스트용 NodePort 31883을
노출한다. 운영 외부 연결은 TLS 구성이 완료되기 전까지 노출하지 않는다.

## Secret 생성

백엔드 ACL의 사용자명은 `backend`로 고정되어 있다. 테스트 기기 사용자명은
반드시 MQTT 메시지의 `deviceId`와 같아야 한다.

```sh
kubectl -n <namespace> create secret generic mosquitto-credentials \
  --from-literal=MQTT_BACKEND_USERNAME=backend \
  --from-literal=MQTT_BACKEND_PASSWORD='<strong-password>' \
  --from-literal=MQTT_DEVICE_USERNAME=device-001 \
  --from-literal=MQTT_DEVICE_PASSWORD='<strong-password>'
```

```sh
kubectl -n <namespace> create secret generic backend-mqtt-secret \
  --from-literal=MQTT_USERNAME=backend \
  --from-literal=MQTT_PASSWORD='<strong-password>'
```

## 배포

```sh
kubectl apply -k 06_Infra/mosquitto/k8s/dev
```

현재 init container는 최초 연동용 기기 계정 하나를 만든다. 여러 기기를 운영할
때는 기기 등록 시 credential을 발급하고 password file을 안전하게 갱신하는 별도
프로비저닝 절차가 필요하다.
