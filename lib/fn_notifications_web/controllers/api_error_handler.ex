defmodule FnNotificationsWeb.ApiErrorHandler do
  @moduledoc """
  Centralized error handling for API endpoints.
  Provides consistent error response formatting across the API.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @doc """
  Handles various types of errors and returns standardized JSON responses.
  """
  def handle_error(conn, error_type, details \\ %{})

  def handle_error(conn, :validation_error, %{changeset: changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      success: false,
      error: "validation_failed",
      message: "The request contains validation errors",
      details: format_changeset_errors(changeset)
    })
  end

  def handle_error(conn, :not_found, %{resource: resource}) do
    conn
    |> put_status(:not_found)
    |> json(%{
      success: false,
      error: "not_found",
      message: "#{String.capitalize(resource)} not found",
      details: %{resource: resource}
    })
  end

  def handle_error(conn, :bad_request, %{message: message}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      success: false,
      error: "bad_request",
      message: message
    })
  end

  def handle_error(conn, :unauthorized, _details) do
    conn
    |> put_status(:unauthorized)
    |> json(%{
      success: false,
      error: "unauthorized",
      message: "Authentication required"
    })
  end

  def handle_error(conn, :forbidden, %{message: message}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      success: false,
      error: "forbidden",
      message: message
    })
  end

  def handle_error(conn, :internal_server_error, details) do
    # Log the error for debugging
    require Logger
    Logger.error("Internal server error: #{inspect(details)}")

    conn
    |> put_status(:internal_server_error)
    |> json(%{
      success: false,
      error: "internal_server_error",
      message: "An unexpected error occurred"
    })
  end

  def handle_error(conn, :rate_limit_exceeded, _details) do
    conn
    |> put_status(:too_many_requests)
    |> json(%{
      success: false,
      error: "rate_limit_exceeded",
      message: "Too many requests. Please try again later."
    })
  end

  def handle_error(conn, :service_unavailable, %{message: message}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      success: false,
      error: "service_unavailable",
      message: message
    })
  end

  # Fallback for unknown error types
  def handle_error(conn, _error_type, _details) do
    handle_error(conn, :internal_server_error, %{})
  end

  @doc """
  Formats Ecto changeset errors into a consistent structure.
  """
  def format_changeset_errors(%Ecto.Changeset{errors: errors}) do
    Enum.map(errors, fn {field, {message, opts}} ->
      %{
        field: to_string(field),
        message: message,
        code: get_error_code(message, opts),
        value: opts[:value]
      }
    end)
  end

  @doc """
  Creates a success response with consistent structure.
  """
  def success_response(conn, status, data, message \\ nil) do
    response = %{
      success: true,
      data: data
    }

    response = if message, do: Map.put(response, :message, message), else: response

    conn
    |> put_status(status)
    |> json(response)
  end

  @doc """
  Creates a paginated success response.
  """
  def paginated_response(conn, data, pagination_info, filters \\ %{}) do
    response = %{
      success: true,
      data: data,
      pagination: pagination_info
    }

    response = if map_size(filters) > 0, do: Map.put(response, :filters, filters), else: response

    conn
    |> put_status(:ok)
    |> json(response)
  end

  # Private helper functions
  defp get_error_code(message, opts) do
    cond do
      Keyword.has_key?(opts, :validation) ->
        opts[:validation]

      String.contains?(message, "can't be blank") ->
        "required"

      String.contains?(message, "has already been taken") ->
        "unique"

      String.contains?(message, "is invalid") ->
        "invalid"

      String.contains?(message, "should be") ->
        "constraint"

      true ->
        "validation"
    end
  end
end
