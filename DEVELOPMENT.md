# fn-notifications Development Guide

**Document Ownership**: This document OWNS all development workflows for the Notifications domain service.

## Prerequisites

- **Elixir** 1.15+ with **OTP** 26+
- **Phoenix** 1.7+
- **Mix** build tool
- **Cloud credentials** configured (see [../fn-docs/CLOUD-SETUP.md](../fn-docs/CLOUD-SETUP.md))

## Environment Setup

```bash
# Clone and navigate
git clone <repository-url>
cd fn-notifications

# Setup environment
cp .env.example .env
# Edit .env with your cloud credentials

# Install dependencies and setup database
make setup

# Start service with cloud services
make up

# Access dashboard
open http://localhost:4000
```

## Development Commands

### Service Operations
```bash
make up                    # Start with cloud services
make down                  # Stop application
make setup                 # Install deps and deploy schema
make logs                  # View application logs
```

### Database Operations
```bash
make deploy-schema-postgres # Deploy schema to cloud PostgreSQL
psql "$DATABASE_URL" -f schema.sql  # Apply schema directly
```

### Testing
```bash
make test                  # Run all E2E tests
make test-integration      # Integration tests with cloud services
make test-all              # Tests with coverage
```

### Code Quality
```bash
mix format                 # Format code
mix credo                  # Static analysis
mix dialyzer               # Type checking
```

## Domain-Driven Design Architecture

### Aggregate Root: Notification
The Notification entity manages delivery lifecycle:

```elixir
defmodule FnNotifications.Domain.Entities.Notification do
  @type t :: %__MODULE__{
    id: String.t(),
    user_id: String.t(),
    notification_type: atom(),
    message: String.t(),
    channels: [atom()],
    status: atom(),
    metadata: map(),
    scheduled_at: DateTime.t(),
    delivered_at: DateTime.t() | nil,
    created_at: DateTime.t()
  }

  defstruct [:id, :user_id, :notification_type, :message, :channels,
             :status, :metadata, :scheduled_at, :delivered_at, :created_at]

  # Business rules enforced
  def create(user_id, type, message, channels) when length(channels) > 0 do
    %__MODULE__{
      id: UUID.uuid4(),
      user_id: user_id,
      notification_type: type,
      message: message,
      channels: channels,
      status: :pending,
      metadata: %{},
      scheduled_at: DateTime.utc_now(),
      created_at: DateTime.utc_now()
    }
  end
end
```

### User Preferences Entity
Contact information is stored separately from notifications:

```elixir
defmodule FnNotifications.Domain.Entities.UserPreferences do
  @type t :: %__MODULE__{
    user_id: String.t(),
    email: String.t() | nil,
    phone: String.t() | nil,
    primary_channel: atom(),
    enabled_channels: [atom()],
    quiet_hours: map(),
    language: String.t()
  }

  # Contact info rules
  def update_contact_info(prefs, email, phone) do
    %{prefs | email: email, phone: phone}
    |> validate_contact_channels()
  end
end
```

### Repository Pattern
```elixir
# Domain behavior (repository interface)
defmodule FnNotifications.Domain.Repositories.NotificationRepositoryBehavior do
  @callback create(notification :: Notification.t()) :: {:ok, Notification.t()} | {:error, term()}
  @callback find_by_user_id(user_id :: String.t()) :: {:ok, [Notification.t()]} | {:error, term()}
  @callback update_status(id :: String.t(), status :: atom()) :: {:ok, Notification.t()} | {:error, term()}
end

# Infrastructure implementation
defmodule FnNotifications.Infrastructure.Repositories.NotificationRepository do
  @behaviour FnNotifications.Domain.Repositories.NotificationRepositoryBehavior

  def create(notification) do
    # Database persistence logic
  end
end
```

## Event-Driven Architecture

### Broadway Event Processing
The service consumes events from Kafka using Broadway:

```elixir
defmodule FnNotifications.Application.EventHandlers.PostsEventProcessor do
  use Broadway

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayKafka.Producer, kafka_config()},
        stages: 1
      ],
      processors: [
        default: [stages: 10, max_demand: 5]
      ],
      batchers: [
        default: [batch_size: 20, batch_timeout: 1000]
      ]
    )
  end

  def handle_message(_processor, message, _context) do
    event = Jason.decode!(message.data)

    case EventTranslator.translate(event) do
      {:ok, command} ->
        NotificationService.send_notification(command)
        message
      {:error, reason} ->
        Logger.error("Failed to translate event: #{reason}")
        Broadway.Message.failed(message, reason)
    end
  end
end
```

### Anti-Corruption Layer
```elixir
defmodule FnNotifications.Application.AntiCorruption.EventTranslator do
  # Protects domain from external event schemas
  def translate(%{"type" => "post.created"} = external_event) do
    {:ok, %SendNotificationCommand{
      user_id: external_event["user_id"],
      notification_type: :post_confirmation,
      metadata: %{
        post_id: external_event["post_id"],
        location: external_event["location"],
        title: external_event["title"]
      },
      channels: [:email]  # Default for confirmations
    }}
  end

  def translate(%{"type" => "post.claimed"} = external_event) do
    {:ok, %SendNotificationCommand{
      user_id: external_event["user_id"],
      notification_type: :urgent_claim,
      metadata: %{
        post_id: external_event["post_id"],
        claimer_contact: external_event["claimer_contact"]
      },
      channels: [:sms, :email]  # Urgent notifications
    }}
  end
end
```

## Multi-Channel Delivery

### Delivery Adapters
```elixir
# Email delivery via Swoosh
defmodule FnNotifications.Infrastructure.Adapters.EmailAdapter do
  def deliver(notification, user_preferences) do
    email = Swoosh.Email.new()
    |> to({user_preferences.name, user_preferences.email})
    |> from({"Findly Now", "notifications@findly.com"})
    |> subject(notification_subject(notification))
    |> text_body(notification.message)
    |> html_body(render_template(notification))

    case Swoosh.Mailer.deliver(email) do
      {:ok, _} -> {:ok, :delivered}
      {:error, reason} -> {:error, reason}
    end
  end
end

# SMS delivery via Twilio
defmodule FnNotifications.Infrastructure.Adapters.SmsAdapter do
  def deliver(notification, user_preferences) do
    case ExTwilio.Message.create(
      from: Application.get_env(:ex_twilio, :phone_number),
      to: user_preferences.phone,
      body: notification.message
    ) do
      {:ok, _message} -> {:ok, :delivered}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Channel Routing Logic
```elixir
defmodule FnNotifications.Application.Services.ChannelRouter do
  # Smart channel selection based on notification type and user preferences
  def select_channels(:post_confirmation, preferences) do
    [preferences.primary_channel]
  end

  def select_channels(:urgent_claim, preferences) do
    [:sms, :email]  # Always multi-channel for urgent
  end

  def select_channels(:match_detected, preferences) do
    if :sms in preferences.enabled_channels do
      [:sms, :email]
    else
      [:email]
    end
  end
end
```

## Resilience Patterns

### Circuit Breaker Implementation
```elixir
defmodule FnNotifications.Domain.Services.CircuitBreakerService do
  use GenServer

  @initial_state %{
    state: :closed,
    failure_count: 0,
    success_count: 0,
    last_failure_time: nil
  }

  def call(service_name, function) do
    case get_state(service_name) do
      :closed -> execute_and_monitor(service_name, function)
      :open -> {:error, :circuit_open}
      :half_open -> execute_with_test(service_name, function)
    end
  end

  defp execute_and_monitor(service_name, function) do
    case function.() do
      {:ok, result} ->
        record_success(service_name)
        {:ok, result}
      {:error, reason} ->
        record_failure(service_name)
        {:error, reason}
    end
  end
end
```

### Bulkhead Resource Isolation
```elixir
defmodule FnNotifications.Domain.Services.BulkheadService do
  use GenServer

  # Separate resource pools prevent cascade failures
  @pools %{
    email: %{max_concurrency: 10, timeout: 30_000},
    sms: %{max_concurrency: 5, timeout: 15_000},
    whatsapp: %{max_concurrency: 5, timeout: 15_000}
  }

  def execute(channel, function) do
    pool = Map.get(@pools, channel)

    case acquire_slot(channel, pool) do
      {:ok, slot} ->
        try do
          function.()
        after
          release_slot(channel, slot)
        end
      {:error, :pool_exhausted} ->
        {:error, :too_many_requests}
    end
  end
end
```

## Database Schema

### Single schema.sql (No Migrations)
```sql
-- notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    channels JSONB NOT NULL DEFAULT '[]',
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    metadata JSONB DEFAULT '{}',
    scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL,
    delivered_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- user_preferences table (CRITICAL: Contact info stored here)
CREATE TABLE IF NOT EXISTS user_preferences (
    user_id UUID PRIMARY KEY,
    email VARCHAR(255),
    phone VARCHAR(20),
    primary_channel VARCHAR(20) NOT NULL DEFAULT 'email',
    enabled_channels JSONB NOT NULL DEFAULT '["email"]',
    quiet_hours JSONB DEFAULT '{}',
    language VARCHAR(10) NOT NULL DEFAULT 'en',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_status ON notifications(status);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(notification_type);
```

## Testing Guidelines

### E2E Test Structure
```elixir
defmodule FnNotifications.E2ETest do
  use ExUnit.Case, async: false

  setup do
    # Initialize repositories with real adapters
    {:ok, _} = start_supervised({NotificationRepository, []})
    {:ok, _} = start_supervised({UserPreferencesRepository, []})

    # Setup test data
    user_id = UUID.uuid4()
    {:ok, _} = UserPreferencesRepository.create(%UserPreferences{
      user_id: user_id,
      email: "test@example.com",
      phone: "+1234567890",
      primary_channel: :email,
      enabled_channels: [:email, :sms]
    })

    %{user_id: user_id}
  end

  test "complete notification workflow", %{user_id: user_id} do
    # Test end-to-end notification delivery
    command = %SendNotificationCommand{
      user_id: user_id,
      notification_type: :post_confirmation,
      message: "Your post has been created successfully.",
      channels: [:email]
    }

    {:ok, notification} = NotificationService.send_notification(command)

    assert notification.status == :delivered
    assert notification.user_id == user_id
    assert :email in notification.channels

    # Verify notification was persisted
    {:ok, notifications} = NotificationRepository.find_by_user_id(user_id)
    assert length(notifications) == 1
  end
end
```

## Phoenix LiveView Dashboard

### Real-time Monitoring
```elixir
defmodule FnNotificationsWeb.DashboardLive do
  use FnNotificationsWeb, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(FnNotifications.PubSub, "notifications")
    end

    notifications = NotificationService.get_recent_notifications()
    stats = NotificationService.get_delivery_stats()

    {:ok, assign(socket, notifications: notifications, stats: stats)}
  end

  def handle_info({:notification_sent, notification}, socket) do
    notifications = [notification | socket.assigns.notifications]
    |> Enum.take(50)  # Keep latest 50

    {:noreply, assign(socket, notifications: notifications)}
  end

  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <div class="stats-grid">
        <div class="stat-card">
          <h3>Delivered Today</h3>
          <p><%= @stats.delivered_today %></p>
        </div>
        <div class="stat-card">
          <h3>Failed Deliveries</h3>
          <p><%= @stats.failed_today %></p>
        </div>
      </div>

      <div class="notifications-list">
        <%= for notification <- @notifications do %>
          <div class="notification-item">
            <span class="status"><%= notification.status %></span>
            <span class="type"><%= notification.notification_type %></span>
            <span class="message"><%= notification.message %></span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
```

## Performance Optimization

### User Preferences Caching
```elixir
defmodule FnNotifications.Infrastructure.Repositories.CachedUserPreferencesRepository do
  @cache_ttl :timer.minutes(5)

  def find_by_user_id(user_id) do
    case Cachex.get(:user_preferences_cache, user_id) do
      {:ok, nil} ->
        case UserPreferencesRepository.find_by_user_id(user_id) do
          {:ok, preferences} ->
            Cachex.put(:user_preferences_cache, user_id, preferences, ttl: @cache_ttl)
            {:ok, preferences}
          error -> error
        end
      {:ok, preferences} ->
        {:ok, preferences}
    end
  end

  def update(preferences) do
    case UserPreferencesRepository.update(preferences) do
      {:ok, updated_preferences} ->
        # Invalidate cache on update
        Cachex.del(:user_preferences_cache, preferences.user_id)
        {:ok, updated_preferences}
      error -> error
    end
  end
end
```

---

*For architecture and cross-service standards, see [../fn-docs/](../fn-docs/)*