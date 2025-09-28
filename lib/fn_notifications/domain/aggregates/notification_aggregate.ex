defmodule FnNotifications.Domain.Aggregates.NotificationAggregate do
  @moduledoc """
  Notification aggregate for business logic and validation.
  """

  alias FnNotifications.Domain.Entities.Notification
  alias FnNotifications.Domain.ValueObjects.NotificationChannel

  @type t :: %__MODULE__{notification: Notification.t()}

  defstruct [:notification]

  @doc """
  Creates a new notification aggregate.
  """
  @spec create(map()) :: {:ok, t()} | {:error, String.t()}
  def create(attrs) do
    with {:ok, notification} <- Notification.new(attrs) do
      aggregate = %__MODULE__{notification: notification}


      {:ok, aggregate}
    end
  end

  @doc """
  Loads an existing notification aggregate.
  """
  @spec load(Notification.t()) :: t()
  def load(%Notification{} = notification) do
    %__MODULE__{notification: notification}
  end

  @doc """
  Sends the notification.
  """
  @spec send(t()) :: {:ok, t()} | {:error, String.t()}
  def send(%__MODULE__{notification: notification} = aggregate) do
    cond do
      not Notification.ready_to_send?(notification) ->
        {:error, "Notification is not ready to be sent (scheduled for future)"}

      notification.status != :pending ->
        {:error, "Only pending notifications can be sent"}

      true ->
        case Notification.mark_as_sent(notification) do
          {:ok, updated_notification} ->
            updated_aggregate = %{aggregate | notification: updated_notification}


            {:ok, updated_aggregate}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Marks the notification as delivered.
  """
  @spec mark_delivered(t()) :: {:ok, t()} | {:error, String.t()}
  def mark_delivered(%__MODULE__{notification: notification} = aggregate) do
    case Notification.mark_as_delivered(notification) do
      {:ok, updated_notification} ->
        updated_aggregate = %{aggregate | notification: updated_notification}

        {:ok, updated_aggregate}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Marks the notification as failed.
  """
  @spec mark_failed(t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def mark_failed(%__MODULE__{notification: notification} = aggregate, reason) do
    case Notification.mark_as_failed(notification, reason) do
      {:ok, updated_notification} ->
        updated_aggregate = %{aggregate | notification: updated_notification}


        {:ok, updated_aggregate}

      {:error, error_reason} ->
        {:error, error_reason}
    end
  end

  @doc """
  Cancels a pending notification.
  """
  @spec cancel(t(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def cancel(%__MODULE__{notification: %{status: :pending} = notification} = aggregate, reason) do
    cancelled_notification = %{
      notification
      | status: :cancelled,
        failure_reason: reason,
        updated_at: DateTime.utc_now()
    }

    {:ok, %{aggregate | notification: cancelled_notification}}
  end

  def cancel(%__MODULE__{notification: notification}, _reason) do
    {:error, "Cannot cancel notification with status: #{notification.status}"}
  end

  @doc """
  Validates notification for processing using domain specifications.
  """
  @spec validate_for_processing(t()) :: :ok | {:error, String.t()}
  def validate_for_processing(%__MODULE__{notification: notification}) do
    case Notification.valid_for_processing?(notification) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Applies channel-specific business rules using simple validation.
  """
  @spec apply_channel_rules(t(), NotificationChannel.t()) :: :ok | {:error, String.t()}
  def apply_channel_rules(%__MODULE__{notification: notification}, _channel) do
    # Simple validation - just ensure notification is valid
    case Notification.valid_for_processing?(notification) do
      {:ok, true} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the notification entity.
  """
  @spec notification(t()) :: Notification.t()
  def notification(%__MODULE__{notification: notification}), do: notification
end
