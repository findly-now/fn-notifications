defmodule FnNotifications.Domain.ValueObjects.NotificationStatus do
  @moduledoc """
  Notification status transitions and validation.
  """

  @type t :: :pending | :sent | :delivered | :failed | :cancelled

  @valid_statuses [:pending, :sent, :delivered, :failed, :cancelled]
  @final_statuses [:delivered, :failed, :cancelled]

  @doc """
  Creates a new notification status.
  """
  @spec new(atom()) :: {:ok, t()} | {:error, :invalid_status}
  def new(status) when status in @valid_statuses, do: {:ok, status}
  def new(_), do: {:error, :invalid_status}

  @doc """
  Returns all valid statuses.
  """
  @spec all() :: [t()]
  def all, do: @valid_statuses

  @doc """
  Checks if a status transition is valid.
  """
  @spec valid_transition?(t(), t()) :: boolean()
  def valid_transition?(from, to) do
    case {from, to} do
      # Initial state transitions
      {:pending, :sent} -> true
      {:pending, :failed} -> true
      {:pending, :cancelled} -> true
      # Sent state transitions
      {:sent, :delivered} -> true
      {:sent, :failed} -> true
      # No transitions from final states
      {final, _} when final in @final_statuses -> false
      # Self-transitions are invalid (redundant operations)
      {same, same} -> false
      # All other transitions are invalid
      _ -> false
    end
  end

  @doc """
  Checks if the status is final (no further transitions allowed).
  """
  @spec final?(t()) :: boolean()
  def final?(status), do: status in @final_statuses

  @doc """
  Returns the initial status for new notifications.
  """
  @spec initial() :: t()
  def initial, do: :pending

  @doc """
  Checks if the status indicates success.
  """
  @spec successful?(t()) :: boolean()
  def successful?(:delivered), do: true
  def successful?(_), do: false

  @doc """
  Checks if the status indicates failure.
  """
  @spec failed?(t()) :: boolean()
  def failed?(:failed), do: true
  def failed?(:cancelled), do: true
  def failed?(_), do: false
end
