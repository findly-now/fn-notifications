defmodule FnNotificationsWeb.UserPreferencesController do
  @moduledoc """
  REST API controller for user notification preference management.
  """

  use FnNotificationsWeb, :controller

  alias FnNotifications.Application.Services.UserPreferencesService
  alias FnNotifications.Application.Commands.UpdateUserPreferencesCommand

  require Logger

  @doc """
  GET /api/users/:user_id/preferences
  Get user notification preferences
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"user_id" => user_id}) do
    case UserPreferencesService.get_preferences(user_id) do
      {:ok, preferences} ->
        conn
        |> put_status(:ok)
        |> json(%{
          user_id: preferences.user_id,
          global_enabled: preferences.global_enabled,
          timezone: preferences.timezone,
          language: preferences.language,
          channel_preferences: preferences.channel_preferences,
          updated_at: preferences.updated_at
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User preferences not found"})

      {:error, reason} ->
        Logger.error("Failed to get user preferences", user_id: user_id, error: reason)

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal server error"})
    end
  end

  @doc """
  PUT /api/users/:user_id/preferences
  Update user notification preferences
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"user_id" => user_id} = params) do
    command_params = %{
      user_id: user_id,
      global_enabled: Map.get(params, "global_enabled"),
      timezone: Map.get(params, "timezone"),
      language: Map.get(params, "language"),
      channel_preferences: Map.get(params, "channel_preferences", %{})
    }

    case UpdateUserPreferencesCommand.new(command_params) do
      {:ok, command} ->
        case UserPreferencesService.update_preferences(command) do
          {:ok, preferences} ->
            conn
            |> put_status(:ok)
            |> json(%{
              user_id: preferences.user_id,
              global_enabled: preferences.global_enabled,
              timezone: preferences.timezone,
              language: preferences.language,
              channel_preferences: preferences.channel_preferences,
              updated_at: preferences.updated_at
            })

          {:error, reason} ->
            Logger.error("Failed to update user preferences", user_id: user_id, error: reason)

            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to update preferences"})
        end

      {:error, errors} ->
        conn
        |> put_status(:bad_request)
        |> json(%{errors: errors})
    end
  end

  @doc """
  POST /api/users/:user_id/preferences/reset
  Reset user preferences to defaults
  """
  @spec reset(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def reset(conn, %{"user_id" => user_id}) do
    case UserPreferencesService.reset_to_defaults(user_id) do
      {:ok, preferences} ->
        conn
        |> put_status(:ok)
        |> json(%{
          user_id: preferences.user_id,
          global_enabled: preferences.global_enabled,
          timezone: preferences.timezone,
          language: preferences.language,
          channel_preferences: preferences.channel_preferences,
          updated_at: preferences.updated_at
        })

      {:error, reason} ->
        Logger.error("Failed to reset user preferences", user_id: user_id, error: reason)

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to reset preferences"})
    end
  end
end
