import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Configure your cloud database for testing
# Use TEST_DATABASE_URL environment variable or override with test-specific cloud DB
if database_url = System.get_env("TEST_DATABASE_URL") || System.get_env("DATABASE_URL") do
  config :fn_notifications, FnNotifications.Repo,
    url: database_url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
else
  raise """
  Test database not configured!
  Set TEST_DATABASE_URL or DATABASE_URL environment variable.
  Example: TEST_DATABASE_URL=postgresql://postgres:password@host:5432/fn_notifications_test
  """
end

# Override repository implementations for testing
config :fn_notifications,
  notification_repository: FnNotifications.Infrastructure.Repositories.NotificationRepository,
  preferences_repository: FnNotifications.Infrastructure.Repositories.UserPreferencesRepository,
  delivery_service: FnNotifications.Infrastructure.Adapters.DeliveryService

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fn_notifications, FnNotificationsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tv/mugh/YdJ7Urwez+ceZGwRwtYOOGs2JnZtbbXVjajZeqNu6JmEkZK87POCQN9P",
  server: false

# In test we don't send emails
config :fn_notifications, FnNotifications.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
