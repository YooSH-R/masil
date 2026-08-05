# k3s 모니터링 설치 안내

이 디렉터리의 설정은 소규모 클러스터용 모니터링 환경을 `monitoring`
네임스페이스에 설치합니다.

- `kube-prometheus-stack`: Prometheus, Grafana, Alertmanager,
  kube-state-metrics, node-exporter
- Loki: 단일 복제본 모놀리식 구성, 로그 보관 기간 7일
- Grafana Alloy: DaemonSet으로 실행하며 Kubernetes 컨테이너 로그 수집
- `ServiceMonitor`: Spring Boot 백엔드의 Prometheus 메트릭 수집

## 설치 전 준비 사항

- Kubernetes 1.25 이상
- Helm 3
- 클러스터 관리자 권한으로 설정된 `kubectl`
- k3s의 `local-path` StorageClass
- 모니터링 구성요소가 사용할 수 있는 메모리 최소 2GiB

Jenkins 서비스 계정은 특정 네임스페이스에만 권한을 갖도록 제한되어 있으므로
최초 설치에 사용하지 않습니다. 클러스터 관리자 권한이 설정된 환경에서 다음
명령을 실행합니다.

```sh
sh 06_Infra/monitoring/install.sh
```

`ServiceMonitor`가 백엔드 메트릭을 정상적으로 수집하려면 현재 브랜치에 추가된
Actuator 및 Micrometer 변경 사항이 백엔드 이미지에 포함되어 있어야 합니다.

설치 스크립트는 개발 환경의 `ServiceMonitor`를 자동으로 적용합니다. 운영
백엔드를 배포한 후에는 운영 환경 메트릭 수집 대상을 별도로 추가합니다.

```sh
kubectl apply -f 06_Infra/prod/service-monitor.yaml
```

## Grafana 접속

Prometheus와 Loki는 클러스터 내부에서만 접근하도록 유지합니다. Grafana는 다음
주소로 접속합니다.

```text
https://i15a203.p.ssafy.io/grafana
```

외부 Ingress에 문제가 있을 때는 다음과 같이 로컬 포트 포워딩으로도 접속할 수
있습니다.

```sh
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

브라우저에서 `http://localhost:3000`을 엽니다. 사용자 이름은 `admin`이며,
설치 스크립트가 자동 생성된 비밀번호를 출력합니다. 비밀번호를 다시 확인하려면
다음 명령을 실행합니다.

```sh
kubectl get secret -n monitoring monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

## 수집 상태 확인

다음 명령으로 모니터링 Pod, 개발 환경의 `ServiceMonitor`, Prometheus 접속 상태를
확인합니다.

```sh
kubectl get pods -n monitoring
kubectl get servicemonitor -n s15a203-dev
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Prometheus 화면에서 다음 쿼리를 실행하면 개발 환경의 수집 대상이 정상인지 확인할
수 있습니다.

```promql
up{namespace="s15a203-dev"}
```

Grafana의 Explore 메뉴에서 Loki 데이터 소스를 선택하고 다음 쿼리를 실행하면
백엔드 로그를 확인할 수 있습니다.

```logql
{namespace="s15a203-dev", app="backend"}
```

## 저장 용량과 보관 기간

기본값은 단일 노드 개발용 k3s 클러스터를 기준으로 설정되어 있습니다.

- Prometheus: 10GiB PVC, 데이터 보관 기간 7일
- Loki: 10GiB PVC, 로그 보관 기간 7일
- Grafana: 2GiB PVC

운영 환경에서는 Loki 저장소로 외부 오브젝트 스토리지를 사용하는 것을 권장합니다.
또한 애플리케이션 노드 장애로 서비스와 모니터링 데이터가 동시에 유실되지 않도록
별도의 모니터링 노드나 관리형 모니터링 서비스를 사용하는 것이 좋습니다.
