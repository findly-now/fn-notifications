defmodule FnNotifications.Repo do
  @moduledoc """
  Ecto repository for PostgreSQL database operations.
  """

  use Ecto.Repo,
    otp_app: :fn_notifications,
    adapter: Ecto.Adapters.Postgres
end
