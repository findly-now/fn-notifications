defmodule FnNotifications.Infrastructure.Adapters.EmailAdapter do
  @moduledoc """
  Email delivery adapter using Swoosh for sending notifications via email.
  """

  alias FnNotifications.Domain.Entities.{Notification, UserPreferences}
  alias FnNotifications.Mailer
  alias Swoosh.Email

  require Logger

  @behaviour FnNotifications.Infrastructure.Adapters.DeliveryAdapterBehavior

  @doc """
  Delivers a notification via email.
  """
  @impl true
  def deliver_notification(%Notification{channel: :email} = notification) do
    with {:ok, email} <- build_email(notification),
         {:ok, _result} <- Mailer.deliver(email) do
      Logger.info("Email delivered successfully", notification_id: notification.id)
      :ok
    else
      {:error, reason} ->
        Logger.error("Email delivery failed: #{inspect(reason)}", notification_id: notification.id)
        {:error, format_error(reason)}
    end
  end

  def deliver_notification(%Notification{channel: channel}) do
    {:error, "EmailAdapter cannot handle channel: #{channel}"}
  end

  @doc """
  Delivers a notification via email with user preferences providing contact info.
  """
  @spec deliver_notification(Notification.t(), UserPreferences.t()) :: :ok | {:error, String.t()}
  def deliver_notification(%Notification{channel: :email} = notification, user_preferences) do
    with {:ok, email} <- build_email(notification, user_preferences),
         {:ok, _result} <- Mailer.deliver(email) do
      Logger.info("Email delivered successfully", notification_id: notification.id)
      :ok
    else
      {:error, reason} ->
        Logger.error("Email delivery failed: #{inspect(reason)}", notification_id: notification.id)
        {:error, format_error(reason)}
    end
  end

  def deliver_notification(%Notification{channel: channel}, _user_preferences) do
    {:error, "EmailAdapter cannot handle channel: #{channel}"}
  end

  @doc """
  Builds a Swoosh email from a notification.
  """
  @spec build_email(Notification.t()) :: {:ok, Email.t()} | {:error, String.t()}
  def build_email(%Notification{} = notification) do
    with {:ok, recipient_email} <- get_recipient_email(notification.user_id),
         {:ok, template} <- get_email_template(notification),
         {:ok, rendered_content} <- render_template(template, notification) do
      email =
        Email.new()
        |> Email.to(recipient_email)
        |> Email.from(sender_email())
        |> Email.subject(notification.title)
        |> Email.html_body(rendered_content.html_body)
        |> Email.text_body(rendered_content.text_body)
        |> add_headers(notification)

      {:ok, email}
    end
  end

  @doc """
  Builds a Swoosh email from a notification using user preferences for contact info.
  """
  @spec build_email(Notification.t(), UserPreferences.t()) :: {:ok, Email.t()} | {:error, String.t()}
  def build_email(%Notification{} = notification, %UserPreferences{email: email} = _user_preferences) do
    with {:ok, recipient_email} <- validate_recipient_email(email),
         {:ok, template} <- get_email_template(notification),
         {:ok, rendered_content} <- render_template(template, notification) do
      email =
        Email.new()
        |> Email.to(recipient_email)
        |> Email.from(sender_email())
        |> Email.subject(notification.title)
        |> Email.html_body(rendered_content.html_body)
        |> Email.text_body(rendered_content.text_body)
        |> add_headers(notification)

      {:ok, email}
    end
  end

  @doc """
  Validates if the notification can be delivered via email.
  """
  @impl true
  def can_deliver?(%Notification{channel: :email} = notification) do
    case get_recipient_email(notification.user_id) do
      {:ok, _email} -> true
      {:error, _} -> false
    end
  end

  def can_deliver?(%Notification{}), do: false

  @doc """
  Gets delivery method identifier.
  """
  @impl true
  def delivery_method, do: :email

  # Private helper functions
  defp get_recipient_email(user_id) do
    case Application.get_env(:fn_notifications, :test_mode, false) do
      true ->
        {:ok, "test@example.com"}

      false ->
        # Fetch real email from user preferences
        case fetch_user_email_from_preferences(user_id) do
          {:ok, email} when is_binary(email) -> {:ok, email}
          _ -> {:error, "User email not found or invalid"}
        end
    end
  end

  defp validate_recipient_email(nil) do
    {:error, "User email address is not configured"}
  end

  defp validate_recipient_email(email) when is_binary(email) do
    if String.contains?(email, "@") and String.length(email) > 0 do
      {:ok, email}
    else
      {:error, "Invalid email address format"}
    end
  end

  defp validate_recipient_email(_) do
    {:error, "Email address must be a string"}
  end

  defp fetch_user_email_from_preferences(user_id) do
    # Fetch from user preferences repository
    case FnNotifications.Infrastructure.Repositories.UserPreferencesRepository.get_by_user_id(user_id) do
      {:ok, %{email: email}} when is_binary(email) -> {:ok, email}
      {:ok, %{email: nil}} -> {:error, "User email not configured in preferences"}
      {:error, :not_found} -> {:error, "User preferences not found"}
      {:error, reason} -> {:error, "Failed to fetch user preferences: #{inspect(reason)}"}
    end
  end

  defp get_email_template(%Notification{} = notification) do
    template_name = determine_template_name(notification)
    {:ok, template_name}
  end

  defp determine_template_name(%Notification{metadata: %{"event_type" => event_type}}) do
    case event_type do
      "post.created" -> "new_post_notification"
      "post.liked" -> "post_liked_notification"
      "post.commented" -> "post_commented_notification"
      "post.shared" -> "post_shared_notification"
      _ -> "generic_notification"
    end
  end

  defp determine_template_name(%Notification{}), do: "generic_notification"

  defp render_template(template_name, %Notification{} = notification) do
    # In a real implementation, this would use a templating engine like EEx or Liquid
    html_body = render_html_template(template_name, notification)
    text_body = render_text_template(template_name, notification)

    {:ok, %{html_body: html_body, text_body: text_body}}
  end

  defp render_html_template("generic_notification", notification) do
    """
    <html>
      <body>
        <h1>#{html_escape(notification.title)}</h1>
        <p>#{html_escape(notification.body)}</p>
        <hr>
        <p><small>This is an automated notification from FN Notifications Service</small></p>
      </body>
    </html>
    """
  end

  defp render_html_template("new_post_notification", notification) do
    author_id = get_in(notification.metadata, ["author_id"]) || "someone"

    """
    <html>
      <body>
        <h1>New Post from #{html_escape(author_id)}</h1>
        <p>#{html_escape(notification.body)}</p>
        <p><a href="#{post_url(notification)}">View Post</a></p>
        <hr>
        <p><small>This is an automated notification from FN Notifications Service</small></p>
      </body>
    </html>
    """
  end

  defp render_html_template(_template_name, notification) do
    # Fallback to generic template
    render_html_template("generic_notification", notification)
  end

  defp render_text_template(_template_name, notification) do
    """
    #{notification.title}

    #{notification.body}

    ---
    This is an automated notification from FN Notifications Service
    """
  end

  defp html_escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#x27;")
  end

  defp html_escape(nil), do: ""
  defp html_escape(value), do: to_string(value) |> html_escape()

  defp post_url(%Notification{metadata: %{"post_id" => post_id}}) do
    base_url = Application.get_env(:fn_notifications, :web_base_url, "https://example.com")
    "#{base_url}/posts/#{post_id}"
  end

  defp post_url(_notification), do: "#"

  defp add_headers(email, %Notification{} = notification) do
    email
    |> Email.header("X-Notification-ID", notification.id)
  end

  defp sender_email do
    Application.get_env(:fn_notifications, :sender_email, "notifications@fnnotifications.com")
  end

  defp format_error(%Swoosh.DeliveryError{reason: reason}) do
    "Swoosh delivery error: #{inspect(reason)}"
  end

  defp format_error({:error, reason}) when is_binary(reason) do
    reason
  end

  defp format_error(error) do
    "Email delivery error: #{inspect(error)}"
  end

  @doc """
  Health check for email service.
  """
  @spec health_check() :: :ok | {:error, String.t()}
  def health_check do
    # Simple check to see if Swoosh is configured and available
    try do
      case Application.get_env(:fn_notifications, :email_adapter) do
        nil -> {:error, "Email adapter not configured"}
        _adapter -> :ok
      end
    rescue
      error -> {:error, "Email health check failed: #{inspect(error)}"}
    end
  end
end
