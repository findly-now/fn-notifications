defmodule FnNotifications.Domain.Services.BulkheadService do
  @moduledoc """
  Bulkhead pattern implementation to isolate resource pools for different operations.
  Prevents cascading failures by limiting resource consumption per operation type.
  """

  use GenServer
  require Logger

  @type operation_type :: :email_delivery | :sms_delivery | :whatsapp_delivery | :event_processing
  @type resource_pool :: %{
    max_concurrency: pos_integer(),
    current_count: non_neg_integer(),
    waiting_queue: :queue.queue(),
    timeout_ms: pos_integer()
  }

  @default_pools %{
    email_delivery: %{max_concurrency: 10, current_count: 0, waiting_queue: :queue.new(), timeout_ms: 30_000},
    sms_delivery: %{max_concurrency: 5, current_count: 0, waiting_queue: :queue.new(), timeout_ms: 15_000},
    whatsapp_delivery: %{max_concurrency: 5, current_count: 0, waiting_queue: :queue.new(), timeout_ms: 15_000},
    event_processing: %{max_concurrency: 20, current_count: 0, waiting_queue: :queue.new(), timeout_ms: 10_000}
  }

  @doc """
  Starts the bulkhead service with configured resource pools.
  """
  def start_link(opts \\ []) do
    pools = Keyword.get(opts, :pools, @default_pools)
    GenServer.start_link(__MODULE__, pools, name: __MODULE__)
  end

  @doc """
  Executes a function within the specified resource pool.
  Returns {:error, :pool_exhausted} if pool is at capacity and queue is full.
  """
  @spec execute(operation_type(), (() -> any())) :: {:ok, any()} | {:error, :pool_exhausted | :timeout | String.t()}
  def execute(operation_type, fun) when is_function(fun, 0) do
    case acquire_resource(operation_type) do
      {:ok, ref} ->
        try do
          result = fun.()
          release_resource(operation_type, ref)
          {:ok, result}
        rescue
          error ->
            release_resource(operation_type, ref)
            {:error, "Execution failed: #{inspect(error)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets current pool statistics for monitoring.
  """
  @spec get_pool_stats() :: map()
  def get_pool_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Gets stats for a specific pool.
  """
  @spec get_pool_stats(operation_type()) :: map()
  def get_pool_stats(operation_type) do
    GenServer.call(__MODULE__, {:get_pool_stats, operation_type})
  end

  ## GenServer Callbacks

  @impl true
  def init(pools) do
    Logger.info("Starting BulkheadService with pools: #{inspect(Map.keys(pools))}")
    {:ok, pools}
  end

  @impl true
  def handle_call({:acquire_resource, operation_type}, from, pools) do
    case Map.get(pools, operation_type) do
      nil ->
        {:reply, {:error, :unknown_operation_type}, pools}

      pool ->
        if pool.current_count < pool.max_concurrency do
          # Resource available, grant immediately
          ref = make_ref()
          updated_pool = %{pool | current_count: pool.current_count + 1}
          updated_pools = Map.put(pools, operation_type, updated_pool)

          Logger.debug("Resource acquired for #{operation_type}, count: #{updated_pool.current_count}/#{pool.max_concurrency}")
          {:reply, {:ok, ref}, updated_pools}
        else
          # Pool exhausted, add to waiting queue
          updated_queue = :queue.in({from, make_ref()}, pool.waiting_queue)
          updated_pool = %{pool | waiting_queue: updated_queue}
          updated_pools = Map.put(pools, operation_type, updated_pool)

          Logger.warning("Pool #{operation_type} exhausted, adding to queue. Queue size: #{:queue.len(updated_queue)}")
          {:noreply, updated_pools}
        end
    end
  end

  @impl true
  def handle_call({:release_resource, operation_type, _ref}, _from, pools) do
    case Map.get(pools, operation_type) do
      nil ->
        {:reply, :ok, pools}

      pool ->
        updated_pool = %{pool | current_count: max(0, pool.current_count - 1)}

        # Check if there are waiting requests
        case :queue.out(pool.waiting_queue) do
          {{:value, {waiting_from, waiting_ref}}, remaining_queue} ->
            # Grant resource to waiting request
            final_pool = %{updated_pool |
              current_count: updated_pool.current_count + 1,
              waiting_queue: remaining_queue
            }
            updated_pools = Map.put(pools, operation_type, final_pool)

            GenServer.reply(waiting_from, {:ok, waiting_ref})
            Logger.debug("Resource released and granted to waiting request for #{operation_type}")
            {:reply, :ok, updated_pools}

          {:empty, _} ->
            # No waiting requests
            updated_pools = Map.put(pools, operation_type, updated_pool)
            Logger.debug("Resource released for #{operation_type}, count: #{updated_pool.current_count}/#{pool.max_concurrency}")
            {:reply, :ok, updated_pools}
        end
    end
  end

  @impl true
  def handle_call(:get_stats, _from, pools) do
    stats = Enum.into(pools, %{}, fn {operation_type, pool} ->
      {operation_type, %{
        max_concurrency: pool.max_concurrency,
        current_count: pool.current_count,
        queue_length: :queue.len(pool.waiting_queue),
        utilization: pool.current_count / pool.max_concurrency
      }}
    end)

    {:reply, stats, pools}
  end

  @impl true
  def handle_call({:get_pool_stats, operation_type}, _from, pools) do
    case Map.get(pools, operation_type) do
      nil ->
        {:reply, {:error, :unknown_operation_type}, pools}

      pool ->
        stats = %{
          max_concurrency: pool.max_concurrency,
          current_count: pool.current_count,
          queue_length: :queue.len(pool.waiting_queue),
          utilization: pool.current_count / pool.max_concurrency
        }
        {:reply, {:ok, stats}, pools}
    end
  end

  ## Private Functions

  defp acquire_resource(operation_type) do
    GenServer.call(__MODULE__, {:acquire_resource, operation_type}, 5_000)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  defp release_resource(operation_type, ref) do
    GenServer.call(__MODULE__, {:release_resource, operation_type, ref})
  end
end