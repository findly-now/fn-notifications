defmodule FnNotifications.Domain.Repositories.NotificationRepositoryBehavior do
  @moduledoc """
  Repository behavior contract for notification persistence operations.
  This belongs in the domain layer to define the contract that infrastructure must implement.
  """

  alias FnNotifications.Domain.Entities.Notification

  @doc """
  Saves a notification entity to persistent storage.
  """
  @callback save(Notification.t()) :: {:ok, Notification.t()} | {:error, term()}

  @doc """
  Gets a notification by its unique identifier.
  """
  @callback get_by_id(String.t()) :: {:ok, Notification.t()} | {:error, :not_found}

  @doc """
  Gets all notifications for a specific user with optional filters.
  """
  @callback get_by_user_id(String.t(), map()) :: {:ok, [Notification.t()]} | {:error, term()}

  @doc """
  Gets notification statistics for a user.
  """
  @callback get_user_stats(String.t(), DateTime.t() | nil) :: {:ok, map()} | {:error, term()}

end
