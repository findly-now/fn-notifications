defmodule FnNotificationsWeb.Endpoint do
  @moduledoc """
  Phoenix HTTP endpoint configuration for the notifications API service.
  """

  use Phoenix.Endpoint, otp_app: :fn_notifications

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_fn_notifications_key",
    signing_salt: "yVL+2aTO",
    same_site: "Lax"
  ]

  # LiveView socket configuration
  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Serve static assets from priv/static (for CSS, JS, images)
  plug Plug.Static,
    at: "/",
    from: :fn_notifications,
    gzip: false,
    only_matching: FnNotificationsWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :fn_notifications
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug FnNotificationsWeb.Router
end
