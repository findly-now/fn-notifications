# fn-notifications

**Document Ownership**: This document OWNS Notifications domain specifications, multi-channel delivery, and event-driven processing.

**Enterprise notification microservice with Broadway event processing on GKE Autopilot**

## Service Overview

Privacy-first multi-channel notification delivery system built with Elixir/Phoenix, Broadway for Kafka event processing, and optimized for GKE Autopilot deployment. Processes 100K+ events/hour with sub-second latency.

**Stack**: Elixir/OTP 25+ • Phoenix 1.7+ • Broadway • Confluent Kafka • Cloud PostgreSQL • Twilio

## Prerequisites

### Local Development
- Elixir 1.15+ with OTP 25+
- Docker & docker-compose
- Google Cloud SDK (`gcloud`)
- Helm 3.12+
- kubectl 1.28+

### GKE Requirements
- GKE Autopilot cluster (managed via Terraform)
- Workload Identity enabled
- Google Secret Manager for credentials
- Artifact Registry for container images

## Environment Variables

### Development (`.env.dev`)
```bash
# Broadway/Kafka Configuration
KAFKA_BROKERS=pkc-dev.confluent.cloud:9092
KAFKA_API_KEY=${SECRET_MANAGER:kafka-api-key-dev}
KAFKA_API_SECRET=${SECRET_MANAGER:kafka-api-secret-dev}
BROADWAY_CONCURRENCY=10
BROADWAY_BATCH_SIZE=100
BROADWAY_BATCH_TIMEOUT=1000

# Phoenix/BEAM Configuration
PORT=4000
POOL_SIZE=10
SECRET_KEY_BASE=${SECRET_MANAGER:phoenix-secret-key}
PHX_HOST=notifications-dev.findly.app
BEAM_COOKIE=${SECRET_MANAGER:erlang-cookie}

# Database
DATABASE_URL=${SECRET_MANAGER:postgres-url-dev}
DATABASE_POOL_SIZE=10
DATABASE_QUEUE_TARGET=50
DATABASE_QUEUE_INTERVAL=1000
```

### Production (`.env.prod`)
```bash
# Broadway/Kafka Configuration (Higher throughput)
KAFKA_BROKERS=pkc-prod.confluent.cloud:9092
KAFKA_API_KEY=${SECRET_MANAGER:kafka-api-key-prod}
KAFKA_API_SECRET=${SECRET_MANAGER:kafka-api-secret-prod}
BROADWAY_CONCURRENCY=50
BROADWAY_BATCH_SIZE=500
BROADWAY_BATCH_TIMEOUT=5000

# Phoenix/BEAM Configuration
PORT=4000
POOL_SIZE=20
SECRET_KEY_BASE=${SECRET_MANAGER:phoenix-secret-key}
PHX_HOST=notifications.findly.app
BEAM_COOKIE=${SECRET_MANAGER:erlang-cookie}
MIX_ENV=prod

# Database (Larger pools for production)
DATABASE_URL=${SECRET_MANAGER:postgres-url-prod}
DATABASE_POOL_SIZE=20
DATABASE_QUEUE_TARGET=100
DATABASE_QUEUE_INTERVAL=2000
```

## CI/CD Pipeline

### GitHub Actions Workflow
```yaml
# .github/workflows/deploy-notifications.yml
on:
  push:
    branches: [main]
    paths: ['fn-notifications/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - Build multi-stage Docker image
      - Run dialyzer & credo checks
      - Execute E2E tests
      - Push to Google Artifact Registry
      - Deploy with Helm to GKE
      - Verify health checks
```

## Deployment Commands

```bash
# Build & push container
docker build --build-arg MIX_ENV=prod -t fn-notifications .
docker tag fn-notifications gcr.io/${PROJECT_ID}/fn-notifications:${VERSION}
docker push gcr.io/${PROJECT_ID}/fn-notifications:${VERSION}

# Deploy with Helm
helm upgrade --install fn-notifications ./helm/fn-notifications \
  --namespace findly \
  --set image.tag=${VERSION} \
  --set environment=prod \
  --wait --timeout=5m

# Verify deployment
kubectl get pods -n findly -l app=fn-notifications
kubectl logs -n findly -l app=fn-notifications --tail=50

# Scale Broadway processors
kubectl scale deployment fn-notifications --replicas=3 -n findly
```

## Health Check Endpoints

### Phoenix LiveView Dashboard
- **URL**: `/` - Real-time monitoring dashboard
- **Metrics**: Broadway pipeline stats, delivery rates, error tracking

### Kubernetes Probes
```yaml
# /api/health - Liveness probe
livenessProbe:
  httpGet:
    path: /api/health
    port: 4000
  initialDelaySeconds: 30
  periodSeconds: 10

# /api/ready - Readiness probe (checks Broadway & DB)
readinessProbe:
  httpGet:
    path: /api/ready
    port: 4000
  initialDelaySeconds: 10
  periodSeconds: 5
```

## Broadway Consumer Monitoring

### Metrics Exposed
- `broadway_pipeline_processed_total` - Events processed
- `broadway_pipeline_failed_total` - Failed events
- `broadway_batch_duration_seconds` - Batch processing time
- `broadway_consumer_lag` - Kafka consumer lag

### Monitoring Commands
```bash
# Check Broadway pipeline status
kubectl exec -it deploy/fn-notifications -n findly -- \
  bin/fn_notifications remote

# Monitor consumer lag
kubectl exec -it deploy/fn-notifications -n findly -- \
  bin/fn_notifications eval "FnNotifications.Broadway.stats()"

# View Broadway supervision tree
kubectl exec -it deploy/fn-notifications -n findly -- \
  bin/fn_notifications eval ":observer.start()"
```

## Troubleshooting

### BEAM/OTP Issues on K8s

#### Memory Issues
```bash
# Check BEAM memory usage
kubectl top pod -n findly -l app=fn-notifications

# Adjust BEAM flags in deployment
env:
  - name: ERL_MAX_ETS_TABLES
    value: "5000"
  - name: ERLANG_MAX_PROCESSES
    value: "1000000"
  - name: ERLANG_MEMORY_CHECK
    value: "true"
```

#### Distribution/Clustering
```bash
# Check node connectivity
kubectl exec -it deploy/fn-notifications -n findly -- \
  bin/fn_notifications eval "Node.list()"

# Debug distribution issues
kubectl logs -n findly -l app=fn-notifications | grep "nodedown"
```

#### Broadway Pipeline Stalls
```bash
# Restart Broadway pipeline
kubectl exec -it deploy/fn-notifications -n findly -- \
  bin/fn_notifications eval "FnNotifications.Broadway.restart()"

# Check for poison messages
kubectl exec -it deploy/fn-notifications -n findly -- \
  bin/fn_notifications eval "FnNotifications.Broadway.failed_messages()"
```

### Common K8s Issues

#### Pod Crashes/Restarts
```bash
# Check crash logs
kubectl describe pod -n findly -l app=fn-notifications
kubectl logs -n findly -l app=fn-notifications --previous

# Common fixes:
# 1. Increase memory limits (BEAM needs headroom)
# 2. Adjust liveness probe timing
# 3. Check for OOM kills
```

#### Secret Management Issues
```bash
# Verify secrets are mounted
kubectl exec -it deploy/fn-notifications -n findly -- ls /var/secrets

# Check Workload Identity binding
kubectl describe sa fn-notifications-sa -n findly
```

#### Broadway Consumer Lag
```bash
# Scale up consumers
kubectl scale deployment fn-notifications --replicas=5 -n findly

# Increase Broadway concurrency (requires restart)
kubectl set env deployment/fn-notifications \
  BROADWAY_CONCURRENCY=100 -n findly
```

## Quick Start

```bash
# Local development
make setup && make up
curl http://localhost:4000/api/health

# GKE deployment
make docker-build ENV=prod
make helm-deploy ENV=prod
make verify-deployment ENV=prod
```

**Dashboard**: http://localhost:4000 (dev) | https://notifications.findly.app (prod)

## Core Features

- **Multi-channel delivery**: Email, SMS, WhatsApp with privacy protection
- **Event-driven**: Real-time Kafka processing with complete context via Broadway
- **Enterprise resilience**: Circuit breakers, bulkheads, retry mechanisms
- **User preferences**: Granular notification controls extracted from events
- **Secure Contact Exchange**: Encrypted contact sharing workflow with time-limited access
- **Privacy Compliance**: GDPR/CCPA compliant with audit trails

## Events & Contact Exchange Workflow

### Event Consumption
All events include complete context to eliminate cross-service API calls:

```elixir
# Fat event with complete user and organization context
%{
  "event_type" => "post.matched",
  "payload" => %{
    "post" => %{"id" => "post-123", "title" => "Lost iPhone"},
    "matched_post" => %{"id" => "post-456", "title" => "Found iPhone"},
    "users" => %{
      "reporter" => %{
        "id" => "user-789",
        "display_name" => "John D.",  # No email/phone in events
        "preferences" => %{
          "notification_channels" => ["email"],
          "timezone" => "America/New_York"
        }
      },
      "finder" => %{...}
    },
    "organization" => %{
      "settings" => %{
        "auto_expire_days" => 30,
        "match_confidence_threshold" => 0.8
      }
    }
  },
  "privacy" => %{
    "contact_token" => "encrypted_token_here",
    "contact_expires" => "2024-01-15T11:30:00Z"
  }
}
```

### Contact Exchange Notifications

```elixir
# Contact exchange request notification
%{
  "event_type" => "contact.exchange.requested",
  "payload" => %{
    "request" => %{
      "id" => "exchange-123",
      "post_id" => "post-456",
      "requester_user" => %{"display_name" => "Jane D."},
      "owner_user" => %{"display_name" => "John D."},
      "message" => "I think this is my phone",
      "verification_required" => true
    }
  }
}

# Contact exchange approved with encrypted contact info
%{
  "event_type" => "contact.exchange.approved",
  "payload" => %{
    "approval" => %{
      "contact_info" => %{
        "email" => "encrypted_email_here",
        "phone" => "encrypted_phone_here",
        "expires_at" => "2024-01-15T12:00:00Z"
      }
    }
  }
}
```

## Database Isolation

- **Domain Database**: `notifications_db` with complete data sovereignty
- **No Cross-Domain Queries**: Never accesses other services' databases
- **Events Enable Autonomy**: All needed data included in events
- **Contact Exchange**: Secure storage of encrypted contact exchange requests

## Environment Configuration

### Kafka Topic Configuration
The service supports configurable Kafka topic names via environment variables:

```bash
# Fat event topic names (with defaults)
KAFKA_POSTS_TOPIC=posts.events            # Fat posts events
KAFKA_MATCHER_TOPIC=posts.matching        # Fat matcher events
KAFKA_USERS_TOPIC=users.events            # Fat user events
KAFKA_CONTACT_EXCHANGE_TOPIC=contact.exchange # Contact exchange events
```

### Privacy & Performance Benefits

- **Zero PII in Events**: Contact information never transmitted in event streams
- **10x Performance**: 50-100ms processing vs 500-2000ms with API calls
- **Complete Context**: User preferences and organization settings in events
- **Secure Contact Exchange**: Encrypted tokens with time-limited access
- **Audit Compliance**: Full GDPR/CCPA compliance with audit trails

## Documentation

- **[DEVELOPMENT.md](./DEVELOPMENT.md)** - Complete development guide
- **[../fn-docs/](../fn-docs/)** - Architecture and standards