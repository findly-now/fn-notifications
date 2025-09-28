defmodule FnNotificationsWeb.NotificationsController do
  use FnNotificationsWeb, :controller

  alias FnNotifications.Application.Services.NotificationService
  alias FnNotificationsWeb.{ApiErrorHandler, RequestValidator}

  @moduledoc """
  REST API controller for notification operations.
  Provides endpoints for reading and managing notifications.
  Notifications are created automatically from Kafka events, not via REST API.
  """

  @doc """
  GET /api/notifications/:id - Get a single notification
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with :ok <- RequestValidator.validate_uuid(id),
         {:ok, notification} <- NotificationService.get_notification(id) do
      ApiErrorHandler.success_response(conn, :ok, notification)
    else
      {:error, "Invalid UUID format"} ->
        ApiErrorHandler.handle_error(conn, :bad_request, %{message: "Invalid notification ID format"})

      {:error, "Notification not found"} ->
        ApiErrorHandler.handle_error(conn, :not_found, %{resource: "notification"})

      {:error, _reason} ->
        ApiErrorHandler.handle_error(conn, :internal_server_error, %{})
    end
  end

  @doc """
  GET /api/users/:user_id/notifications - Get notifications for a user
  """
  @spec user_notifications(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def user_notifications(conn, %{"user_id" => user_id} = params) do
    with {:ok, pagination} <- RequestValidator.validate_pagination_params(params),
         {:ok, filters} <- RequestValidator.validate_notification_filters(params),
         combined_filters <- Map.merge(filters, pagination),
         {:ok, notifications} <- NotificationService.get_user_notifications(user_id, combined_filters) do
      pagination_info = build_pagination_info(notifications, combined_filters)
      ApiErrorHandler.paginated_response(conn, notifications, pagination_info, filters)
    else
      {:error, reason} when is_binary(reason) ->
        ApiErrorHandler.handle_error(conn, :bad_request, %{message: reason})

      {:error, _reason} ->
        ApiErrorHandler.handle_error(conn, :internal_server_error, %{})
    end
  end

  # Private helper functions

  defp build_pagination_info(notifications, filters) do
    %{
      total: length(notifications),
      limit: Map.get(filters, :limit, 50),
      offset: Map.get(filters, :offset, 0),
      has_more: length(notifications) == Map.get(filters, :limit, 50)
    }
  end
end
