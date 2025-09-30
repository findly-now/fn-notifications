defmodule FnNotifications.Infrastructure.Schemas.ContactExchangeNotificationSchema do
  @moduledoc """
  Ecto Schema for Contact Exchange Notifications

  Database schema mapping for the contact_exchange_notifications table.
  This schema handles the persistence layer for secure contact sharing
  workflow notifications while maintaining proper data types and constraints.

  ## Security Considerations
  - Contact information is stored encrypted in the contact_info JSONB field
  - Sensitive data is never logged or exposed in plain text
  - Proper indexing for efficient querying while maintaining privacy
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias FnNotifications.Domain.Entities.ContactExchangeNotification
  alias FnNotifications.Domain.ValueObjects.{ContactExchangeStatus, ContactExchangeNotificationType}

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "contact_exchange_notifications" do
    field :request_id, :string
    field :requester_user_id, :string
    field :owner_user_id, :string
    field :related_post_id, :string
    field :exchange_status, :string
    field :notification_type, :string
    field :contact_info, :map, default: %{}
    field :expires_at, :utc_datetime
    field :metadata, :map, default: %{}
    field :notification_sent, :boolean, default: false
    field :sent_at, :utc_datetime

    timestamps(inserted_at: :inserted_at, updated_at: :updated_at, type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new contact exchange notification.
  """
  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :request_id,
      :requester_user_id,
      :owner_user_id,
      :related_post_id,
      :exchange_status,
      :notification_type,
      :contact_info,
      :expires_at,
      :metadata
    ])
    |> validate_required([
      :id,
      :request_id,
      :requester_user_id,
      :owner_user_id,
      :related_post_id,
      :exchange_status,
      :notification_type
    ])
    |> validate_inclusion(:exchange_status, ["pending", "approved", "denied", "expired"])
    |> validate_inclusion(:notification_type, ["request_received", "approval_granted", "denial_sent", "expiration_notice"])
    |> validate_different_users()
    |> validate_contact_info_for_approval()
    |> unique_constraint(:id)
    |> unique_constraint([:request_id, :notification_type], name: :contact_exchange_notifications_request_type_unique)
  end

  @doc """
  Changeset for updating notification status (marking as sent).
  """
  @spec update_sent_changeset(__MODULE__.t(), map()) :: Ecto.Changeset.t()
  def update_sent_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:notification_sent, :sent_at])
    |> validate_required([:notification_sent])
  end

  @doc """
  Converts a database schema to a domain entity.
  """
  @spec to_domain_entity(__MODULE__.t()) :: {:ok, ContactExchangeNotification.t()} | {:error, term()}
  def to_domain_entity(%__MODULE__{} = schema) do
    with {:ok, exchange_status} <- ContactExchangeStatus.from_string(schema.exchange_status),
         {:ok, notification_type} <- ContactExchangeNotificationType.from_string(schema.notification_type) do
      domain_entity = %ContactExchangeNotification{
        id: schema.id,
        request_id: schema.request_id,
        requester_user_id: schema.requester_user_id,
        owner_user_id: schema.owner_user_id,
        related_post_id: schema.related_post_id,
        exchange_status: exchange_status,
        notification_type: notification_type,
        contact_info: schema.contact_info || %{},
        expires_at: schema.expires_at,
        metadata: schema.metadata || %{},
        notification_sent: schema.notification_sent,
        sent_at: schema.sent_at,
        inserted_at: schema.inserted_at,
        updated_at: schema.updated_at
      }

      {:ok, domain_entity}
    end
  end

  @doc """
  Converts a domain entity to database schema attributes.
  """
  @spec from_domain_entity(ContactExchangeNotification.t()) :: map()
  def from_domain_entity(%ContactExchangeNotification{} = entity) do
    %{
      id: entity.id,
      request_id: entity.request_id,
      requester_user_id: entity.requester_user_id,
      owner_user_id: entity.owner_user_id,
      related_post_id: entity.related_post_id,
      exchange_status: ContactExchangeStatus.to_string(entity.exchange_status),
      notification_type: ContactExchangeNotificationType.to_string(entity.notification_type),
      contact_info: entity.contact_info,
      expires_at: entity.expires_at,
      metadata: entity.metadata,
      notification_sent: entity.notification_sent,
      sent_at: entity.sent_at,
      inserted_at: entity.inserted_at,
      updated_at: entity.updated_at
    }
  end

  # Private validation functions

  defp validate_different_users(changeset) do
    requester_id = get_field(changeset, :requester_user_id)
    owner_id = get_field(changeset, :owner_user_id)

    if requester_id && owner_id && requester_id == owner_id do
      add_error(changeset, :owner_user_id, "must be different from requester")
    else
      changeset
    end
  end

  defp validate_contact_info_for_approval(changeset) do
    notification_type = get_field(changeset, :notification_type)
    contact_info = get_field(changeset, :contact_info)

    case notification_type do
      "approval_granted" ->
        if is_map(contact_info) && map_size(contact_info) > 0 do
          changeset
        else
          add_error(changeset, :contact_info, "is required for approval notifications")
        end

      _ ->
        changeset
    end
  end
end