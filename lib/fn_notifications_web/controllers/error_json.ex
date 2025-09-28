defmodule FnNotificationsWeb.ErrorJSON do
  @moduledoc """
  JSON error response handler for API endpoints.
  """
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
