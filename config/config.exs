# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fn_notifications,
  ecto_repos: [FnNotifications.Repo],
  generators: [timestamp_type: :utc_datetime],
  # DDD Layer Configuration - Repository implementations for dependency injection
  notification_repository: FnNotifications.Infrastructure.Repositories.NotificationRepository,
  preferences_repository: FnNotifications.Infrastructure.Repositories.UserPreferencesRepository,
  delivery_service: FnNotifications.Infrastructure.Adapters.DeliveryService

# Configures the endpoint
config :fn_notifications, FnNotificationsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FnNotificationsWeb.ErrorHTML, json: FnNotificationsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FnNotifications.PubSub,
  live_view: [signing_salt: "wsIp/2fi"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :fn_notifications, FnNotifications.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (JavaScript bundling)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure Tailwind CSS
config :tailwind,
  version: "3.4.0",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :correlation_id, :user_id, :error]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Tesla HTTP Client Configuration
config :tesla, :adapter, Tesla.Adapter.Finch

# Disable Tesla deprecated builder warning
config :tesla, disable_deprecated_builder_warning: true

# Tesla Finch Pool Configuration
config :finch,
  pools: %{
    :default => [size: 25, count: 3],
    "https://api.twilio.com" => [size: 5, count: 1]
  }

# Broadway Kafka Configuration - Will be set at runtime from environment variables

# External Service Configuration
config :fn_notifications,
  # Twilio SMS and WhatsApp Configuration
  twilio_account_sid: System.get_env("TWILIO_ACCOUNT_SID"),
  twilio_auth_token: System.get_env("TWILIO_AUTH_TOKEN"),
  twilio_phone_number: System.get_env("TWILIO_PHONE_NUMBER"),
  twilio_whatsapp_number: System.get_env("TWILIO_WHATSAPP_NUMBER"),

  # Application URLs - must be configured for cloud deployment
  web_base_url: System.get_env("WEB_BASE_URL") ||
    raise("WEB_BASE_URL environment variable is required"),
  sender_email: System.get_env("SENDER_EMAIL", "notifications@fnnotifications.local"),

  # Contact Exchange Security Configuration
  contact_encryption_key: System.get_env("CONTACT_ENCRYPTION_KEY"),
  contact_retention_days: String.to_integer(System.get_env("CONTACT_RETENTION_DAYS", "30")),

  # Feature Flags - defaults to safe test mode unless explicitly disabled
  test_mode: System.get_env("TEST_MODE", "true") == "true",
  log_twilio_requests: System.get_env("LOG_TWILIO_REQUESTS", "false") == "true"



# Datadog StatsD Configuration
config :fn_notifications, FnNotifications.Infrastructure.Adapters.DatadogAdapter,
  host: System.get_env("STATSD_HOST", "localhost"),
  port: String.to_integer(System.get_env("STATSD_PORT", "8125"))

# Oban Configuration
config :fn_notifications, Oban,
  repo: FnNotifications.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [retries: 5]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
