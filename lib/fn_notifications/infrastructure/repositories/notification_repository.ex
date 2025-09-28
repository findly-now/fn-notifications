defmodule FnNotifications.Infrastructure.Repositories.NotificationRepository do
  @moduledoc """
  Ecto-based repository for notification persistence following DDD patterns.
  """

  import Ecto.Query

  alias FnNotifications.Repo
  alias FnNotifications.Domain.Entities.Notification
  alias FnNotifications.Infrastructure.Schemas.NotificationSchema

  @behaviour FnNotifications.Domain.Repositories.NotificationRepositoryBehavior

  @doc """
  Saves a notification entity to the database.
  """
  @impl true
  def save(%Notification{} = notification) do
    changeset = NotificationSchema.from_entity(notification)

    case Repo.insert_or_update(changeset) do
      {:ok, schema} ->
        {:ok, NotificationSchema.to_entity(schema)}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  @doc """
  Gets a notification by ID.
  """
  @impl true
  def get_by_id(id) when is_binary(id) do
    case Repo.get(NotificationSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, NotificationSchema.to_entity(schema)}
    end
  end

  @doc """
  Gets recent notifications for dashboard display.
  """
  def get_recent_notifications(limit \\ 5) do
    query =
      from n in NotificationSchema,
        order_by: [desc: n.inserted_at],
        limit: ^limit

    notifications = Repo.all(query)
    Enum.map(notifications, &NotificationSchema.to_entity/1)
  end

  @doc """
  Gets dashboard statistics for Lost & Found metrics.
  """
  def get_dashboard_stats do
    today = Date.utc_today()
    today_start = DateTime.new!(today, ~T[00:00:00])
    today_end = DateTime.new!(today, ~T[23:59:59])

    # Get Lost & Found event counts
    lost_items_today = count_notifications_by_event_type_and_date("post.created", today_start, today_end)
    matches_found = count_notifications_by_event_type("post.matched")
    active_claims = count_notifications_by_event_type("post.claimed")
    items_recovered = count_notifications_by_event_type("post.resolved")

    # Get delivery statistics
    total_notifications = Repo.aggregate(NotificationSchema, :count, :id)
    delivered_today = count_notifications_by_status_and_date("delivered", today_start, today_end)
    pending_delivery = count_notifications_by_status("pending")
    failed_delivery = count_notifications_by_status("failed")

    # Get channel distribution
    email_notifications = count_notifications_by_channel("email")
    sms_notifications = count_notifications_by_channel("sms")
    whatsapp_notifications = count_notifications_by_channel("whatsapp")

    %{
      # Lost & Found Business Metrics
      lost_items_today: lost_items_today,
      matches_found: matches_found,
      active_claims: active_claims,
      items_recovered: items_recovered,

      # Delivery Performance Metrics
      total_notifications: total_notifications,
      delivered_today: delivered_today,
      pending_delivery: pending_delivery,
      failed_delivery: failed_delivery,

      # Channel Distribution
      email_notifications: email_notifications,
      sms_notifications: sms_notifications,
      whatsapp_notifications: whatsapp_notifications
    }
  end

  @doc """
  Gets notifications for a user with optional filters.
  """
  @impl true
  def get_by_user_id(user_id, filters \\ %{}) do
    # Special case: "all" means get all notifications (for admin view)
    query = if user_id == "all" do
      from n in NotificationSchema,
        order_by: [desc: n.inserted_at]
    else
      from n in NotificationSchema,
        where: n.user_id == ^user_id,
        order_by: [desc: n.inserted_at]
    end

    query = apply_filters(query, filters)

    notifications =
      query
      |> Repo.all()
      |> Enum.map(&NotificationSchema.to_entity/1)

    {:ok, notifications}
  end





  @doc """
  Gets notification statistics for a user.
  """
  @impl true
  def get_user_stats(user_id, from_date \\ nil) do
    base_query = from n in NotificationSchema, where: n.user_id == ^user_id

    query =
      case from_date do
        nil -> base_query
        date -> from n in base_query, where: n.inserted_at >= ^date
      end

    stats =
      from n in query,
        group_by: [n.status, n.channel],
        select: {n.status, n.channel, count(n.id)}

    results = Repo.all(stats)

    stats_map =
      results
      |> Enum.reduce(%{}, fn {status, channel, count}, acc ->
        channel_key = to_string(channel)
        status_key = to_string(status)

        acc
        |> Map.put_new(channel_key, %{})
        |> put_in([channel_key, status_key], count)
      end)

    {:ok, stats_map}
  end


  # Private helper functions
  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn {key, value}, acc ->
      case key do
        :channel ->
          from n in acc, where: n.channel == ^value

        :status ->
          from n in acc, where: n.status == ^value

        :event_type ->
          from n in acc, where: fragment("?->>'event_type' = ?", n.metadata, ^value)

        :from_date ->
          from n in acc, where: n.inserted_at >= ^value

        :to_date ->
          from n in acc, where: n.inserted_at <= ^value

        :limit ->
          from n in acc, limit: ^value

        :offset ->
          from n in acc, offset: ^value

        _ ->
          acc
      end
    end)
  end

  # Private helper functions for dashboard statistics

  defp count_notifications_by_event_type(event_type) do
    from(n in NotificationSchema,
      where: fragment("?->>'event_type' = ?", n.metadata, ^event_type),
      select: count(n.id)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp count_notifications_by_event_type_and_date(event_type, date_start, date_end) do
    from(n in NotificationSchema,
      where: fragment("?->>'event_type' = ?", n.metadata, ^event_type),
      where: n.inserted_at >= ^date_start and n.inserted_at <= ^date_end,
      select: count(n.id)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp count_notifications_by_status(status) do
    from(n in NotificationSchema,
      where: n.status == ^status,
      select: count(n.id)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp count_notifications_by_status_and_date(status, date_start, date_end) do
    from(n in NotificationSchema,
      where: n.status == ^status,
      where: n.inserted_at >= ^date_start and n.inserted_at <= ^date_end,
      select: count(n.id)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp count_notifications_by_channel(channel) do
    from(n in NotificationSchema,
      where: n.channel == ^channel,
      select: count(n.id)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Health check for database connectivity.
  """
  @spec health_check() :: :ok | {:error, String.t()}
  def health_check do
    try do
      # Simple query to check database connectivity
      case Repo.query("SELECT 1", []) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, "Database query failed: #{inspect(reason)}"}
      end
    rescue
      error -> {:error, "Database connection failed: #{inspect(error)}"}
    catch
      :exit, reason -> {:error, "Database process exited: #{inspect(reason)}"}
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
