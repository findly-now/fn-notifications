defmodule FnNotifications.Infrastructure.Repositories.ContactExchangeNotificationRepository do
  @moduledoc """
  PostgreSQL Repository Implementation for Contact Exchange Notifications

  Implements the ContactExchangeNotificationRepositoryBehavior using Ecto and PostgreSQL.
  Provides persistence and querying capabilities for contact exchange notifications
  while maintaining domain isolation and proper error handling.

  ## Security Considerations
  - Never logs sensitive contact information
  - Properly handles encrypted contact data
  - Implements secure deletion for expired notifications
  - Uses parameterized queries to prevent injection attacks
  """

  import Ecto.Query, warn: false
  require Logger

  alias FnNotifications.Repo
  alias FnNotifications.Domain.Entities.ContactExchangeNotification
  alias FnNotifications.Domain.Repositories.ContactExchangeNotificationRepositoryBehavior
  alias FnNotifications.Infrastructure.Schemas.ContactExchangeNotificationSchema

  @behaviour ContactExchangeNotificationRepositoryBehavior

  @impl ContactExchangeNotificationRepositoryBehavior
  def create(%ContactExchangeNotification{} = notification) do
    Logger.debug("Creating contact exchange notification",
      notification_id: notification.id,
      request_id: notification.request_id,
      type: notification.notification_type.value
    )

    attrs = ContactExchangeNotificationSchema.from_domain_entity(notification)

    case ContactExchangeNotificationSchema.create_changeset(attrs) do
      %{valid?: true} = changeset ->
        case Repo.insert(changeset) do
          {:ok, schema} ->
            Logger.debug("Contact exchange notification created successfully",
              notification_id: schema.id
            )

            ContactExchangeNotificationSchema.to_domain_entity(schema)

          {:error, changeset} = error ->
            Logger.error("Failed to create contact exchange notification",
              notification_id: notification.id,
              errors: changeset.errors
            )

            error
        end

      %{valid?: false} = changeset ->
        Logger.error("Invalid contact exchange notification data",
          notification_id: notification.id,
          errors: changeset.errors
        )

        {:error, changeset}
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def update(%ContactExchangeNotification{} = notification) do
    Logger.debug("Updating contact exchange notification",
      notification_id: notification.id
    )

    case Repo.get(ContactExchangeNotificationSchema, notification.id) do
      nil ->
        Logger.warning("Contact exchange notification not found for update",
          notification_id: notification.id
        )

        {:error, :not_found}

      schema ->
        attrs = ContactExchangeNotificationSchema.from_domain_entity(notification)

        case ContactExchangeNotificationSchema.create_changeset(attrs) do
          %{valid?: true} = changeset ->
            case Repo.update(changeset) do
              {:ok, updated_schema} ->
                Logger.debug("Contact exchange notification updated successfully",
                  notification_id: updated_schema.id
                )

                ContactExchangeNotificationSchema.to_domain_entity(updated_schema)

              {:error, changeset} = error ->
                Logger.error("Failed to update contact exchange notification",
                  notification_id: notification.id,
                  errors: changeset.errors
                )

                error
            end

          %{valid?: false} = changeset ->
            Logger.error("Invalid contact exchange notification update data",
              notification_id: notification.id,
              errors: changeset.errors
            )

            {:error, changeset}
        end
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def find_by_id(id) when is_binary(id) do
    case Repo.get(ContactExchangeNotificationSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        ContactExchangeNotificationSchema.to_domain_entity(schema)
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def find_by_request_id(request_id) when is_binary(request_id) do
    query =
      from n in ContactExchangeNotificationSchema,
        where: n.request_id == ^request_id,
        order_by: [desc: n.inserted_at],
        limit: 1

    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      schema ->
        ContactExchangeNotificationSchema.to_domain_entity(schema)
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def find_by_requester_user_id(user_id) when is_binary(user_id) do
    query =
      from n in ContactExchangeNotificationSchema,
        where: n.requester_user_id == ^user_id,
        order_by: [desc: n.inserted_at]

    schemas = Repo.all(query)

    case convert_schemas_to_entities(schemas) do
      {:ok, entities} -> {:ok, entities}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def find_by_owner_user_id(user_id) when is_binary(user_id) do
    query =
      from n in ContactExchangeNotificationSchema,
        where: n.owner_user_id == ^user_id,
        order_by: [desc: n.inserted_at]

    schemas = Repo.all(query)

    case convert_schemas_to_entities(schemas) do
      {:ok, entities} -> {:ok, entities}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def find_by_post_id(post_id) when is_binary(post_id) do
    query =
      from n in ContactExchangeNotificationSchema,
        where: n.related_post_id == ^post_id,
        order_by: [desc: n.inserted_at]

    schemas = Repo.all(query)

    case convert_schemas_to_entities(schemas) do
      {:ok, entities} -> {:ok, entities}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def find_pending_notifications do
    query =
      from n in ContactExchangeNotificationSchema,
        where: n.notification_sent == false,
        order_by: [asc: n.inserted_at]

    schemas = Repo.all(query)

    case convert_schemas_to_entities(schemas) do
      {:ok, entities} -> {:ok, entities}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def find_expired_notifications do
    now = DateTime.utc_now()

    query =
      from n in ContactExchangeNotificationSchema,
        where: not is_nil(n.expires_at) and n.expires_at < ^now,
        order_by: [asc: n.expires_at]

    schemas = Repo.all(query)

    case convert_schemas_to_entities(schemas) do
      {:ok, entities} -> {:ok, entities}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def find_by_status_and_type(status, type) when is_binary(status) and is_binary(type) do
    query =
      from n in ContactExchangeNotificationSchema,
        where: n.exchange_status == ^status and n.notification_type == ^type,
        order_by: [desc: n.inserted_at]

    schemas = Repo.all(query)

    case convert_schemas_to_entities(schemas) do
      {:ok, entities} -> {:ok, entities}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def mark_as_sent(notification_id) when is_binary(notification_id) do
    Logger.debug("Marking contact exchange notification as sent",
      notification_id: notification_id
    )

    case Repo.get(ContactExchangeNotificationSchema, notification_id) do
      nil ->
        Logger.warning("Contact exchange notification not found for marking as sent",
          notification_id: notification_id
        )

        {:error, :not_found}

      schema ->
        attrs = %{
          notification_sent: true,
          sent_at: DateTime.utc_now()
        }

        case ContactExchangeNotificationSchema.update_sent_changeset(schema, attrs) do
          %{valid?: true} = changeset ->
            case Repo.update(changeset) do
              {:ok, updated_schema} ->
                Logger.debug("Contact exchange notification marked as sent",
                  notification_id: updated_schema.id
                )

                ContactExchangeNotificationSchema.to_domain_entity(updated_schema)

              {:error, changeset} = error ->
                Logger.error("Failed to mark notification as sent",
                  notification_id: notification_id,
                  errors: changeset.errors
                )

                error
            end

          %{valid?: false} = changeset ->
            Logger.error("Invalid data for marking notification as sent",
              notification_id: notification_id,
              errors: changeset.errors
            )

            {:error, changeset}
        end
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def delete_expired_notifications do
    # Calculate cutoff time for expired notifications (e.g., 30 days old)
    cutoff_time = DateTime.utc_now() |> DateTime.add(-30, :day)

    Logger.info("Deleting expired contact exchange notifications",
      cutoff_time: DateTime.to_iso8601(cutoff_time)
    )

    query =
      from n in ContactExchangeNotificationSchema,
        where:
          (not is_nil(n.expires_at) and n.expires_at < ^cutoff_time) or
          (n.exchange_status in ["expired", "denied"] and n.inserted_at < ^cutoff_time)

    case Repo.delete_all(query) do
      {count, _} ->
        Logger.info("Deleted #{count} expired contact exchange notifications")
        {:ok, count}

      error ->
        Logger.error("Failed to delete expired notifications: #{inspect(error)}")
        {:error, :delete_failed}
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def count_all do
    query = from n in ContactExchangeNotificationSchema, select: count(n.id)

    case Repo.one(query) do
      count when is_integer(count) -> {:ok, count}
      error -> {:error, error}
    end
  end

  @impl ContactExchangeNotificationRepositoryBehavior
  def count_by_status(status) when is_binary(status) do
    query =
      from n in ContactExchangeNotificationSchema,
        where: n.exchange_status == ^status,
        select: count(n.id)

    case Repo.one(query) do
      count when is_integer(count) -> {:ok, count}
      error -> {:error, error}
    end
  end

  # Private helper functions

  defp convert_schemas_to_entities(schemas) when is_list(schemas) do
    entities =
      schemas
      |> Enum.map(&ContactExchangeNotificationSchema.to_domain_entity/1)
      |> Enum.reduce_while({:ok, []}, fn
        {:ok, entity}, {:ok, acc} -> {:cont, {:ok, [entity | acc]}}
        {:error, reason}, _acc -> {:halt, {:error, reason}}
      end)

    case entities do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end
end