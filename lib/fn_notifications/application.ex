defmodule FnNotifications.Application do
  @moduledoc """
  Main OTP application supervisor for FN Notifications microservice.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core Infrastructure
      FnNotificationsWeb.Telemetry,
      FnNotifications.Repo,
      {DNSCluster, query: Application.get_env(:fn_notifications, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FnNotifications.PubSub},

      # Caching Layer
      Supervisor.child_spec({Cachex, name: :user_preferences_cache, limit: 10_000}, id: :user_preferences_cache),

      # Event Processing Pipeline
      {FnNotifications.Application.EventHandlers.PostsEventProcessor, []},
      {FnNotifications.Application.EventHandlers.UsersEventProcessor, []},
      {FnNotifications.Application.EventHandlers.MatcherEventProcessor, []},

      # Background Job Processors
      {Oban, Application.fetch_env!(:fn_notifications, Oban)},

      # HTTP Clients Pool (Tesla connections)
      {Finch, name: FnNotifications.Finch},

      # Circuit Breakers for External Services
      Supervisor.child_spec({FnNotifications.Domain.Services.CircuitBreakerService, service_name: :twilio_circuit_breaker}, id: :twilio_circuit_breaker),
      Supervisor.child_spec({FnNotifications.Domain.Services.CircuitBreakerService, service_name: :email_circuit_breaker}, id: :email_circuit_breaker),

      # Bulkhead service for resource isolation
      FnNotifications.Domain.Services.BulkheadService,

      # Health check service
      FnNotifications.Infrastructure.Health.HealthCheckService,

      # Scheduled Tasks Supervisor
      {Task.Supervisor, name: FnNotifications.TaskSupervisor},

      # Phoenix Web Endpoint (typically last)
      FnNotificationsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FnNotifications.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FnNotificationsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
