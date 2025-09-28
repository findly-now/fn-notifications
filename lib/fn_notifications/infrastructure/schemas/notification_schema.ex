defmodule FnNotifications.Infrastructure.Schemas.NotificationSchema do
  @moduledoc """
  Ecto schema for notifications table with conversion methods to/from domain entities.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FnNotifications.Domain.Entities.Notification

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  schema "notifications" do
    field :user_id, :string
    field :channel, Ecto.Enum, values: [:email, :sms, :whatsapp]
    field :status, Ecto.Enum, values: [:pending, :sent, :delivered, :failed, :cancelled]
    field :title, :string
    field :body, :string
    field :metadata, :map, default: %{}
    field :scheduled_at, :utc_datetime
    field :sent_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :failure_reason, :string
    field :retry_count, :integer, default: 0
    field :max_retries, :integer, default: 3

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset from a notification entity for insert/update operations.
  """
  @spec from_entity(Notification.t()) :: Ecto.Changeset.t()
  def from_entity(%Notification{} = notification) do
    attrs = %{
      id: notification.id,
      user_id: notification.user_id,
      channel: notification.channel,
      status: notification.status,
      title: notification.title,
      body: notification.body,
      metadata: notification.metadata,
      scheduled_at: notification.scheduled_at,
      sent_at: notification.sent_at,
      delivered_at: notification.delivered_at,
      failed_at: notification.failed_at,
      failure_reason: notification.failure_reason,
      retry_count: notification.retry_count,
      max_retries: notification.max_retries,
      inserted_at: notification.inserted_at,
      updated_at: notification.updated_at
    }

    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc """
  Converts a schema struct back to a domain entity.
  """
  @spec to_entity(t()) :: Notification.t()
  def to_entity(%__MODULE__{} = schema) do
    %Notification{
      id: schema.id,
      user_id: schema.user_id,
      channel: schema.channel,
      status: schema.status,
      title: schema.title,
      body: schema.body,
      metadata: schema.metadata || %{},
      scheduled_at: schema.scheduled_at,
      sent_at: schema.sent_at,
      delivered_at: schema.delivered_at,
      failed_at: schema.failed_at,
      failure_reason: schema.failure_reason,
      retry_count: schema.retry_count,
      max_retries: schema.max_retries,
      inserted_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Changeset for creating/updating notifications.
  """
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :id,
      :user_id,
      :channel,
      :status,
      :title,
      :body,
      :metadata,
      :scheduled_at,
      :sent_at,
      :delivered_at,
      :failed_at,
      :failure_reason,
      :retry_count,
      :max_retries,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([:id, :user_id, :channel, :status, :title, :body])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:body, min: 1, max: 2000)
    |> validate_length(:failure_reason, max: 500)
    |> validate_number(:retry_count, greater_than_or_equal_to: 0)
    |> validate_number(:max_retries, greater_than_or_equal_to: 0)
    |> validate_retry_count()
    |> unique_constraint(:id, name: :notifications_pkey)
  end

  # Private validation functions
  defp validate_retry_count(changeset) do
    retry_count = get_field(changeset, :retry_count)
    max_retries = get_field(changeset, :max_retries)

    if retry_count && max_retries && retry_count > max_retries do
      add_error(changeset, :retry_count, "cannot exceed max_retries")
    else
      changeset
    end
  end
end
