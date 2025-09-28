# FN Notifications Service

> **Enterprise notification microservice for Lost & Found platforms**

Multi-channel notification delivery system enabling rapid reunification of lost items through intelligent, timely notifications.

## 🎯 Domain Vision

This microservice operates within the **Lost & Found ecosystem**, enabling rapid reunification of lost items through intelligent notifications. The system processes lifecycle events (`post.created`, `post.matched`, `post.claimed`, `post.resolved`) and delivers contextual notifications via multiple channels to accelerate the connection between item reporters and finders.

**Core Business Value**: Reduce the time between item loss and recovery through timely, relevant notifications that guide users through the reunification process.

## 🏗️ Domain Objects

Explore the domain model:

- **Entities**: [`Notification`](lib/fn_notifications/domain/entities/notification.ex), [`UserPreferences`](lib/fn_notifications/domain/entities/user_preferences.ex)
- **Aggregates**: [`NotificationAggregate`](lib/fn_notifications/domain/aggregates/notification_aggregate.ex)
- **Value Objects**: [`NotificationChannel`](lib/fn_notifications/domain/value_objects/notification_channel.ex), [`NotificationStatus`](lib/fn_notifications/domain/value_objects/notification_status.ex)
- **Repositories**: [`NotificationRepositoryBehavior`](lib/fn_notifications/domain/repositories/notification_repository_behavior.ex), [`UserPreferencesRepositoryBehavior`](lib/fn_notifications/domain/repositories/user_preferences_repository_behavior.ex)

## 📚 Architecture & Product Vision

For comprehensive documentation on architecture decisions, product vision, and system design:

**📖 [fn-docs Repository](https://github.com/your-org/fn-docs)**

## 🚀 Quick Start

```bash
# Clone and setup
git clone <repository-url>
cd fn-notifications

# One-command setup
make setup

# Start services
make up

# Verify everything works
curl http://localhost:4000/api/health
```

**Dashboard**: http://localhost:4000

## 🛠️ Core Features

- **Multi-channel delivery**: Email, SMS, WhatsApp notifications
- **Event-driven processing**: Real-time Confluent Cloud Kafka event handling via Broadway
- **Enterprise resilience**: Circuit breakers, bulkheads, retry mechanisms
- **User preference management**: Granular notification controls per channel
- **Real-time dashboard**: Phoenix LiveView with live updates

## 📦 Tech Stack

**Elixir/OTP** • **Phoenix** • **Confluent Cloud Kafka** • **Cloud PostgreSQL** • **Google Cloud Storage** • **Docker**

## 🧞 AI Assistant

For AI-assisted development, see **[CLAUDE.md](CLAUDE.md)** - specialized guidance for Claude Code.

## 📄 License

MIT License - see [LICENSE.md](LICENSE.md)