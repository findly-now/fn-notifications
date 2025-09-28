defmodule FnNotifications.Infrastructure.Repositories.UserPreferencesRepository do
  @moduledoc """
  Ecto-based repository for user preferences persistence following DDD patterns.
  """

  import Ecto.Query

  alias FnNotifications.Repo
  alias FnNotifications.Domain.Entities.UserPreferences
  alias FnNotifications.Infrastructure.Schemas.UserPreferencesSchema

  @behaviour FnNotifications.Domain.Repositories.UserPreferencesRepositoryBehavior

  @doc """
  Saves user preferences entity to the database.
  """
  @impl true
  def save(%UserPreferences{} = user_preferences) do
    changeset = UserPreferencesSchema.from_entity(user_preferences)

    case Repo.insert_or_update(changeset) do
      {:ok, schema} ->
        # Invalidate cache for this user
        cache_key = "user_prefs:#{user_preferences.user_id}"
        Cachex.del(:user_preferences_cache, cache_key)

        {:ok, UserPreferencesSchema.to_entity(schema)}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  @doc """
  Gets user preferences by user ID with caching.
  """
  @impl true
  def get_by_user_id(user_id) when is_binary(user_id) do
    cache_key = "user_prefs:#{user_id}"

    case Cachex.get(:user_preferences_cache, cache_key) do
      {:ok, nil} ->
        # Cache miss - fetch from database
        case Repo.get_by(UserPreferencesSchema, user_id: user_id) do
          nil ->
            {:error, :not_found}

          schema ->
            preferences = UserPreferencesSchema.to_entity(schema)
            # Cache for 5 minutes
            Cachex.put(:user_preferences_cache, cache_key, preferences, ttl: :timer.minutes(5))
            {:ok, preferences}
        end

      {:ok, cached_preferences} ->
        # Cache hit
        {:ok, cached_preferences}

      {:error, _reason} ->
        # Cache error - fallback to database
        case Repo.get_by(UserPreferencesSchema, user_id: user_id) do
          nil -> {:error, :not_found}
          schema -> {:ok, UserPreferencesSchema.to_entity(schema)}
        end
    end
  end

  @doc """
  Gets user preferences by preferences ID.
  """
  @impl true
  def get_by_id(id) when is_binary(id) do
    case Repo.get(UserPreferencesSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, UserPreferencesSchema.to_entity(schema)}
    end
  end

  @doc """
  Updates existing user preferences.
  """
  @impl true
  def update(%UserPreferences{} = user_preferences) do
    save(user_preferences)
  end

  @doc """
  Deletes user preferences by ID.
  """
  @impl true
  def delete(id) when is_binary(id) do
    case Repo.get(UserPreferencesSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, _deleted_schema} -> :ok
          {:error, changeset} -> {:error, format_errors(changeset)}
        end
    end
  end

  @doc """
  Lists user preferences with optional filters.
  """
  @impl true
  def list(filters \\ %{}) do
    query = build_list_query(filters)

    schemas = Repo.all(query)
    entities = Enum.map(schemas, &UserPreferencesSchema.to_entity/1)

    {:ok, entities}
  rescue
    error ->
      {:error, "Database query failed: #{inspect(error)}"}
  end

  @doc """
  Gets statistics about user preferences.
  """
  @impl true
  def get_stats do
    stats = %{
      total_users: count_total_users(),
      enabled_notifications: count_enabled_users(),
      disabled_notifications: count_disabled_users(),
      language_breakdown: get_language_breakdown(),
      timezone_breakdown: get_timezone_breakdown(),
      channel_preferences: get_channel_preferences_stats()
    }

    {:ok, stats}
  rescue
    error ->
      {:error, "Failed to get stats: #{inspect(error)}"}
  end

  # Private helper functions
  defp build_list_query(filters) do
    query = from(up in UserPreferencesSchema, order_by: [desc: up.inserted_at])

    Enum.reduce(filters, query, fn
      {:global_enabled, enabled}, query ->
        where(query, [up], up.global_enabled == ^enabled)

      {:language, language}, query ->
        where(query, [up], up.language == ^language)

      {:timezone, timezone}, query ->
        where(query, [up], up.timezone == ^timezone)

      {:limit, limit}, query ->
        limit(query, ^limit)

      _other, query ->
        query
    end)
  end

  defp count_total_users do
    Repo.aggregate(UserPreferencesSchema, :count, :id)
  end

  defp count_enabled_users do
    query = from(up in UserPreferencesSchema, where: up.global_enabled == true)
    Repo.aggregate(query, :count, :id)
  end

  defp count_disabled_users do
    query = from(up in UserPreferencesSchema, where: up.global_enabled == false)
    Repo.aggregate(query, :count, :id)
  end

  defp get_language_breakdown do
    query =
      from(up in UserPreferencesSchema,
        group_by: up.language,
        select: {up.language, count(up.id)}
      )

    Repo.all(query) |> Enum.into(%{})
  end

  defp get_timezone_breakdown do
    query =
      from(up in UserPreferencesSchema,
        group_by: up.timezone,
        select: {up.timezone, count(up.id)},
        order_by: [desc: count(up.id)],
        limit: 10
      )

    Repo.all(query) |> Enum.into(%{})
  end

  defp get_channel_preferences_stats do
    # This is a simplified implementation
    # In a real application, you might want to analyze the JSON data more thoroughly
    %{
      users_with_custom_preferences: count_users_with_custom_channel_preferences(),
      users_with_default_preferences: count_users_with_default_channel_preferences()
    }
  end

  defp count_users_with_custom_channel_preferences do
    query =
      from(up in UserPreferencesSchema,
        where: fragment("jsonb_array_length(?) > 0", up.channel_preferences)
      )

    Repo.aggregate(query, :count, :id)
  rescue
    # Fallback for non-PostgreSQL databases or JSON handling issues
    _ -> 0
  end

  defp count_users_with_default_channel_preferences do
    total = count_total_users()
    custom = count_users_with_custom_channel_preferences()
    total - custom
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, messages} ->
      "#{field}: #{Enum.join(messages, ", ")}"
    end)
    |> Enum.join("; ")
  end
end
