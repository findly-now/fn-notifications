defmodule FnNotificationsWeb.ErrorHTML do
  @moduledoc """
  HTML error response handler for web requests.
  """
  use FnNotificationsWeb, :html
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
