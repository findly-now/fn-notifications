ExUnit.start()

# Tests use cloud database - schema should already be deployed
# Run `make deploy-schema-postgres` to deploy schema to cloud test database

# Load schema using Ecto with shared mode for setup
if File.exists?("schema.sql") do
  try do
    schema_content = File.read!("schema.sql")
    statements = String.split(schema_content, ";")

    # Use shared mode temporarily for schema loading
    Ecto.Adapters.SQL.Sandbox.mode(FnNotifications.Repo, {:shared, self()})

    Enum.each(statements, fn sql ->
      case String.trim(sql) do
        "" -> :ok
        query ->
          try do
            Ecto.Adapters.SQL.query!(FnNotifications.Repo, query)
          rescue
            e -> IO.puts("Warning: Failed to execute query: #{inspect(e)}")
          end
      end
    end)

    IO.puts("Schema loaded successfully for tests")
  rescue
    e -> IO.puts("Warning: Failed to load schema: #{inspect(e)}")
  end
end

# Set sandbox mode for tests
Ecto.Adapters.SQL.Sandbox.mode(FnNotifications.Repo, :manual)
