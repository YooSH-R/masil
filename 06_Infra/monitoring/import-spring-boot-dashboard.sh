#!/usr/bin/env sh
set -eu

DASHBOARD_ID=17175
DASHBOARD_REVISION=1
DASHBOARD_URL="https://grafana.com/api/dashboards/$DASHBOARD_ID/revisions/$DASHBOARD_REVISION/download"
NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
CONFIGMAP_NAME=grafana-dashboard-spring-boot-observability
TEMP_DIR="$(mktemp -d)"
SOURCE_JSON="$TEMP_DIR/source.json"
OUTPUT_JSON="$TEMP_DIR/spring-boot-observability.json"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

for command_name in curl jq kubectl; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "$command_name is required" >&2
    exit 1
  }
done

curl -fsSLo "$SOURCE_JSON" "$DASHBOARD_URL"

# Dashboard 17175 expects Docker Compose's compose_service label. Replace its
# two Loki queries with the labels collected by Alloy from this k3s cluster.
jq '
  del(.__inputs)
  | .id = null
  | .uid = "mysil-spring-boot-observability"
  | .title = "Spring Boot Observability - MYSIL"
  | .version = 1
  | (.panels[] | select(.datasource.uid == "${DS_PROMETHEUS}") | .datasource.uid) = "prometheus"
  | (.panels[] | select(.datasource.uid == "${DS_LOKI}") | .datasource.uid) = "loki"
  | (.panels[].targets[]? | select(.datasource.uid == "${DS_PROMETHEUS}") | .datasource.uid) = "prometheus"
  | (.panels[].targets[]? | select(.datasource.uid == "${DS_LOKI}") | .datasource.uid) = "loki"
  | (.templating.list[] | select(.name == "app_name") | .datasource.uid) = "prometheus"
  | (.panels[] | select(.id == 14) | .targets[0].expr) = "sum by(stream) (rate({namespace=\"$namespace\", app=\"backend\"} |= \"$log_keyword\" [1m]))"
  | (.panels[] | select(.id == 2) | .targets[0].expr) = "{namespace=\"$namespace\", app=\"backend\"} |= \"$log_keyword\""
  | .templating.list = ([{
      "current": {"selected": true, "text": "s15a203-dev", "value": "s15a203-dev"},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "definition": "label_values(kube_pod_info{namespace=~\"s15a203-(dev|prod)\"}, namespace)",
      "hide": 0,
      "includeAll": false,
      "label": "Environment",
      "multi": false,
      "name": "namespace",
      "options": [],
      "query": {"query": "label_values(kube_pod_info{namespace=~\"s15a203-(dev|prod)\"}, namespace)", "refId": "StandardVariableQuery"},
      "refresh": 1,
      "regex": "",
      "skipUrlSync": false,
      "sort": 1,
      "type": "query"
    }] + .templating.list)
' "$SOURCE_JSON" > "$OUTPUT_JSON"

kubectl create configmap "$CONFIGMAP_NAME" \
  --namespace "$NAMESPACE" \
  --from-file=spring-boot-observability.json="$OUTPUT_JSON" \
  --dry-run=client -o yaml \
  | kubectl apply -f -

kubectl label configmap "$CONFIGMAP_NAME" \
  --namespace "$NAMESPACE" \
  grafana_dashboard=1 \
  --overwrite

kubectl annotate configmap "$CONFIGMAP_NAME" \
  --namespace "$NAMESPACE" \
  grafana_folder=MYSIL \
  dashboard-source="https://grafana.com/grafana/dashboards/17175-spring-boot-observability/" \
  --overwrite
