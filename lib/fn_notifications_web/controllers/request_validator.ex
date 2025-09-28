defmodule FnNotificationsWeb.RequestValidator do
  @moduledoc """
  Request validation utilities for API endpoints.
  Provides common validation functions and parameter parsing.
  """

  @doc """
  Validates required parameters are present in the request.
  """
  def validate_required_params(params, required_fields) when is_list(required_fields) do
    missing_fields =
      Enum.filter(required_fields, fn field ->
        case Map.get(params, to_string(field)) do
          nil -> true
          "" -> true
          _ -> false
        end
      end)

    case missing_fields do
      [] -> :ok
      fields -> {:error, "Missing required parameters: #{Enum.join(fields, ", ")}"}
    end
  end

  @doc """
  Validates UUID format for ID parameters.
  """
  def validate_uuid(uuid_string) when is_binary(uuid_string) do
    case UUID.info(uuid_string) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, "Invalid UUID format"}
    end
  end

  def validate_uuid(_), do: {:error, "UUID must be a string"}

  @doc """
  Validates notification channel values.
  """
  def validate_channel(channel) when is_binary(channel) do
    valid_channels = ["email", "sms", "whatsapp"]

    if channel in valid_channels do
      :ok
    else
      {:error, "Invalid channel. Must be one of: #{Enum.join(valid_channels, ", ")}"}
    end
  end

  def validate_channel(_), do: {:error, "Channel must be a string"}

  @doc """
  Validates notification status values.
  """
  def validate_status(status) when is_binary(status) do
    valid_statuses = ["pending", "sent", "delivered", "failed", "cancelled"]

    if status in valid_statuses do
      :ok
    else
      {:error, "Invalid status. Must be one of: #{Enum.join(valid_statuses, ", ")}"}
    end
  end

  def validate_status(_), do: {:error, "Status must be a string"}

  @doc """
  Validates and parses datetime strings.
  """
  def validate_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> {:ok, datetime}
      {:error, _} -> {:error, "Invalid datetime format. Use ISO 8601 format (e.g., 2023-09-24T12:00:00Z)"}
    end
  end

  def validate_datetime(%DateTime{} = datetime), do: {:ok, datetime}
  def validate_datetime(nil), do: {:ok, nil}
  def validate_datetime(_), do: {:error, "Datetime must be a string in ISO 8601 format"}

  @doc """
  Validates and parses integer parameters with optional bounds.
  """
  def validate_integer(value, opts \\ [])

  def validate_integer(value, opts) when is_integer(value) do
    validate_integer_bounds(value, opts)
  end

  def validate_integer(value, opts) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} -> validate_integer_bounds(int_value, opts)
      {_int_value, _remainder} -> {:error, "Invalid integer format"}
      :error -> {:error, "Invalid integer format"}
    end
  end

  def validate_integer(nil, opts) do
    if Keyword.get(opts, :required, false) do
      {:error, "Integer value is required"}
    else
      {:ok, Keyword.get(opts, :default)}
    end
  end

  def validate_integer(_, _opts), do: {:error, "Value must be an integer"}

  @doc """
  Validates string parameters with optional length constraints.
  """
  def validate_string(value, opts \\ [])

  def validate_string(value, opts) when is_binary(value) do
    cond do
      Keyword.has_key?(opts, :min_length) and String.length(value) < opts[:min_length] ->
        {:error, "String must be at least #{opts[:min_length]} characters long"}

      Keyword.has_key?(opts, :max_length) and String.length(value) > opts[:max_length] ->
        {:error, "String must be at most #{opts[:max_length]} characters long"}

      String.trim(value) == "" and Keyword.get(opts, :allow_empty, false) == false ->
        {:error, "String cannot be empty"}

      true ->
        {:ok, value}
    end
  end

  def validate_string(nil, opts) do
    if Keyword.get(opts, :required, false) do
      {:error, "String value is required"}
    else
      {:ok, Keyword.get(opts, :default)}
    end
  end

  def validate_string(_, _opts), do: {:error, "Value must be a string"}

  @doc """
  Validates pagination parameters (limit and offset).
  """
  def validate_pagination_params(params) do
    with {:ok, limit} <- validate_integer(params["limit"], min: 1, max: 100, default: 50),
         {:ok, offset} <- validate_integer(params["offset"], min: 0, default: 0) do
      {:ok, %{limit: limit, offset: offset}}
    end
  end

  @doc """
  Sanitizes and validates filter parameters for user notifications.
  """
  def validate_notification_filters(params) do
    filters = %{}

    filters =
      case validate_status(params["status"]) do
        :ok -> Map.put(filters, :status, params["status"])
        {:error, _} -> filters
      end

    filters =
      case validate_channel(params["channel"]) do
        :ok -> Map.put(filters, :channel, params["channel"])
        {:error, _} -> filters
      end

    filters =
      case validate_datetime(params["from_date"]) do
        {:ok, datetime} when not is_nil(datetime) -> Map.put(filters, :from_date, datetime)
        _ -> filters
      end

    filters =
      case validate_datetime(params["to_date"]) do
        {:ok, datetime} when not is_nil(datetime) -> Map.put(filters, :to_date, datetime)
        _ -> filters
      end

    {:ok, filters}
  end

  # Private helper functions
  defp validate_integer_bounds(value, opts) do
    cond do
      Keyword.has_key?(opts, :min) and value < opts[:min] ->
        {:error, "Value must be at least #{opts[:min]}"}

      Keyword.has_key?(opts, :max) and value > opts[:max] ->
        {:error, "Value must be at most #{opts[:max]}"}

      true ->
        {:ok, value}
    end
  end
end
