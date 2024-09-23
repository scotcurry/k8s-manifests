kubectl create secret generic datadog-secrets --from-literal api-key=$DD_API_KEY --from-literal app-key=$DD_APP_KEY
helm install curryware-datadog-operator datadog/datadog-operator
kubectl apply -f ./ddagent-operator.yaml
