defmodule FnNotificationsWeb.Plugs.CorrelationId do
  @moduledoc """
  Plug for handling correlation IDs in HTTP requests.

  Extracts correlation ID from headers or generates a new one if not present.
  Sets the correlation ID in Logger metadata for structured logging.
  """

  import Plug.Conn
  require Logger

  @correlation_id_header "x-correlation-id"

  def init(opts), do: opts

  def call(conn, _opts) do
    correlation_id =
      conn
      |> get_req_header(@correlation_id_header)
      |> List.first()
      |> case do
        nil -> UUID.uuid4()
        existing_id when is_binary(existing_id) and byte_size(existing_id) > 0 -> existing_id
        _ -> UUID.uuid4()
      end

    # Set correlation ID in response headers
    conn = put_resp_header(conn, @correlation_id_header, correlation_id)

    # Set correlation ID in Logger metadata for structured logging
    Logger.metadata(correlation_id: correlation_id)

    # Store in connection assigns for access in controllers
    assign(conn, :correlation_id, correlation_id)
  end
end
