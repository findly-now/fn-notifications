import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/fn_notifications start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :fn_notifications, FnNotificationsWeb.Endpoint, server: true
end

# Kafka configuration - Cloud-only (Confluent Cloud)
environment = System.get_env("ENVIRONMENT", "staging")

# Always use cloud Kafka configuration
kafka_brokers = System.get_env("KAFKA_BROKERS") ||
  raise """
  environment variable KAFKA_BROKERS is missing.
  Set it to your Confluent Cloud bootstrap servers.
  Example: KAFKA_BROKERS=pkc-xxxxx.us-east-1.aws.confluent.cloud:9092
  """

kafka_hosts = kafka_brokers
|> String.split(",")
|> Enum.map(fn broker ->
  [host, port] = String.split(broker, ":")
  {host, String.to_integer(port)}
end)

# SASL authentication for Confluent Cloud (required)
kafka_config = [
  sasl: %{
    mechanism: :plain,
    username: System.get_env("KAFKA_API_KEY") ||
      raise("environment variable KAFKA_API_KEY is missing"),
    password: System.get_env("KAFKA_API_SECRET") ||
      raise("environment variable KAFKA_API_SECRET is missing")
  },
  ssl: [verify: :verify_peer]
]

config :fn_notifications, :kafka_hosts, kafka_hosts
config :fn_notifications, :kafka_config, kafka_config

# Kafka topic configuration
config :fn_notifications, :kafka_topics,
  posts_events: System.get_env("KAFKA_POSTS_TOPIC", "posts.events"),
  posts_matching: System.get_env("KAFKA_MATCHER_TOPIC", "posts.matching"),
  users_events: System.get_env("KAFKA_USERS_TOPIC", "users.events")

# Database configuration for development/Docker/test
if database_url = System.get_env("DATABASE_URL") do
  # Set appropriate pool configuration based on environment
  pool_config = case System.get_env("MIX_ENV") do
    "test" -> [pool: Ecto.Adapters.SQL.Sandbox, pool_size: System.schedulers_online() * 2]
    _ -> [pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")]
  end

  config :fn_notifications, FnNotifications.Repo,
    ([url: database_url] ++ pool_config)
end

# Configure notification mode based on environment
# This overrides the default config.exs settings at runtime
config :fn_notifications,
  # Test mode configuration - defaults to true (safe) unless explicitly set to false
  test_mode: System.get_env("TEST_MODE", "true") == "true",
  log_twilio_requests: System.get_env("LOG_TWILIO_REQUESTS", "false") == "true",

  # Application configuration from environment
  web_base_url: System.get_env("WEB_BASE_URL", "http://localhost:4000"),
  sender_email: System.get_env("SENDER_EMAIL", "notifications@fnnotifications.local"),

  # External service configuration
  twilio_account_sid: System.get_env("TWILIO_ACCOUNT_SID"),
  twilio_auth_token: System.get_env("TWILIO_AUTH_TOKEN"),
  twilio_phone_number: System.get_env("TWILIO_PHONE_NUMBER"),
  twilio_whatsapp_number: System.get_env("TWILIO_WHATSAPP_NUMBER")

# Configure Swoosh email adapter based on TEST_MODE
if System.get_env("TEST_MODE", "true") == "false" do
  # Real SMTP configuration when test mode is disabled
  config :fn_notifications, FnNotifications.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("SMTP_HOST", "smtp.gmail.com"),
    port: String.to_integer(System.get_env("SMTP_PORT", "587")),
    username: System.get_env("SMTP_USERNAME"),
    password: System.get_env("SMTP_PASSWORD"),
    tls: :always,
    auth: :always,
    retries: 2

  # Enable Swoosh API client for SMTP
  config :swoosh, :api_client, Swoosh.ApiClient.Finch
else
  # Test mode - keep local adapter (emails go to /dev/mailbox)
  config :fn_notifications, FnNotifications.Mailer, adapter: Swoosh.Adapters.Local
  config :swoosh, :api_client, false
end

# Cloud Storage configuration (optional)
if bucket_name = System.get_env("BUCKET_NAME") do
  config :fn_notifications, :storage,
    bucket: bucket_name,
    bucket_url: System.get_env("BUCKET_URL"),
    project_id: System.get_env("STORAGE_PROJECT_ID"),
    # Support both file path and direct JSON content
    credentials: case System.get_env("STORAGE_SERVICE_ACCOUNT_JSON_CONTENT") do
      nil ->
        # Use file path
        System.get_env("STORAGE_SERVICE_ACCOUNT_JSON")
      json_content ->
        # Use direct JSON content (useful for deployment environments)
        Jason.decode!(json_content)
    end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :fn_notifications, FnNotifications.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :fn_notifications, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :fn_notifications, FnNotificationsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :fn_notifications, FnNotificationsWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :fn_notifications, FnNotificationsWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :fn_notifications, FnNotifications.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  # Production Configuration for New Services
  config :fn_notifications, FnNotifications.Infrastructure.Adapters.DatadogAdapter,
    host: System.get_env("STATSD_HOST", "127.0.0.1"),
    port: String.to_integer(System.get_env("STATSD_PORT", "8125"))

  config :fn_notifications, Oban, queues: [retries: String.to_integer(System.get_env("OBAN_RETRY_WORKERS", "10"))]

  # Production External service configuration - override runtime config
  config :fn_notifications,
    twilio_account_sid: System.get_env("TWILIO_ACCOUNT_SID"),
    twilio_auth_token: System.get_env("TWILIO_AUTH_TOKEN"),
    twilio_phone_number: System.get_env("TWILIO_PHONE_NUMBER"),
    twilio_whatsapp_number: System.get_env("TWILIO_WHATSAPP_NUMBER"),

    # Production always uses real notifications (no test mode)
    test_mode: false,
    log_twilio_requests: false
end
