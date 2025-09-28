defmodule FnNotificationsWeb.Router do
  @moduledoc """
  Phoenix router for notification service REST API endpoints.
  """

  use FnNotificationsWeb, :router

  # Browser pipeline for LiveView frontend
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FnNotificationsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug FnNotificationsWeb.Plugs.CorrelationId
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug FnNotificationsWeb.Plugs.CorrelationId
  end


  # API scope for REST endpoints
  scope "/api", FnNotificationsWeb do
    pipe_through :api

    # Health check endpoint (legacy)
    get "/health", HealthController, :show

    # Notification endpoints (read-only)
    get "/notifications/:id", NotificationsController, :show

    # User notifications endpoint
    get "/users/:user_id/notifications", NotificationsController, :user_notifications

    # User preferences endpoints
    get "/users/:user_id/preferences", UserPreferencesController, :show
    put "/users/:user_id/preferences", UserPreferencesController, :update
    post "/users/:user_id/preferences/reset", UserPreferencesController, :reset
  end


  # LiveView frontend routes
  scope "/", FnNotificationsWeb do
    pipe_through :browser

    # Main dashboard
    live "/", DashboardLive, :index
    # Notifications list
    live "/notifications", NotificationsLive, :index
    # Individual notification details
    live "/notifications/:id", NotificationDetailLive, :show
    # Settings/preferences page
    live "/preferences", UserPreferencesLive, :index
  end

  # Development routes
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
