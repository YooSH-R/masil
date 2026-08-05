#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required" >&2
  exit 1
}
command -v helm >/dev/null 2>&1 || {
  echo "helm 3 is required" >&2
  exit 1
}

test "$(kubectl auth can-i create namespaces 2>/dev/null)" = "yes" || {
  echo "cluster-admin compatible kubeconfig is required" >&2
  exit 1
}

helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts --force-update
helm repo add grafana-community \
  https://grafana-community.github.io/helm-charts --force-update
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update

helm upgrade --install monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$SCRIPT_DIR/kube-prometheus-stack-values.yaml" \
  --wait --timeout 10m

helm upgrade --install loki grafana-community/loki \
  --namespace "$NAMESPACE" \
  --values "$SCRIPT_DIR/loki-values.yaml" \
  --wait --timeout 10m

helm upgrade --install alloy grafana/alloy \
  --namespace "$NAMESPACE" \
  --values "$SCRIPT_DIR/alloy-values.yaml" \
  --wait --timeout 10m

kubectl apply -n s15a203-dev -f "$SCRIPT_DIR/../dev/service-monitor.yaml"

echo "Monitoring stack is ready."
echo "Grafana admin password:"
kubectl get secret -n "$NAMESPACE" monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
echo
echo "Open Grafana: https://i15a203.p.ssafy.io/grafana"
echo "Local fallback:"
echo "kubectl port-forward -n $NAMESPACE svc/monitoring-grafana 3000:80"
