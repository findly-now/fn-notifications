defmodule FnNotifications.Domain.Entities.Notification do
  @moduledoc """
  Notification entity for multi-channel delivery.
  """

  alias FnNotifications.Domain.ValueObjects.{
    NotificationChannel,
    NotificationStatus
  }

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          channel: NotificationChannel.t(),
          status: NotificationStatus.t(),
          title: String.t(),
          body: String.t(),
          metadata: map(),
          scheduled_at: DateTime.t() | nil,
          sent_at: DateTime.t() | nil,
          delivered_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil,
          failure_reason: String.t() | nil,
          retry_count: non_neg_integer(),
          max_retries: non_neg_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @enforce_keys [:id, :user_id, :channel, :title, :body, :inserted_at]
  defstruct [
    :id,
    :user_id,
    :channel,
    :title,
    :body,
    :metadata,
    :scheduled_at,
    :sent_at,
    :delivered_at,
    :failed_at,
    :failure_reason,
    :inserted_at,
    :updated_at,
    status: NotificationStatus.initial(),
    retry_count: 0,
    max_retries: 3
  ]

  @doc """
  Creates a new notification entity.
  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(%{} = attrs) do
    now = DateTime.utc_now()

    with {:ok, id} <- validate_id(attrs[:id]),
         {:ok, user_id} <- validate_user_id(attrs[:user_id]),
         {:ok, channel} <- validate_channel(attrs[:channel]),
         {:ok, title} <- validate_title(attrs[:title]),
         {:ok, body} <- validate_body(attrs[:body]) do
      notification = %__MODULE__{
        id: id,
        user_id: user_id,
        channel: channel,
        title: title,
        body: body,
        metadata: attrs[:metadata] || %{},
        scheduled_at: attrs[:scheduled_at],
        max_retries: attrs[:max_retries] || 3,
        inserted_at: now,
        updated_at: now
      }

      {:ok, notification}
    end
  end

  @doc """
  Marks the notification as sent.
  """
  @spec mark_as_sent(t()) :: {:ok, t()} | {:error, String.t()}
  def mark_as_sent(%__MODULE__{status: current_status} = notification) do
    if NotificationStatus.valid_transition?(current_status, :sent) do
      {:ok, %{notification | status: :sent, sent_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}}
    else
      {:error, "Invalid status transition from #{current_status} to sent"}
    end
  end

  @doc """
  Marks the notification as delivered.
  """
  @spec mark_as_delivered(t()) :: {:ok, t()} | {:error, String.t()}
  def mark_as_delivered(%__MODULE__{status: current_status} = notification) do
    if NotificationStatus.valid_transition?(current_status, :delivered) do
      {:ok, %{notification | status: :delivered, delivered_at: DateTime.utc_now(), updated_at: DateTime.utc_now()}}
    else
      {:error, "Invalid status transition from #{current_status} to delivered"}
    end
  end

  @doc """
  Marks the notification as failed with a reason.
  """
  @spec mark_as_failed(t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def mark_as_failed(%__MODULE__{status: current_status} = notification, reason) do
    if NotificationStatus.valid_transition?(current_status, :failed) do
      now = DateTime.utc_now()
      {:ok, %{notification | status: :failed, failed_at: now, failure_reason: reason, updated_at: now}}
    else
      {:error, "Invalid status transition from #{current_status} to failed"}
    end
  end

  @doc """
  Increments the retry count and resets status to pending if retries available.
  """
  @spec increment_retry(t()) :: {:ok, t()} | {:error, String.t()}
  def increment_retry(%__MODULE__{retry_count: retry_count, max_retries: max_retries} = notification)
      when retry_count < max_retries do
    {:ok, %{notification | retry_count: retry_count + 1, status: :pending, updated_at: DateTime.utc_now()}}
  end

  def increment_retry(%__MODULE__{}), do: {:error, "Maximum retries exceeded"}

  @doc """
  Checks if the notification can be retried.
  """
  @spec can_retry?(t()) :: boolean()
  def can_retry?(%__MODULE__{retry_count: retry_count, max_retries: max_retries}),
    do: retry_count < max_retries

  @doc """
  Checks if the notification is ready to be sent (not scheduled or scheduled time has passed).
  """
  @spec ready_to_send?(t()) :: boolean()
  def ready_to_send?(%__MODULE__{scheduled_at: nil}), do: true

  def ready_to_send?(%__MODULE__{scheduled_at: scheduled_at}) do
    DateTime.compare(scheduled_at, DateTime.utc_now()) != :gt
  end

  @doc """
  Validates if notification is valid for processing.
  """
  @spec valid_for_processing?(t()) :: {:ok, true} | {:error, String.t()}
  def valid_for_processing?(%__MODULE__{} = notification) do
    cond do
      notification.status != :pending ->
        {:error, "Only pending notifications can be processed"}

      not ready_to_send?(notification) ->
        {:error, "Notification is scheduled for future delivery"}

      String.trim(notification.title) == "" ->
        {:error, "Notification title cannot be empty"}

      String.trim(notification.body) == "" ->
        {:error, "Notification body cannot be empty"}

      true ->
        {:ok, true}
    end
  end

  # Private validation functions
  defp validate_id(nil), do: {:ok, UUID.uuid4()}
  defp validate_id(id) when is_binary(id) and byte_size(id) > 0, do: {:ok, id}
  defp validate_id(_), do: {:error, "Invalid ID"}

  defp validate_user_id(user_id) when is_binary(user_id) and byte_size(user_id) > 0, do: {:ok, user_id}
  defp validate_user_id(_), do: {:error, "Invalid user ID"}

  defp validate_channel(channel) do
    if NotificationChannel.valid?(channel) do
      {:ok, channel}
    else
      {:error, "Invalid channel"}
    end
  end

  defp validate_title(title) when is_binary(title) and byte_size(title) > 0 and byte_size(title) <= 255, do: {:ok, title}
  defp validate_title(_), do: {:error, "Title must be a non-empty string with max 255 characters"}

  defp validate_body(body) when is_binary(body) and byte_size(body) > 0 and byte_size(body) <= 2000, do: {:ok, body}
  defp validate_body(_), do: {:error, "Body must be a non-empty string with max 2000 characters"}
end
