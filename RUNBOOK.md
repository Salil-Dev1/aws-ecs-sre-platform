# Backend 5xx runbook and incident note

## Triage and recovery

1. Check the alarm and recent transitions:

   ```sh
   aws cloudwatch describe-alarms --region ap-south-1 --alarm-names taskflow-backend-high-5xx-rate
   aws cloudwatch describe-alarm-history --region ap-south-1 --alarm-name taskflow-backend-high-5xx-rate --max-records 10
   ```

2. Check the ECS deployment and recent service events:

   ```sh
   aws ecs describe-services --region ap-south-1 --cluster taskflow-cluster --services taskflow-backend
   aws logs tail /ecs/taskflow/backend --region ap-south-1 --since 15m
   ```

3. Verify the ALB health path and API response:

   ```sh
   curl -i http://taskflow-alb-1356420687.ap-south-1.elb.amazonaws.com/health
   curl -i http://taskflow-alb-1356420687.ap-south-1.elb.amazonaws.com/api/items
   ```

4. If the release is causing errors, set `HEALTHY_BACKEND_TASK_DEFINITION_ARN` to the recorded healthy ARN, then restore it:

   ```sh
   aws ecs update-service --region ap-south-1 --cluster taskflow-cluster \
     --service taskflow-backend --task-definition "$HEALTHY_BACKEND_TASK_DEFINITION_ARN"
   aws ecs wait services-stable --region ap-south-1 --cluster taskflow-cluster \
     --services taskflow-backend
   ```

5. Recheck `/health`, `GET /api/items`, service stability, and alarm state. Revert the bad source commit on `main` and push so subsequent deployments match the recovered code.

## Blameless postmortem — simulated v2 query regression

**Impact:** During the incident window, `GET /api/items` returned HTTP 500. `/health` remained 200. The target 5xx alarm crossed its threshold; the unhealthy-targets alarm stayed OK, so the targets were reachable and this was an application regression rather than a capacity or health-check failure.

| Event | UTC | IST | Record |
|---|---|---|---|
| Broken task definition `:3` registered/deployed | 2026-11-27 15:19:19 | 2026-11-27 20:49:19 | ECS `UpdateService` from CD |
| 45 failing requests sent over ~90 seconds; peak 27 5xx/min vs threshold 5 | 2026-11-27 15:21–15:22 | 2026-11-27 20:51–20:52 | ALB metric; alarm evaluated 26 at 15:21 |
| Alarm entered ALARM | 2026-11-27 15:24:16 UTC | 2026-11-27 20:54:16 IST | CloudWatch history |
| Rollback to healthy backend `:2` started | 2026-11-27 15:24:10 UTC | 2026-11-27 20:54:10 IST | ECS update requested; AWS recorded update at 15:24:11 |
| Rollback service stable | 2026-11-27 15:26:44 UTC | 2026-11-27 20:56:44 IST | ECS waiter succeeded |
| Alarm returned to OK | 2026-11-27 15:31:16 UTC | 2026-11-27 21:01:16 IST | CloudWatch history |

The rollback was issued six seconds before CloudWatch exposed the ALARM state because the alarm evaluation lagged the metric. The broken release was commit [`3bb6035`](https://github.com/Salil-Dev1/aws-ecs-sre-platform/commit/3bb6035); [`6f6e2b1`](https://github.com/Salil-Dev1/aws-ecs-sre-platform/commit/6f6e2b1) reverted it. Earlier pipeline permission repair [`7d008b8`](https://github.com/Salil-Dev1/aws-ecs-sre-platform/commit/7d008b8) enabled ECR image publishing. The successful incident and revert deployments are [run 46023689176](https://github.com/Salil-Dev1/aws-ecs-sre-platform/actions/runs/46023689176) and [run 46025030863](https://github.com/Salil-Dev1/aws-ecs-sre-platform/actions/runs/46025030863).

**Two follow-up actions**

1. Add a post-deploy smoke gate for `/health`, `GET /api/items`, and a disposable `POST /api/items`; fail the deployment if the API contract returns an unexpected status.
2. Add the CloudWatch metric timestamp and alarm transition lag to the alert dashboard/runbook, and review the alarm evaluation behavior during the next controlled load test.

Evidence: [alarm history JSON](evidence/alarm-history.json), [CloudWatch 5xx alarm screenshot](evidence/screenshots/cloudwatch-5xx-alarm.png), and [GitHub Actions CD screenshot](evidence/screenshots/github-actions-cd.png). Screenshot files were not present in this checkout.
