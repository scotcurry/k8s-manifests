# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview
These are plain Kubernetes YAML manifests for the single-node MicroK8s cluster at `ubuntu-microk8s.curryware.org`.
The remote is `github.com/scotcurry/k8s-manifests`, and the default branch is `main`. There is no Helm chart,
Kustomize or templating. Each file is applied as is.

## Deployment Model (GitOps)
- Argo CD watches this repo and syncs the cluster from it. The Argo CD `Application` definitions are **not** in this
  repo. The `argocd/` folder only holds Argo CD's own ingress, TLS and config.
- Each service repo's GitHub Actions build bumps the image tag here automatically, so most commits look like
  `Committed <file-or-service> <timestamp> - Short SHA: <sha>`. Pull before editing (`git pull origin main`) to
  avoid conflicts with these CI commits.
- A deployment's image tag and its `tags.datadoghq.com/version` labels must match. CI updates both, and a manual
  bump must update all three places: the image, the Deployment labels and the pod template labels.

## Layout
| Folder | Contents |
|---|---|
| `curryware-fantasy/` | App workloads in the `curryware` namespace: yahoo-api (8087), java-api-server (8080), kafka-go-processor (no Service), front-end (Service 80 → 8000), and the `curryware-nflverse-stats` CronJob |
| `traefik-ingress/` | Gateway API ingress: `traefik` GatewayClass, `traefik-gateway` in namespace `ingress` (HTTP 8000, HTTPS 8443), the strip-prefix Middleware, and the cert-manager Let's Encrypt Issuer. There is no Certificate manifest: the gateway's `cert-manager.io/issuer` annotation makes cert-manager create and own the `ubuntu-microk8s-tls` Certificate. Don't add a second Certificate for that secret |
| `argocd/` | Argo CD namespace, HTTPRoute, TLS cert, and the `server.insecure` ConfigMap (TLS ends at the gateway) |
| `datadog/` | Datadog Operator and Helm setup (`deploy-ddagent.sh`, `ddagent-operator.yaml`, `helm-values.yaml`) and a host-agent config template |
| `postgresql/` | Old in-cluster Postgres (local PV at `/var/curryware-db`). The apps now use the external `postgres.curryware.org` |
| `additional-projects/` | Unrelated side projects and an old nginx IngressClass |

## Routing
External traffic reaches `https://ubuntu-microk8s.curryware.org` and goes through `traefik-gateway`, then an
HTTPRoute per service:
- `/cw_api/*` → `curryware-yahoo-api:8087`
- `/java/*` → `curryware-java-api-server-service:8080`
- `/` → `argocd-server:80`

The `strip-cwapi-java-prefix` Middleware removes both `/cw_api` and `/java`. A new path prefix must be added to
that Middleware as well as to the HTTPRoute. Only namespaces labeled `shared-gateway-access: "true"` can attach
routes to the gateway.

Some older files (`argocd/curryware-argocd-ingress-controller.yaml`, the `ingressClassName: nginx` Issuers,
`additional-projects/curryware-nginx-ingress-class.yaml`) come from the nginx-ingress setup that came before Traefik.
Gateway API with Traefik is the current approach.

## Secrets
`*secrets*` files are gitignored and must never be committed. They are applied to the cluster by hand. Workloads
read the Postgres login from the `curryware-postgres-secrets` Secret (`postgres-username`, `postgres-password`).
Non-secret DB settings are set inline: `POSTGRES_SERVER=postgres.curryware.org`, `POSTGRES_PORT=5432`,
`POSTGRES_DATABASE=currywarefantasy`. The nflverse CronJob is different: it uses `POSTGRES_HOST`/`POSTGRES_USER`
and also pulls in a `curryware-postgres` Secret through `envFrom`.

## Datadog Conventions
All workloads use Datadog single-step instrumentation through the admission controller, so no tracer is built into
the images:
- Pod label `admission.datadoghq.com/enabled: "true"`. Pin the tracer version with an
  `admission.datadoghq.com/<lang>-lib.version` annotation (java, dotnet, python).
- Unified service tags `tags.datadoghq.com/{env,service,version}` go on both the Deployment and the pod template.
- The common `DD_*` env vars are `DD_LOGS_INJECTION`, `DD_RUNTIME_METRICS_ENABLED`, `DD_APPSEC_ENABLED`, and
  `DD_DATA_STREAMS_ENABLED` for the Kafka producer and consumer.
- The Go processor sends traces over the UDS socket at `/var/run/datadog/apm.socket`, mounted from the host.

## Commands
```bash
kubectl apply --dry-run=server -f <file>.yaml   # validate against the cluster's API (catches bad apiVersion/kind)
kubectl diff -f <file>.yaml                     # see what a change would do before Argo CD syncs it
kubectl apply -f <file>.yaml                    # apply by hand (secrets, or resources Argo CD does not manage)
```
