defmodule FnNotifications.Domain.Repositories.UserPreferencesRepositoryBehavior do
  @moduledoc """
  Repository behavior contract for user preferences persistence operations.
  This belongs in the domain layer to define the contract that infrastructure must implement.
  """

  alias FnNotifications.Domain.Entities.UserPreferences

  @doc """
  Saves user preferences entity to persistent storage.
  """
  @callback save(UserPreferences.t()) :: {:ok, UserPreferences.t()} | {:error, term()}

  @doc """
  Gets user preferences by user ID.
  """
  @callback get_by_user_id(String.t()) :: {:ok, UserPreferences.t()} | {:error, :not_found}

  @doc """
  Gets user preferences by preferences ID.
  """
  @callback get_by_id(String.t()) :: {:ok, UserPreferences.t()} | {:error, :not_found}

  @doc """
  Updates existing user preferences.
  """
  @callback update(UserPreferences.t()) :: {:ok, UserPreferences.t()} | {:error, term()}

  @doc """
  Deletes user preferences.
  """
  @callback delete(String.t()) :: :ok | {:error, term()}

  @doc """
  Lists all user preferences with optional filters.
  """
  @callback list(map()) :: {:ok, [UserPreferences.t()]} | {:error, term()}

  @doc """
  Gets statistics about user preferences.
  """
  @callback get_stats() :: {:ok, map()} | {:error, term()}
end
