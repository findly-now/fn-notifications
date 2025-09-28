# fn-notifications

**Enterprise notification microservice for Lost & Found platforms**

## Purpose

Multi-channel notification delivery system enabling rapid reunification through intelligent, timely notifications across Email, SMS, and WhatsApp.

**Technology**: Elixir/OTP + Phoenix + Kafka + PostgreSQL + Twilio

## Quick Start

```bash
# 1. Setup environment
cp .env.example .env
# Edit .env with your cloud credentials (see fn-docs/CLOUD-SETUP.md)

# 2. Start service
make setup && make up

# 3. Test
curl http://localhost:4000/api/health
make test
```

**Dashboard**: http://localhost:4000

## Core Features

- **Multi-channel delivery**: Email, SMS, WhatsApp
- **Event-driven**: Real-time Kafka processing via Broadway
- **Enterprise resilience**: Circuit breakers, bulkheads, retry mechanisms
- **User preferences**: Granular notification controls per channel

## Documentation

- **[DEVELOPMENT.md](./DEVELOPMENT.md)** - Complete development guide
- **[../fn-docs/](../fn-docs/)** - Architecture and standards