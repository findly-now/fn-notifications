defmodule FnNotifications.Domain.ValueObjects.ContactExchangeStatus do
  @moduledoc """
  Contact Exchange Status Value Object

  Represents the status of a contact exchange request in the secure contact sharing workflow.
  This follows a specific state machine for contact exchange lifecycle management.

  ## Valid Status Transitions

  ```
  pending → approved | denied | expired
  approved → expired
  denied → (terminal state)
  expired → (terminal state)
  ```

  ## Status Meanings
  - `pending`: Initial state when request is created
  - `approved`: Owner has approved sharing contact information
  - `denied`: Owner has denied the contact sharing request
  - `expired`: Request or approved contact sharing has expired
  """

  defstruct [:value]

  @type t :: %__MODULE__{value: atom()}

  @valid_statuses [:pending, :approved, :denied, :expired]

  @doc """
  Creates a pending status.
  """
  @spec pending() :: t()
  def pending, do: %__MODULE__{value: :pending}

  @doc """
  Creates an approved status.
  """
  @spec approved() :: t()
  def approved, do: %__MODULE__{value: :approved}

  @doc """
  Creates a denied status.
  """
  @spec denied() :: t()
  def denied, do: %__MODULE__{value: :denied}

  @doc """
  Creates an expired status.
  """
  @spec expired() :: t()
  def expired, do: %__MODULE__{value: :expired}

  @doc """
  Creates a status from a string value.
  """
  @spec from_string(String.t()) :: {:ok, t()} | {:error, :invalid_status}
  def from_string(status_string) when is_binary(status_string) do
    status_atom = String.to_existing_atom(status_string)

    if status_atom in @valid_statuses do
      {:ok, %__MODULE__{value: status_atom}}
    else
      {:error, :invalid_status}
    end
  rescue
    ArgumentError -> {:error, :invalid_status}
  end

  @doc """
  Converts the status to a string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{value: value}), do: Atom.to_string(value)

  @doc """
  Checks if a status transition is valid.
  """
  @spec valid_transition?(t(), t()) :: boolean()
  def valid_transition?(%__MODULE__{value: :pending}, %__MODULE__{value: new_status})
      when new_status in [:approved, :denied, :expired],
      do: true

  def valid_transition?(%__MODULE__{value: :approved}, %__MODULE__{value: :expired}), do: true

  def valid_transition?(%__MODULE__{}, %__MODULE__{}), do: false

  @doc """
  Checks if the status is terminal (no further transitions allowed).
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{value: status}) when status in [:denied, :expired], do: true
  def terminal?(%__MODULE__{}), do: false

  @doc """
  Checks if the status allows contact sharing.
  """
  @spec allows_contact_sharing?(t()) :: boolean()
  def allows_contact_sharing?(%__MODULE__{value: :approved}), do: true
  def allows_contact_sharing?(%__MODULE__{}), do: false

  @doc """
  Returns all valid status values.
  """
  @spec valid_statuses() :: [atom()]
  def valid_statuses, do: @valid_statuses
end