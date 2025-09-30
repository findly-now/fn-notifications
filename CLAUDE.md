# CLAUDE.md

**Document Ownership**: This document OWNS Notifications domain AI guidance, Elixir patterns, and Broadway configuration.

This file provides guidance to Claude Code (claude.ai/code) when working with the FN Notifications Service codebase.

## Essential Commands

### Development
```bash
# Basic workflow
make up                    # Start application (connects to cloud services)
make down                  # Stop application
make setup                 # Install dependencies and deploy cloud schema
make test                  # Run E2E tests only
make logs                  # View application logs

# Manual development (if needed)
mix deps.get              # Install dependencies
mix phx.server            # Start Phoenix server
mix compile               # Compile application
mix test                  # Run E2E test suite
```

### Cloud Database Management
```bash
make deploy-schema-postgres    # Deploy schema to cloud PostgreSQL
psql "$DATABASE_URL" -f schema.sql  # Apply schema directly
```

### Code Quality
```bash
mix format               # Format code
mix credo                # Static analysis (lint)
```

## Architecture Overview

This is an **enterprise-grade notification microservice** for **Lost & Found platforms** implementing comprehensive **Domain-Driven Design (DDD)** patterns with **resilience features**. The system processes events from Kafka and delivers notifications via multiple channels (Email, SMS, WhatsApp).

### Core Context: Lost & Found Ecosystem

**Critical Understanding**: This service enables rapid reunification of lost items through intelligent notifications. Events like `post.created`, `post.matched`, `post.claimed`, and `post.resolved` all relate to the Lost & Found item lifecycle.

**Key Business Flow**:
```
📋 Item Reported          → 📧 Confirmation + area alerts
🔍 Match Detected         → 📧📱 Both parties notified instantly
🏃 Someone Claims         → 📱 URGENT: SMS to reporter
✅ Item Recovered         → 📧 Success story + feedback request
```

### Architectural Patterns

**Domain-Driven Design (DDD)**:
- **Entities**: `Notification`, `UserPreferences` with business logic
- **Aggregates**: `NotificationAggregate` manages consistency boundaries
- **Value Objects**: `NotificationChannel`, `NotificationStatus`
- **Anti-Corruption Layer**: `EventTranslator` protects domain from external schemas
- **Domain Services**: Business logic that doesn't belong to entities

**Resilience Patterns**:
- **Circuit Breaker**: Protects external service calls (Twilio, Email)
- **Bulkhead**: Resource isolation with separate pools per channel
- **Health Checks**: Cloud-compatible monitoring endpoints
- **Retry Logic**: Exponential backoff with different strategies per component

### Layer Structure

```
lib/fn_notifications/
├── application/           # Application layer - orchestration
│   ├── services/         # Application services
│   ├── commands/         # Command objects
│   ├── event_handlers/   # Broadway event processors
│   └── anti_corruption/  # External event translation
├── domain/               # Domain layer - business logic
│   ├── entities/         # Domain entities
│   ├── aggregates/       # Aggregate roots
│   ├── value_objects/    # Value objects
│   └── services/         # Domain services (circuit breaker, bulkhead)
├── infrastructure/       # Infrastructure layer - external concerns
│   ├── adapters/         # External service adapters
│   ├── repositories/     # Data persistence
│   ├── schemas/          # Ecto schemas
│   └── clients/          # HTTP clients
└── lib/fn_notifications_web/  # Web layer - Phoenix controllers, LiveView
```

## Core Technologies

- **Elixir/OTP**: Fault tolerance and concurrency
- **Phoenix**: Web framework with LiveView for real-time UI
- **Confluent Cloud Kafka + Broadway**: Event streaming and processing
- **Cloud PostgreSQL**: Data persistence with JSONB for metadata
- **Swoosh**: Email delivery
- **Twilio**: SMS and WhatsApp delivery
- **Google Cloud Storage**: File and template storage
- **Docker**: Unified containerized deployment (single Dockerfile for all environments)

## Development Guidelines

### Domain Layer Rules
- **No infrastructure dependencies** in domain layer
- Entities contain business logic and invariants
- Use aggregates to maintain consistency boundaries
- Domain services for logic that doesn't belong to entities
- Value objects for immutable concepts

### Event Processing
- External fat events come from Confluent Cloud Kafka via Broadway with complete context
- Internal domain events use Phoenix.PubSub
- `FatEventTranslator` converts fat external events to domain commands (NO API calls needed)
- All event handlers are in `application/event_handlers/`
- Contact exchange events processed with encrypted contact information

### Contact Information Architecture with Events
**UPDATED**: Contact info comes from fat events or secure contact exchange - NO database queries to other domains.

**Events Flow**:
1. Fat event contains privacy-safe user context with preferences (NO email/phone)
2. Contact exchange creates encrypted contact tokens when needed
3. Delivery service decrypts contact info only during actual delivery
4. Contact info never stored permanently, only temporarily encrypted

**Contact Exchange Flow**:
1. `contact.exchange.requested` event creates notification to post owner
2. `contact.exchange.approved` event contains encrypted contact info
3. Service decrypts contact details for immediate delivery
4. Contact info discarded after delivery (audit trail remains)

### Testing Approach
- **E2E tests ONLY** in `test/e2e_test.exs` test complete event flows with repository initialization
- Tests cover all adapters with proper repository interaction
- Circuit breaker and bulkhead resilience testing
- Use `ExUnit.Case, async: false` for database tests

### Configuration
- Database schema is in `schema.sql` (single source of truth, no migrations)
- Cloud services configured via environment variables
- Single Dockerfile works for dev, qa, staging, prod environments
- Environment variables for cloud service credentials

## Key Components

**Event Processing**:
- `PostsEventProcessor` - Handles fat post.created, post.matched, post.claimed, post.resolved events
- `UsersEventProcessor` - Handles fat user.registered, organization.staff_added events
- `ContactExchangeEventProcessor` - Handles contact.exchange.* events with encrypted contact info
- `FatEventTranslator` - Translates fat external Kafka events to domain commands (replaces EventTranslator)

**Delivery Channels**:
- `EmailAdapter` - Swoosh-based email delivery (uses UserPreferences.email)
- `SmsAdapter` - Twilio SMS delivery (uses UserPreferences.phone)
- `WhatsAppAdapter` - Twilio WhatsApp Business API delivery (uses UserPreferences.phone)

**Resilience Services**:
- `CircuitBreakerService` - GenServer-based circuit breaker (separate instances for Twilio, Email)
- `BulkheadService` - Resource pool isolation
- `HealthCheckService` - Comprehensive health monitoring

**Data Layer**:
- `NotificationRepository` - Notification persistence
- `UserPreferencesRepository` - User preferences with caching
- Schemas in `infrastructure/schemas/` - Ecto database mappings

## Frontend (Phoenix LiveView)
- Real-time dashboard at `http://localhost:4000`
- Components in `lib/fn_notifications_web/live/`
- Uses Tailwind CSS for styling
- Real-time updates via Phoenix.PubSub

## Health Monitoring
```bash
curl http://localhost:4000/api/health    # Service health status
```

## Important Notes

### Database
- **Uses single `schema.sql` file, not Ecto migrations**
- Schema is idempotent and can be applied multiple times
- Contact information stored in `user_preferences.email` and `user_preferences.phone`

### Caching
- User preferences cached with Cachex (5min TTL)
- Cache invalidation on preference updates

### OTP Supervision
- Circuit breakers restart in closed state on failure
- Resource pools: Email(10), SMS(5), WhatsApp(5) concurrent operations

### Broadway Configuration
- Confluent Cloud Kafka consumer with configurable concurrency and batching
- Events processed via Broadway from Confluent Cloud Kafka topics
- SASL authentication for secure cloud connectivity

### Dockerization
- Single multi-stage Dockerfile supports all environments
- Build argument `MIX_ENV` controls environment (dev, qa, staging, prod)
- Cloud-native with proper signal handling and health checks
- Non-root user for security

### Common Debugging
```bash
make logs                # View application logs
psql "$DATABASE_URL"     # Database access
```

## Documentation

- **Product Vision & Architecture**: External fn-docs repository
- **Domain Objects**: See README.md for direct links to domain entities, aggregates, value objects
- **Development**: This CLAUDE.md file

## Important Code Patterns

### Creating Notifications
Use `NotificationService.send_notification/1` with `SendNotificationCommand` - never create notifications directly.

### Handling User Preferences
Always load user preferences when processing notifications. Contact information comes from preferences, not notification metadata.

### Event Translation
External fat events go through `FatEventTranslator` to convert complete context to domain commands. This maintains the anti-corruption layer while eliminating API calls.

### Error Handling
Use tagged tuples `{:ok, result}` and `{:error, reason}` consistently. Let processes crash for unexpected errors - OTP will handle supervision.

The codebase emphasizes **clean architecture** with strict layer separation, **resilience patterns** for production reliability, and **comprehensive E2E testing**.

---

**Remember**: This is a Lost & Found notification service, not a generic notification system. The business context of reuniting people with lost items drives all architectural and feature decisions.