defmodule FnNotifications.Infrastructure.Clients.TwilioClient do
  @moduledoc """
  Tesla-based HTTP client for Twilio SMS and WhatsApp API.
  Handles both SMS and WhatsApp message delivery through Twilio's unified messaging API.
  """

  use Tesla

  require Logger

  @account_sid Application.compile_env(:fn_notifications, :twilio_account_sid)
  @auth_token Application.compile_env(:fn_notifications, :twilio_auth_token)

  plug Tesla.Middleware.BaseUrl, "https://api.twilio.com/2010-04-01/Accounts/#{@account_sid}"
  plug Tesla.Middleware.BasicAuth, username: @account_sid, password: @auth_token
  plug Tesla.Middleware.FormUrlencoded
  plug Tesla.Middleware.JSON, decode_content_types: ["application/json"]
  plug Tesla.Middleware.Timeout, timeout: 30_000

  plug Tesla.Middleware.Retry,
    delay: 1000,
    max_retries: 3,
    max_delay: 10_000,
    should_retry: fn
      {:ok, %{status: status}} when status in [429, 500, 502, 503] -> true
      {:ok, _} -> false
      {:error, _} -> true
    end

  plug Tesla.Middleware.Logger, debug: false

  alias FnNotifications.Domain.Services.CircuitBreakerService

  @doc """
  Sends an SMS message via Twilio API with circuit breaker protection.
  """
  @spec send_sms(map()) :: {:ok, map()} | {:error, String.t()}
  def send_sms(%{to: to, body: body} = params) when is_binary(to) and is_binary(body) do
    CircuitBreakerService.call(:twilio_circuit_breaker, fn ->
      send_sms_internal(params)
    end)
  end

  def send_sms(params) do
    {:error, "Invalid SMS parameters: #{inspect(params)}"}
  end

  defp send_sms_internal(%{to: to, body: body} = params) do
    message_params = %{
      "To" => to,
      "From" => Map.get(params, :from, default_from_number()),
      "Body" => body
    }

    # Add optional parameters
    message_params = add_optional_params(message_params, params)

    case post("/Messages.json", message_params) do
      {:ok, %Tesla.Env{status: 201, body: body}} ->
        Logger.debug("SMS sent successfully via Twilio", sid: Map.get(body, "sid"))
        {:ok, body}

      {:ok, %Tesla.Env{status: 400, body: body}} ->
        error_message = extract_error_message(body, "Invalid SMS request")
        Logger.warning("Twilio SMS request invalid", error: error_message, params: message_params)
        {:error, error_message}

      {:ok, %Tesla.Env{status: 401}} ->
        error_message = "Twilio authentication failed"
        Logger.error(error_message)
        {:error, error_message}

      {:ok, %Tesla.Env{status: 403}} ->
        error_message = "Twilio access forbidden - check permissions"
        Logger.error(error_message)
        {:error, error_message}

      {:ok, %Tesla.Env{status: 429, body: body}} ->
        error_message = extract_error_message(body, "Twilio rate limit exceeded")
        Logger.warning("Twilio rate limit exceeded", error: error_message)
        {:error, error_message}

      {:ok, %Tesla.Env{status: status, body: body}} when status >= 500 ->
        error_message = extract_error_message(body, "Twilio server error")
        Logger.error("Twilio server error", status: status, error: error_message)
        {:error, error_message}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        error_message = "Unexpected Twilio response: #{status}"
        Logger.error(error_message, response_body: body)
        {:error, error_message}

      {:error, %Tesla.Error{reason: reason}} ->
        error_message = "Twilio HTTP client error: #{inspect(reason)}"
        Logger.error(error_message)
        {:error, error_message}

      {:error, reason} ->
        error_message = "Twilio request failed: #{inspect(reason)}"
        Logger.error(error_message)
        {:error, error_message}
    end
  end


  @doc """
  Sends a WhatsApp message via Twilio API with circuit breaker protection.
  """
  @spec send_whatsapp_message(map()) :: {:ok, map()} | {:error, String.t()}
  def send_whatsapp_message(%{to: to, body: body} = params) when is_binary(to) and is_binary(body) do
    CircuitBreakerService.call(:twilio_circuit_breaker, fn ->
      send_whatsapp_message_internal(params)
    end)
  end

  def send_whatsapp_message(params) do
    {:error, "Invalid WhatsApp message parameters: #{inspect(params)}"}
  end

  defp send_whatsapp_message_internal(%{to: to, body: body} = params) do
    message_params = %{
      # Should already have "whatsapp:" prefix
      "To" => to,
      "From" => Map.get(params, :from, default_whatsapp_from_number()),
      "Body" => body
    }

    # Add optional parameters specific to WhatsApp
    message_params = add_whatsapp_optional_params(message_params, params)

    case post("/Messages.json", message_params) do
      {:ok, %Tesla.Env{status: 201, body: body}} ->
        Logger.debug("WhatsApp message sent successfully via Twilio", sid: Map.get(body, "sid"))
        {:ok, body}

      {:ok, %Tesla.Env{status: 400, body: body}} ->
        error_message = extract_error_message(body, "Invalid WhatsApp message request")
        Logger.warning("Twilio WhatsApp request invalid", error: error_message, params: message_params)
        {:error, error_message}

      {:ok, %Tesla.Env{status: 401}} ->
        error_message = "Twilio authentication failed"
        Logger.error(error_message)
        {:error, error_message}

      {:ok, %Tesla.Env{status: 403}} ->
        error_message = "Twilio access forbidden - check WhatsApp sandbox permissions"
        Logger.error(error_message)
        {:error, error_message}

      {:ok, %Tesla.Env{status: 429, body: body}} ->
        error_message = extract_error_message(body, "Twilio rate limit exceeded")
        Logger.warning("Twilio rate limit exceeded", error: error_message)
        {:error, error_message}

      {:ok, %Tesla.Env{status: status, body: body}} when status >= 500 ->
        error_message = extract_error_message(body, "Twilio server error")
        Logger.error("Twilio server error", status: status, error: error_message)
        {:error, error_message}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        error_message = "Unexpected Twilio response: #{status}"
        Logger.error(error_message, response_body: body)
        {:error, error_message}

      {:error, %Tesla.Error{reason: reason}} ->
        error_message = "Twilio HTTP client error: #{inspect(reason)}"
        Logger.error(error_message)
        {:error, error_message}

      {:error, reason} ->
        error_message = "Twilio WhatsApp request failed: #{inspect(reason)}"
        Logger.error(error_message)
        {:error, error_message}
    end
  end


  @doc """
  Gets message status from Twilio.
  """
  @spec get_message_status(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_message_status(message_sid) when is_binary(message_sid) do
    case get("/Messages/#{message_sid}.json") do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, "Message not found"}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        error_message = extract_error_message(body, "Failed to get message status")
        Logger.error("Failed to get Twilio message status", status: status, error: error_message)
        {:error, error_message}

      {:error, reason} ->
        error_message = "Failed to get message status: #{inspect(reason)}"
        Logger.error(error_message)
        {:error, error_message}
    end
  end

  @doc """
  Validates phone number format.
  """
  @spec validate_phone_number(String.t()) :: :ok | {:error, String.t()}
  def validate_phone_number(phone_number) when is_binary(phone_number) do
    # Basic E.164 format validation
    if Regex.match?(~r/^\+[1-9]\d{1,14}$/, phone_number) do
      :ok
    else
      {:error, "Invalid phone number format. Must be in E.164 format (e.g., +1234567890)"}
    end
  end

  def validate_phone_number(_), do: {:error, "Phone number must be a string"}

  @doc """
  Validates SMS body content.
  """
  @spec validate_sms_body(String.t()) :: :ok | {:error, String.t()}
  def validate_sms_body(body) when is_binary(body) do
    cond do
      String.trim(body) == "" ->
        {:error, "SMS body cannot be empty"}

      # Twilio's limit
      String.length(body) > 1600 ->
        {:error, "SMS body too long (max 1600 characters)"}

      true ->
        :ok
    end
  end

  def validate_sms_body(_), do: {:error, "SMS body must be a string"}

  @doc """
  Validates WhatsApp message body content.
  """
  @spec validate_whatsapp_body(String.t()) :: :ok | {:error, String.t()}
  def validate_whatsapp_body(body) when is_binary(body) do
    cond do
      String.trim(body) == "" ->
        {:error, "WhatsApp message body cannot be empty"}

      # WhatsApp character limit via Twilio
      String.length(body) > 1600 ->
        {:error, "WhatsApp message body too long (max 1600 characters)"}

      true ->
        :ok
    end
  end

  def validate_whatsapp_body(_), do: {:error, "WhatsApp message body must be a string"}

  @doc """
  Validates WhatsApp phone number format (must include whatsapp: prefix).
  """
  @spec validate_whatsapp_number(String.t()) :: :ok | {:error, String.t()}
  def validate_whatsapp_number("whatsapp:" <> phone_number) do
    validate_phone_number(phone_number)
  end

  def validate_whatsapp_number(phone_number) when is_binary(phone_number) do
    {:error, "WhatsApp number must have 'whatsapp:' prefix. Got: #{phone_number}"}
  end

  def validate_whatsapp_number(_), do: {:error, "WhatsApp number must be a string"}

  @doc """
  Health check for Twilio service availability.
  """
  @spec health_check() :: :ok | {:error, String.t()}
  def health_check do
    # Simple ping to Twilio account info endpoint
    case get("/") do
      {:ok, %Tesla.Env{status: status}} when status in [200, 201] ->
        :ok

      {:ok, %Tesla.Env{status: 401}} ->
        {:error, "Authentication failed - check credentials"}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  # Private helper functions

  defp default_from_number do
    Application.get_env(:fn_notifications, :twilio_phone_number, "+15551234567")
  end

  defp default_whatsapp_from_number do
    Application.get_env(:fn_notifications, :twilio_whatsapp_number, "whatsapp:+14155238886")
  end

  defp add_optional_params(base_params, params) do
    base_params
    |> maybe_add_param("StatusCallback", params[:status_callback])
    |> maybe_add_param("ApplicationSid", params[:application_sid])
    |> maybe_add_param("MaxPrice", params[:max_price])
    |> maybe_add_param("ValidityPeriod", params[:validity_period])
  end

  defp add_whatsapp_optional_params(base_params, params) do
    base_params
    |> maybe_add_param("StatusCallback", params[:status_callback])
    |> maybe_add_param("MaxPrice", params[:max_price])

    # WhatsApp doesn't support ApplicationSid or ValidityPeriod
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

  defp extract_error_message(%{"message" => message}, _default) when is_binary(message), do: message
  defp extract_error_message(%{"error_message" => message}, _default) when is_binary(message), do: message

  defp extract_error_message(%{"code" => code, "message" => message}, _default) do
    "Twilio Error #{code}: #{message}"
  end

  defp extract_error_message(_, default), do: default
end
