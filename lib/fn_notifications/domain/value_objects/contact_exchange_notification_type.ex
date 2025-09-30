defmodule FnNotifications.Domain.ValueObjects.ContactExchangeNotificationType do
  @moduledoc """
  Contact Exchange Notification Type Value Object

  Represents the type of notification in the contact exchange workflow.
  Each type corresponds to a specific step in the secure contact sharing process
  and determines who receives the notification and what content is included.

  ## Notification Types

  - `request_received`: Sent to post owner when someone requests their contact info
  - `approval_granted`: Sent to requester when owner approves contact sharing
  - `denial_sent`: Sent to requester when owner denies contact sharing
  - `expiration_notice`: Sent when contact exchange expires (request or approved sharing)

  ## Target Recipients

  - `request_received` → Post owner
  - `approval_granted` → Requester
  - `denial_sent` → Requester
  - `expiration_notice` → Both (separate notifications)
  """

  defstruct [:value]

  @type t :: %__MODULE__{value: atom()}

  @valid_types [:request_received, :approval_granted, :denial_sent, :expiration_notice]

  @doc """
  Creates a request received notification type.
  """
  @spec request_received() :: t()
  def request_received, do: %__MODULE__{value: :request_received}

  @doc """
  Creates an approval granted notification type.
  """
  @spec approval_granted() :: t()
  def approval_granted, do: %__MODULE__{value: :approval_granted}

  @doc """
  Creates a denial sent notification type.
  """
  @spec denial_sent() :: t()
  def denial_sent, do: %__MODULE__{value: :denial_sent}

  @doc """
  Creates an expiration notice notification type.
  """
  @spec expiration_notice() :: t()
  def expiration_notice, do: %__MODULE__{value: :expiration_notice}

  @doc """
  Creates a notification type from a string value.
  """
  @spec from_string(String.t()) :: {:ok, t()} | {:error, :invalid_type}
  def from_string(type_string) when is_binary(type_string) do
    type_atom = String.to_existing_atom(type_string)

    if type_atom in @valid_types do
      {:ok, %__MODULE__{value: type_atom}}
    else
      {:error, :invalid_type}
    end
  rescue
    ArgumentError -> {:error, :invalid_type}
  end

  @doc """
  Converts the notification type to a string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{value: value}), do: Atom.to_string(value)

  @doc """
  Determines the target recipient for this notification type.
  """
  @spec target_recipient(t()) :: :owner | :requester
  def target_recipient(%__MODULE__{value: :request_received}), do: :owner
  def target_recipient(%__MODULE__{value: :approval_granted}), do: :requester
  def target_recipient(%__MODULE__{value: :denial_sent}), do: :requester
  def target_recipient(%__MODULE__{value: :expiration_notice}), do: :requester

  @doc """
  Checks if this notification type includes contact information.
  """
  @spec includes_contact_info?(t()) :: boolean()
  def includes_contact_info?(%__MODULE__{value: :approval_granted}), do: true
  def includes_contact_info?(%__MODULE__{}), do: false

  @doc """
  Checks if this notification type is urgent (requires immediate delivery).
  """
  @spec urgent?(t()) :: boolean()
  def urgent?(%__MODULE__{value: :approval_granted}), do: true
  def urgent?(%__MODULE__{value: :denial_sent}), do: true
  def urgent?(%__MODULE__{}), do: false

  @doc """
  Gets the default notification template for this type.
  """
  @spec default_template(t()) :: String.t()
  def default_template(%__MODULE__{value: :request_received}), do: "contact_exchange_request"
  def default_template(%__MODULE__{value: :approval_granted}), do: "contact_exchange_approved"
  def default_template(%__MODULE__{value: :denial_sent}), do: "contact_exchange_denied"
  def default_template(%__MODULE__{value: :expiration_notice}), do: "contact_exchange_expired"

  @doc """
  Returns all valid notification type values.
  """
  @spec valid_types() :: [atom()]
  def valid_types, do: @valid_types
end