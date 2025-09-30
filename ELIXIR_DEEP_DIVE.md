# 📚 Elixir Deep Dive: fn-notifications Repository

## Table of Contents

1. [Introduction](#introduction)
2. [Core Elixir Concepts](#core-elixir-concepts)
3. [Module and Function Syntax](#module-and-function-syntax)
4. [Data Types and Pattern Matching](#data-types-and-pattern-matching)
5. [OTP Patterns](#otp-patterns)
6. [Phoenix Framework](#phoenix-framework)
7. [LiveView Patterns](#liveview-patterns)
8. [Broadway Event Processing](#broadway-event-processing)
9. [Domain-Driven Design](#domain-driven-design)
10. [Error Handling](#error-handling)
11. [Testing Patterns](#testing-patterns)
12. [Real Code Examples](#real-code-examples)

---

## Introduction

This document provides a comprehensive guide to understanding Elixir syntax and patterns as used in the `fn-notifications` microservice. Every concept is explained with actual code from this repository.

### What is Elixir?

Elixir is a functional, concurrent language that runs on the Erlang VM (BEAM). Key characteristics:
- **Functional**: Immutable data, function composition
- **Concurrent**: Millions of lightweight processes
- **Fault-tolerant**: "Let it crash" philosophy
- **Distributed**: Built for distributed systems

---

## Core Elixir Concepts

### 1. Everything is an Expression

In Elixir, everything returns a value:

```elixir
# From notification.ex:64-77
notification = %__MODULE__{
  id: id,
  user_id: user_id,
  channel: channel,
  title: title,
  body: body,
  metadata: attrs[:metadata] || %{},
  scheduled_at: attrs[:scheduled_at],
  max_retries: attrs[:max_retries] || 3,
  inserted_at: now,
  updated_at: now
}

{:ok, notification}  # This is the return value
```

### 2. Immutability

Data never changes; operations create new data:

```elixir
# From notification.ex:86
{:ok, %{notification | status: :sent, sent_at: DateTime.utc_now()}}
# Creates a NEW struct with updated fields, original unchanged
```

### 3. Pattern Matching

The `=` operator is actually a pattern match:

```elixir
{:ok, notification} = Notification.new(attrs)
# Matches if left pattern fits right value
# Extracts notification if successful
```

---

## Module and Function Syntax

### Module Definition

```elixir
defmodule FnNotifications.Domain.Entities.Notification do
  @moduledoc """
  Documentation for the entire module
  """

  # Module attributes (compile-time constants)
  @enforce_keys [:id, :user_id, :channel]

  # Type definitions
  @type t :: %__MODULE__{
    id: String.t(),
    user_id: String.t(),
    # ... more fields
  }

  # Struct definition
  defstruct [:id, :user_id, :channel, status: :pending]
end
```

### Function Definitions

```elixir
# Public function with documentation and type spec
@doc """
Creates a new notification entity.
"""
@spec new(map()) :: {:ok, t()} | {:error, String.t()}
def new(%{} = attrs) do
  # Function body
end

# Private function (only accessible within module)
defp validate_id(nil), do: {:ok, UUID.uuid4()}
defp validate_id(id) when is_binary(id), do: {:ok, id}
defp validate_id(_), do: {:error, "Invalid ID"}
```

### Key Syntax Elements:

1. **`defmodule`** - Defines a module
2. **`@moduledoc`** - Module documentation
3. **`@doc`** - Function documentation
4. **`@spec`** - Type specification
5. **`def`** - Public function
6. **`defp`** - Private function
7. **`do...end`** - Block syntax
8. **`,` do:** - Single line syntax

### Function Clauses and Guards

```elixir
# Multiple function clauses with pattern matching
defp validate_id(nil), do: {:ok, UUID.uuid4()}
defp validate_id(id) when is_binary(id) and byte_size(id) > 0, do: {:ok, id}
defp validate_id(_), do: {:error, "Invalid ID"}

# Guards use 'when' keyword
def increment_retry(notification) when retry_count < max_retries do
  # ...
end
```

---

## Data Types and Pattern Matching

### Atoms

Atoms are constants whose value is their own name:

```elixir
:ok        # Success atom
:error     # Error atom
:pending   # Status atom
:email     # Channel type
```

### Tuples

Fixed-size containers, often used for return values:

```elixir
{:ok, notification}           # Success tuple
{:error, "Invalid ID"}        # Error tuple
{:reply, result, new_state}   # GenServer reply
```

### Maps

Key-value data structures:

```elixir
# Basic map
%{
  "user_id" => "123",
  "channel" => "email"
}

# Atom keys (more common in internal code)
%{
  user_id: "123",
  channel: :email
}
```

### Structs

Maps with predefined keys and default values:

```elixir
# Define struct in module
defstruct [
  :id,
  :user_id,
  status: :pending,  # With default value
  retry_count: 0
]

# Create struct instance
%Notification{
  id: "123",
  user_id: "456",
  status: :sent
}

# Update struct (creates new one)
%{notification | status: :delivered}
```

### Pattern Matching Examples

```elixir
# Match and destructure in function head
def mark_as_sent(%__MODULE__{status: current_status} = notification) do
  # notification is bound to entire struct
  # current_status is bound to the status field
end

# Match on different patterns
case decode_message(message) do
  {:ok, event} ->
    # Handle success
  {:error, reason} ->
    # Handle error
end

# Match in with statement
with {:ok, id} <- validate_id(attrs[:id]),
     {:ok, user_id} <- validate_user_id(attrs[:user_id]),
     {:ok, channel} <- validate_channel(attrs[:channel]) do
  # All matched successfully
else
  {:error, reason} -> {:error, reason}
end
```

---

## OTP Patterns

### GenServer (Generic Server)

GenServer is the fundamental OTP behavior for stateful processes:

```elixir
defmodule FnNotifications.Domain.Services.CircuitBreakerService do
  use GenServer

  # Client API (runs in caller process)
  def start_link(opts) do
    service_name = Keyword.fetch!(opts, :service_name)
    GenServer.start_link(__MODULE__, @initial_state, name: service_name)
  end

  def call(service_name, fun) do
    GenServer.call(service_name, {:call, fun})
  end

  # Server Callbacks (run in GenServer process)
  @impl true
  def init(state) do
    {:ok, state}  # Returns {:ok, initial_state}
  end

  @impl true
  def handle_call({:call, fun}, _from, state) do
    # Process synchronous call
    result = execute_function(fun)
    new_state = update_state(state, result)
    {:reply, result, new_state}
    # {:reply, return_value, new_state}
  end

  @impl true
  def handle_cast(msg, state) do
    # Process async message
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    # Handle other messages
    {:noreply, state}
  end
end
```

### Key GenServer Concepts:

1. **Client/Server separation** - API functions vs callbacks
2. **Synchronous calls** - `GenServer.call` waits for reply
3. **Asynchronous casts** - `GenServer.cast` doesn't wait
4. **State management** - State persists between calls
5. **Process naming** - Can register process with atom name

### Application Supervisor

The application starts a supervision tree:

```elixir
defmodule FnNotifications.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Each child is a worker or supervisor
      FnNotifications.Repo,
      {Phoenix.PubSub, name: FnNotifications.PubSub},
      {Cachex, name: :user_preferences_cache},
      {Oban, Application.fetch_env!(:fn_notifications, Oban)},
      FnNotificationsWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: FnNotifications.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Supervision Strategies:

- **`:one_for_one`** - Restart only failed child
- **`:one_for_all`** - Restart all children if one fails
- **`:rest_for_one`** - Restart failed child and those started after it

---

## Phoenix Framework

### Controllers

Handle HTTP requests and responses:

```elixir
defmodule FnNotificationsWeb.NotificationsController do
  use FnNotificationsWeb, :controller

  # Action function matches route
  def create(conn, %{"notification" => params}) do
    case NotificationService.send_notification(params) do
      {:ok, notification} ->
        conn
        |> put_status(:created)
        |> json(%{data: notification})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end
end
```

### Plugs (Middleware)

```elixir
defmodule FnNotificationsWeb.Plugs.CorrelationId do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    correlation_id = get_req_header(conn, "x-correlation-id")
                    |> List.first()
                    |> (&(&1 || UUID.uuid4())).()

    Logger.metadata(correlation_id: correlation_id)
    put_resp_header(conn, "x-correlation-id", correlation_id)
  end
end
```

### Router

Defines application routes:

```elixir
defmodule FnNotificationsWeb.Router do
  use FnNotificationsWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug FnNotificationsWeb.Plugs.CorrelationId
  end

  scope "/api", FnNotificationsWeb do
    pipe_through :api

    resources "/notifications", NotificationsController, only: [:create, :show]
    get "/health", HealthController, :check
  end
end
```

---

## LiveView Patterns

LiveView enables real-time features without JavaScript:

```elixir
defmodule FnNotificationsWeb.DashboardLive do
  use FnNotificationsWeb, :live_view

  # Mount: Initialize socket state
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time updates
      Phoenix.PubSub.subscribe(FnNotifications.PubSub, "domain_events")
    end

    socket = assign(socket,
      notifications: [],
      stats: load_stats()
    )

    {:ok, socket}
  end

  # Handle real-time events
  def handle_info({:notification_created, notification}, socket) do
    {:noreply,
     socket
     |> update(:notifications, fn list -> [notification | list] end)
     |> update(:stats, fn stats -> increment_stats(stats) end)
    }
  end

  # Handle user interactions
  def handle_event("filter", %{"channel" => channel}, socket) do
    filtered = filter_notifications(socket.assigns.notifications, channel)
    {:noreply, assign(socket, filtered_notifications: filtered)}
  end

  # Render function with HEEx template
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <h1><%= @page_title %></h1>

      <div :for={notification <- @notifications} class="notification">
        <span><%= notification.title %></span>
        <span class={status_class(notification.status)}>
          <%= notification.status %>
        </span>
      </div>

      <button phx-click="refresh">Refresh</button>
    </div>
    """
  end
end
```

### LiveView Lifecycle:

1. **Mount** - Initialize state
2. **Render** - Generate HTML
3. **Handle events** - Process user actions
4. **Handle info** - Process server messages
5. **Update & Render** - Re-render on state change

---

## Broadway Event Processing

Broadway provides concurrent, multi-stage data processing:

```elixir
defmodule FnNotifications.Application.EventHandlers.PostsEventProcessor do
  use Broadway

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayKafka.Producer,
          hosts: kafka_hosts(),
          group_id: "fn_notifications_posts",
          topics: ["posts.events"],
          client_config: kafka_config()
        }
      ],
      processors: [
        default: [concurrency: 10]
      ],
      batchers: [
        default: [
          batch_size: 50,
          batch_timeout: 1000
        ]
      ]
    )
  end

  @impl Broadway
  def handle_message(:default, message, _context) do
    # Process individual message
    case decode_and_translate(message.data) do
      {:ok, commands} ->
        %{message | data: commands}
      {:error, reason} ->
        Broadway.Message.failed(message, reason)
    end
  end

  @impl Broadway
  def handle_batch(:default, messages, _batch_info, _context) do
    # Process batch of messages
    Enum.each(messages, &process_commands(&1.data))
    messages  # Return processed messages
  end
end
```

### Broadway Pipeline:

1. **Producer** - Pulls messages from source (Kafka)
2. **Processor** - Transforms messages concurrently
3. **Batcher** - Groups messages for batch processing
4. **Consumer** - Final processing stage

---

## Domain-Driven Design

### Entities with Business Logic

```elixir
defmodule FnNotifications.Domain.Entities.Notification do
  @enforce_keys [:id, :user_id, :channel]
  defstruct [:id, :user_id, :channel, :status, :title, :body]

  # Business rule: Status transitions
  def mark_as_sent(%__MODULE__{status: current} = notification) do
    if valid_transition?(current, :sent) do
      {:ok, %{notification | status: :sent}}
    else
      {:error, "Invalid transition"}
    end
  end

  # Encapsulated validation
  defp valid_transition?(:pending, :sent), do: true
  defp valid_transition?(:sent, :delivered), do: true
  defp valid_transition?(_, _), do: false
end
```

### Repository Pattern with Behaviors

```elixir
# Define contract (behavior)
defmodule FnNotifications.Domain.Repositories.NotificationRepositoryBehavior do
  @callback save(Notification.t()) :: {:ok, Notification.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, Notification.t()} | {:error, :not_found}
  @callback list_by_user(String.t()) :: [Notification.t()]
end

# Implement repository
defmodule FnNotifications.Infrastructure.Repositories.NotificationRepository do
  @behaviour FnNotifications.Domain.Repositories.NotificationRepositoryBehavior

  alias FnNotifications.Repo
  alias FnNotifications.Infrastructure.Schemas.NotificationSchema

  @impl true
  def save(notification) do
    notification
    |> to_schema()
    |> Repo.insert_or_update()
    |> case do
      {:ok, schema} -> {:ok, to_entity(schema)}
      error -> error
    end
  end

  @impl true
  def get(id) do
    case Repo.get(NotificationSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, to_entity(schema)}
    end
  end
end
```

### Value Objects

```elixir
defmodule FnNotifications.Domain.ValueObjects.NotificationChannel do
  @valid_channels [:email, :sms, :whatsapp, :push]

  @type t :: :email | :sms | :whatsapp | :push

  @spec valid?(any()) :: boolean()
  def valid?(channel) when channel in @valid_channels, do: true
  def valid?(_), do: false

  @spec to_string(t()) :: String.t()
  def to_string(:email), do: "Email"
  def to_string(:sms), do: "SMS"
  def to_string(:whatsapp), do: "WhatsApp"
  def to_string(:push), do: "Push Notification"
end
```

---

## Error Handling

### Tagged Tuples Pattern

The standard Elixir pattern for error handling:

```elixir
# Function returns tagged tuple
def create_notification(params) do
  case validate(params) do
    :ok ->
      {:ok, build_notification(params)}
    {:error, reason} ->
      {:error, reason}
  end
end

# Caller handles both cases
case create_notification(params) do
  {:ok, notification} ->
    send_notification(notification)
  {:error, reason} ->
    Logger.error("Failed: #{reason}")
    {:error, reason}
end
```

### With Statement

Chain operations that might fail:

```elixir
def process_notification(attrs) do
  with {:ok, validated} <- validate_attrs(attrs),
       {:ok, user} <- get_user(validated.user_id),
       {:ok, preferences} <- get_preferences(user.id),
       {:ok, notification} <- build_notification(validated, preferences),
       {:ok, sent} <- send_notification(notification) do
    {:ok, sent}
  else
    {:error, :user_not_found} ->
      {:error, "User does not exist"}
    {:error, :preferences_not_found} ->
      {:error, "User has no notification preferences"}
    {:error, reason} ->
      {:error, reason}
  end
end
```

### Let It Crash Philosophy

```elixir
# Don't defensive program - let supervisor restart
def process_message(message) do
  # This will crash if message.data is nil
  # That's OK - supervisor will restart
  decoded = Jason.decode!(message.data)
  process_decoded(decoded)
end

# Only catch expected errors
def safe_process(message) do
  try do
    process_message(message)
  rescue
    Jason.DecodeError ->
      {:error, "Invalid JSON"}
    # Don't catch everything!
  end
end
```

---

## Testing Patterns

### ExUnit Test Structure

```elixir
defmodule FnNotifications.NotificationServiceTest do
  use ExUnit.Case, async: false  # async: false for database tests

  alias FnNotifications.Application.Services.NotificationService

  describe "send_notification/1" do
    setup do
      # Setup runs before each test
      user = insert(:user)
      {:ok, user: user}
    end

    test "sends email notification successfully", %{user: user} do
      params = %{
        user_id: user.id,
        channel: :email,
        title: "Test",
        body: "Test message"
      }

      assert {:ok, notification} = NotificationService.send_notification(params)
      assert notification.status == :sent
      assert notification.user_id == user.id
    end

    test "returns error for invalid channel" do
      params = %{channel: :invalid}

      assert {:error, reason} = NotificationService.send_notification(params)
      assert reason =~ "Invalid channel"
    end
  end
end
```

### E2E Testing Approach

```elixir
defmodule FnNotifications.E2ETest do
  use ExUnit.Case

  setup_all do
    # Initialize real repositories and services
    start_supervised!(FnNotifications.Repo)
    start_supervised!(FnNotifications.Application.EventHandlers.PostsEventProcessor)
    :ok
  end

  test "complete notification flow from event to delivery" do
    # Create Kafka event
    event = build_post_created_event()

    # Send to Broadway processor
    Broadway.test_message(PostsEventProcessor, event)

    # Wait for async processing
    :timer.sleep(100)

    # Verify notification was created and sent
    assert [notification] = Repo.all(Notification)
    assert notification.status == :delivered
  end
end
```

---

## Real Code Examples

### 1. Complete Module Analysis: Notification Entity

Let's analyze the complete notification entity line by line:

```elixir
# Line 1: Module definition with nested namespacing
defmodule FnNotifications.Domain.Entities.Notification do

  # Lines 2-4: Module documentation (appears in generated docs)
  @moduledoc """
  Notification entity for multi-channel delivery.
  """

  # Lines 6-9: Alias other modules for shorter names
  alias FnNotifications.Domain.ValueObjects.{
    NotificationChannel,    # Can now use NotificationChannel instead of full path
    NotificationStatus
  }
  alias UUID  # External dependency

  # Lines 12-29: Type definition for documentation and dialyzer
  @type t :: %__MODULE__{      # t() is conventional for "this module's type"
          id: String.t(),       # Built-in type
          user_id: String.t(),
          channel: NotificationChannel.t(),  # Custom type from value object
          status: NotificationStatus.t(),
          title: String.t(),
          body: String.t(),
          metadata: map(),      # Any map
          scheduled_at: DateTime.t() | nil,  # Union type: DateTime OR nil
          sent_at: DateTime.t() | nil,
          delivered_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil,
          failure_reason: String.t() | nil,
          retry_count: non_neg_integer(),  # 0 or positive integer
          max_retries: non_neg_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  # Line 31: Required fields - struct creation fails without these
  @enforce_keys [:id, :user_id, :channel, :title, :body, :inserted_at]

  # Lines 32-49: Struct definition with defaults
  defstruct [
    :id,           # No default value (nil)
    :user_id,
    :channel,
    :title,
    :body,
    :metadata,
    :scheduled_at,
    :sent_at,
    :delivered_at,
    :failed_at,
    :failure_reason,
    :inserted_at,
    :updated_at,
    status: NotificationStatus.initial(),  # Default from function call
    retry_count: 0,                        # Default value 0
    max_retries: 3                         # Default value 3
  ]
```

### 2. Pattern Matching in Action

```elixir
# From circuit_breaker_service.ex
def handle_call({:call, fun}, _from, state) do
  # Pattern match on tuple in first argument
  # _from means we don't care about the sender
  # state is our GenServer's current state

  case should_allow_call?(state) do
    true ->
      # Execute and track
      result = execute_with_tracking(fun, state)
      new_state = update_state_from_result(state, result)
      {:reply, result, new_state}  # Return tuple: {:reply, response, new_state}

    false ->
      # Circuit breaker is open
      {:reply, {:error, "Circuit breaker open"}, state}
  end
end

# Multiple function clauses with pattern matching
defp should_allow_call?(%{state: :closed}), do: true
defp should_allow_call?(%{state: :half_open}), do: true
defp should_allow_call?(%{state: :open} = state) do
  # More complex logic for open state
  check_recovery_timeout(state)
end
```

### 3. Broadway Message Processing

```elixir
# From posts_event_processor.ex
@impl Broadway
def handle_message(:default, message, _context) do
  # Extract correlation ID for distributed tracing
  correlation_id = extract_correlation_id(message.metadata)
  Logger.metadata(correlation_id: correlation_id)

  # Decode message - note the pipeline
  case decode_message(message) do
    {:ok, event} ->
      # Transform external event to internal commands
      case FatEventTranslator.translate_post_event(event) do
        {:ok, notification_commands} ->
          # Update message data with commands
          %{message | data: notification_commands}

        {:error, reason} ->
          Logger.warning("Failed to translate: #{reason}")
          Broadway.Message.failed(message, reason)
      end

    {:error, reason} ->
      Logger.error("Failed to decode: #{reason}")
      Broadway.Message.failed(message, reason)
  end
end
```

### 4. LiveView Real-time Updates

```elixir
# From dashboard_live.ex
def mount(_params, _session, socket) do
  # Check if WebSocket is connected (not initial HTTP request)
  if connected?(socket) do
    # Subscribe to PubSub topic for real-time updates
    Phoenix.PubSub.subscribe(FnNotifications.PubSub, @events_topic)
  end

  # Pipeline to build socket state
  socket =
    socket
    |> assign(page_title: "Dashboard")     # Single assignment
    |> load_dashboard_data()               # Function returns updated socket
    |> assign_last_updated()               # Another transform

  {:ok, socket}  # Return success tuple with socket
end

# Handle real-time PubSub messages
def handle_info({:notification_created, notification}, socket) do
  # Update socket assigns (state) and re-render
  {:noreply,
   socket
   |> update_stats_for_new_notification(notification)
   |> add_to_recent_notifications(notification)
   |> assign_last_updated()
  }
end
```

### 5. Pipe Operator Usage

The pipe operator `|>` passes the result of one function as the first argument to the next:

```elixir
# Without pipes (nested, hard to read)
assign_last_updated(
  add_to_recent_notifications(
    update_stats_for_new_notification(socket, notification),
    notification
  )
)

# With pipes (linear, easy to read)
socket
|> update_stats_for_new_notification(notification)
|> add_to_recent_notifications(notification)
|> assign_last_updated()

# Real example from controller
conn
|> put_status(:created)
|> put_resp_header("content-type", "application/json")
|> json(%{data: notification})
```

---

## Common Patterns and Idioms

### 1. Function Composition

```elixir
# Small, composable functions
defp validate_and_send(params) do
  params
  |> validate()
  |> build_notification()
  |> send_notification()
end

defp validate(params), do: {:ok, params}
defp build_notification({:ok, params}), do: {:ok, struct(Notification, params)}
defp build_notification(error), do: error
defp send_notification({:ok, notification}), do: DeliveryService.send(notification)
defp send_notification(error), do: error
```

### 2. Configuration Pattern

```elixir
# Runtime configuration
def kafka_config do
  [
    "bootstrap.servers": System.get_env("KAFKA_BROKERS"),
    "group.id": System.get_env("KAFKA_CONSUMER_GROUP", "default"),
    "sasl.username": System.get_env("KAFKA_USERNAME"),
    "sasl.password": System.get_env("KAFKA_PASSWORD")
  ]
end

# Compile-time configuration
@config Application.compile_env(:fn_notifications, __MODULE__, [])
@retry_count Keyword.get(@config, :retry_count, 3)
```

### 3. Supervisor Child Specs

```elixir
# Different ways to specify children
children = [
  # Module only (uses child_spec/1)
  FnNotifications.Repo,

  # Tuple format {module, args}
  {Phoenix.PubSub, name: FnNotifications.PubSub},

  # With custom ID
  Supervisor.child_spec(
    {CircuitBreakerService, service_name: :email_breaker},
    id: :email_circuit_breaker
  )
]
```

### 4. Message Passing

```elixir
# Send message to named process
send(:notification_processor, {:process, notification})

# GenServer call (synchronous)
GenServer.call(:notification_service, {:send, notification})

# GenServer cast (asynchronous)
GenServer.cast(:notification_service, {:log, event})

# PubSub broadcast
Phoenix.PubSub.broadcast(
  FnNotifications.PubSub,
  "notifications",
  {:notification_sent, notification}
)
```

---

## Development Workflow

### Mix Tasks

```bash
# Project setup
mix deps.get          # Install dependencies
mix ecto.create       # Create database
mix ecto.migrate      # Run migrations

# Development
mix phx.server        # Start Phoenix server
iex -S mix phx.server # Start with interactive shell

# Testing
mix test              # Run all tests
mix test path/to/test.exs:42  # Run specific test at line 42

# Code quality
mix format            # Format code
mix credo            # Static analysis
mix dialyzer         # Type checking
```

### IEx (Interactive Elixir)

```elixir
# Start IEx session
iex -S mix

# Reload modules
r(FnNotifications.Domain.Entities.Notification)

# Get help
h Enum.map

# Inspect data
i notification

# Debug
require IEx
IEx.pry()  # Breakpoint
```

---

## Performance Patterns

### ETS (Erlang Term Storage) for Caching

```elixir
defmodule Cache do
  use GenServer

  def init(_) do
    # Create ETS table
    :ets.new(:cache_table, [:set, :public, :named_table])
    {:ok, %{}}
  end

  def get(key) do
    case :ets.lookup(:cache_table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  def put(key, value) do
    :ets.insert(:cache_table, {key, value})
    :ok
  end
end
```

### Process Pooling

```elixir
# Using poolboy for connection pooling
children = [
  :poolboy.child_spec(
    :worker_pool,
    [
      size: 10,
      max_overflow: 20
    ],
    []
  )
]

# Use pool
:poolboy.transaction(:worker_pool, fn worker ->
  GenServer.call(worker, {:process, data})
end)
```

---

## Debugging Tips

### 1. IO.inspect for Pipeline Debugging

```elixir
result =
  data
  |> transform_1()
  |> IO.inspect(label: "After transform_1")
  |> transform_2()
  |> IO.inspect(label: "After transform_2")
  |> transform_3()
```

### 2. Pattern Match Debugging

```elixir
case some_function() do
  {:ok, result} ->
    result
  error ->
    IO.inspect(error, label: "Unexpected result")
    raise "Unexpected: #{inspect(error)}"
end
```

### 3. Logger with Metadata

```elixir
Logger.metadata(user_id: user.id, request_id: request_id)
Logger.info("Processing notification",
  channel: notification.channel,
  status: notification.status
)
```

---

## Glossary

| Term | Definition |
|------|------------|
| **Atom** | Constant whose value is its name (`:ok`, `:error`) |
| **BEAM** | Erlang virtual machine that runs Elixir |
| **Behavior** | Interface definition that modules can implement |
| **GenServer** | Generic server for stateful processes |
| **Guard** | Condition in function clause (`when is_binary(id)`) |
| **HEEx** | HTML+EEx template format for Phoenix |
| **LiveView** | Server-rendered real-time web UI |
| **OTP** | Open Telecom Platform - Erlang/Elixir framework |
| **Pattern Match** | Destructuring and matching data structures |
| **PubSub** | Publish-Subscribe messaging pattern |
| **Supervisor** | Process that monitors and restarts other processes |
| **Tagged Tuple** | Tuple with atom as first element (`{:ok, value}`) |

---

## Quick Reference

### Common Return Patterns

```elixir
{:ok, result}           # Success
{:error, reason}        # Failure
{:reply, value, state}  # GenServer reply
{:noreply, state}       # GenServer no reply
{:stop, reason, state}  # GenServer stop
```

### Common Guards

```elixir
is_atom(x)
is_binary(x)
is_boolean(x)
is_function(x)
is_integer(x)
is_list(x)
is_map(x)
is_nil(x)
is_number(x)
is_tuple(x)
```

### Common Operators

```elixir
|>   # Pipe operator
<>   # String concatenation
++   # List concatenation
--   # List difference
=    # Pattern match / assignment
==   # Equality
===  # Strict equality
!=   # Inequality
!==  # Strict inequality
&&   # Boolean AND
||   # Boolean OR
!    # Boolean NOT
```

---

## Conclusion

This deep dive covered the essential Elixir patterns and syntax used in the fn-notifications repository. Key takeaways:

1. **Functional Programming**: Immutability, pattern matching, and function composition are core
2. **Actor Model**: Processes, message passing, and supervision provide fault tolerance
3. **OTP Patterns**: GenServers, Supervisors, and Applications structure the system
4. **Phoenix Framework**: Provides web interface with LiveView for real-time features
5. **Broadway**: Handles high-throughput event processing from Kafka
6. **Domain-Driven Design**: Clean architecture with clear boundaries

The codebase demonstrates professional Elixir development with:
- Strong type specifications
- Comprehensive error handling
- Clear separation of concerns
- Extensive use of OTP patterns
- Real-time features via LiveView
- Scalable event processing

This document serves as both a learning guide and reference for working with the fn-notifications Elixir codebase.