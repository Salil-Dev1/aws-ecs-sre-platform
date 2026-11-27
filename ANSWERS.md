# Engineering answers

## Part 1 — Application, containers, and log triage

- The backend is Python 3.12 / FastAPI with PyMongo, Prometheus metrics, request IDs, and structured JSON request logs. `/health` pings MongoDB; `/api/items` supports list/create/delete; `/metrics` exposes Prometheus metrics.
- MongoDB uses `taskflowdb` by default, matching the Atlas `readWrite` grant and the database in `/taskflow/prod/mongo_uri`.
- The frontend is a React/Vite SPA served by unprivileged Nginx on port 8080. Both Dockerfiles are built from the repository root (`-f app/backend/Dockerfile .`, `-f app/frontend/Dockerfile .`).
- `scripts/triage.sh [logfile]` reports top endpoints, 5xx counts by minute, and the ten slowest requests. The checked-in sample has 413 access-log lines.
- Local entry point: `docker compose up --build -d`; teardown for the local stack: `docker compose down -v`.

## Part 3 — AWS platform and deployment

- Terraform uses the default VPC, an internet-facing ALB, and separate backend/frontend security groups. Listener rules route API, health, and metrics paths to the backend and other paths to the frontend.
- ECS runs 2 backend and 1 frontend Fargate tasks (each 256 CPU / 512 MB). Images are built for `linux/amd64` and tagged by commit SHA.
- MongoDB Atlas M0 stores application data in `taskflowdb`. ECS injects `MONGO_URI` from SSM Parameter Store SecureString; the task role has no extra application permissions.
- GitHub Actions uses OIDC with a trust condition restricted to this repository’s `main` branch. ECR and ECS permissions are scoped to the deployment role.
- Cost/security assumptions: no NAT gateways or RDS; public-IP Fargate tasks use the default VPC. Atlas M0 requires the broad `0.0.0.0/0` access entry in this no-NAT setup. The ALB currently serves HTTP without TLS.

## Part 5 — Monitoring and operations

| Signal | Configuration | Purpose |
|---|---|---|
| Target 5xx | `HTTPCode_Target_5XX_Count`, sum, 60 seconds, threshold ≥5 | Detect backend errors |
| Backend p95 | `TargetResponseTime`, p95 >1 second for 2 periods | Detect sustained latency |
| Unhealthy targets | `UnHealthyHostCount` maximum >0 for 1 period | Detect unavailable targets |
| Logs | `/ecs/taskflow/backend` and `/ecs/taskflow/frontend`, 7-day retention | Request and service investigation |

The incident alarm entered ALARM at `2026-11-27 15:24:16 UTC` (`20:54:16 IST`) on 26 target 5xx in the evaluated minute; the observed minute peak was 27 against the threshold of 5. The unhealthy-targets alarm stayed OK. Alarm history is in [evidence/alarm-history.json](evidence/alarm-history.json).

## Assumptions and stretch latency SLO

- `main` is the production branch; merging a PR triggers the OIDC deployment.
- Atlas M0 is adequate for this demonstration workload; no production data durability or throughput guarantee is assumed.
- Stretch SLO proposal: monthly API availability ≥99.5% and successful-request p95 <250 ms at 20 requests/second. This target has not been load-tested; the configured >1-second p95 alarm is an operational warning, not proof of the SLO.

## Run records

- PR #1: [Fix MongoDB database selection and add OIDC CI/CD](https://github.com/Salil-Dev1/aws-ecs-sre-platform/pull/1) — merged 2026-11-27.
- Passing CI: [run 46020243916](https://github.com/Salil-Dev1/aws-ecs-sre-platform/actions/runs/46020243916).
- Successful incident deployment: [run 46023689176](https://github.com/Salil-Dev1/aws-ecs-sre-platform/actions/runs/46023689176).
- Successful revert deployment: [run 46025030863](https://github.com/Salil-Dev1/aws-ecs-sre-platform/actions/runs/46025030863).
- Supporting screenshots: [CloudWatch 5xx alarm](evidence/screenshots/cloudwatch-5xx-alarm.png), [GitHub Actions CD](evidence/screenshots/github-actions-cd.png). Image files were not present in the checkout when these docs were written.
