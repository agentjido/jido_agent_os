defmodule JidoOSDev.ObservabilityLog do
  @moduledoc """
  Host-level observability adapter for the Phoenix dev example.

  `Jido.AgentOS`, the sample `RepoPod`, and `JidoOSDev.RepoWorkspace` already
  do the real work. This module exists so the Phoenix shell has a stable,
  UI-friendly place to consume runtime events without pushing that concern into
  the kernel, the pod topology, or the public workflow service.

  In this example repo, `ObservabilityLog` does three small jobs:

  - attach to Jido/JidoAI telemetry events
  - normalize those events into a bounded in-memory log
  - broadcast new entries over PubSub so LiveView can tail them

  It is intentionally separate from the task board activity feed:

  - activity feed: short, human workflow history tied to tasks
  - signal log: lower-level runtime and AI event stream for observability

  It is also intentionally outside `Jido.AgentOS` because it is not a kernel
  primitive. It is host-app glue for this Phoenix example: the LiveView signal
  dock uses it to tail runtime events, and the repo workspace uses it to record
  a few app-level workflow events next to the underlying telemetry stream.

  If this demo did not need a live signal dock or replayable tool traces, this
  module could disappear and the host could listen to telemetry directly. The
  reason it stays separate here is that the UI needs more than raw telemetry:
  subscription, filtering, replay since a cursor, and a compact normalized shape.
  """

  use GenServer

  @topic "signal_log"
  @handler_id "jido-os-dev-signal-log"
  @default_limit 120
  @max_entries 1_200

  @typedoc """
  Normalized signal-log entry consumed by the Phoenix host.
  """
  @type entry :: %{
          required(:seq) => non_neg_integer(),
          required(:at) => String.t(),
          required(:family) => atom(),
          required(:stage) => String.t(),
          required(:event) => String.t(),
          optional(:pod_id) => String.t() | nil,
          optional(:agent_id) => String.t() | nil,
          optional(:agent_module) => String.t() | nil,
          optional(:signal_type) => String.t() | nil,
          optional(:request_id) => String.t() | nil,
          optional(:run_id) => String.t() | nil,
          optional(:tool_name) => String.t() | nil,
          optional(:model) => String.t() | nil,
          optional(:operation) => String.t() | nil,
          optional(:termination_reason) => String.t() | nil,
          optional(:error_type) => String.t() | nil,
          optional(:directive_count) => integer() | nil,
          optional(:duration_ms) => integer() | nil,
          required(:summary) => String.t(),
          required(:details) => map()
        }

  @events [
    [:jido, :agent_server, :signal, :start],
    [:jido, :agent_server, :signal, :stop],
    [:jido, :agent_server, :signal, :exception],
    [:jido, :ai, :request, :start],
    [:jido, :ai, :request, :complete],
    [:jido, :ai, :request, :failed],
    [:jido, :ai, :request, :cancelled],
    [:jido, :ai, :tool, :start],
    [:jido, :ai, :tool, :complete],
    [:jido, :ai, :tool, :error],
    [:jido, :ai, :tool, :timeout],
    [:jido, :ai, :tool, :retry],
    [:jido, :ai, :llm, :start],
    [:jido, :ai, :llm, :complete],
    [:jido, :ai, :llm, :error]
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribe the caller to live signal-log entries over Phoenix PubSub.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(JidoOSDev.PubSub, @topic)
  end

  @doc """
  Append one app-level entry to the log.

  This is used for high-level host events that do not naturally fall out of the
  telemetry stream, such as "pod ensured" or "assistant answered a repo question."
  """
  def record(attrs) when is_map(attrs) do
    GenServer.cast(__MODULE__, {:manual, attrs})
  end

  @doc """
  Return the current monotonically increasing cursor for replay.
  """
  def current_seq do
    GenServer.call(__MODULE__, :current_seq)
  end

  @doc """
  Return the newest entries, optionally filtered by pod, agent, request, or family.
  """
  @spec list_entries(keyword()) :: [entry()]
  def list_entries(opts \\ []) do
    GenServer.call(__MODULE__, {:list_entries, opts})
  end

  @doc """
  Return entries added after the given cursor, optionally filtered.
  """
  @spec entries_since(non_neg_integer(), keyword()) :: [entry()]
  def entries_since(seq, opts \\ []) do
    GenServer.call(__MODULE__, {:entries_since, seq, opts})
  end

  @doc false
  def handle_telemetry(event_name, measurements, metadata, _config) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:telemetry, event_name, measurements, metadata})
    end

    :ok
  end

  @impl true
  def init(opts) do
    max_entries = Keyword.get(opts, :max_entries, @max_entries)

    _ = :telemetry.detach(@handler_id)
    :ok = :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_telemetry/4, nil)

    {:ok, %{entries: [], seq: 0, max_entries: max_entries}}
  end

  @impl true
  def handle_call(:current_seq, _from, state) do
    {:reply, state.seq, state}
  end

  def handle_call({:list_entries, opts}, _from, state) do
    entries =
      state.entries
      |> filter_entries(opts)
      |> Enum.take(Keyword.get(opts, :limit, @default_limit))

    {:reply, entries, state}
  end

  def handle_call({:entries_since, seq, opts}, _from, state) do
    entries =
      state.entries
      |> Enum.filter(&(&1.seq > seq))
      |> filter_entries(opts)
      |> Enum.reverse()

    entries =
      case Keyword.get(opts, :limit) do
        nil -> entries
        limit -> Enum.take(entries, limit)
      end

    {:reply, entries, state}
  end

  @impl true
  def handle_cast({:telemetry, event_name, measurements, metadata}, state) do
    seq = state.seq + 1
    entry = normalize_entry(seq, event_name, measurements, metadata)
    {:noreply, push_entry(state, seq, entry)}
  end

  def handle_cast({:manual, attrs}, state) do
    seq = state.seq + 1
    entry = manual_entry(seq, attrs)
    {:noreply, push_entry(state, seq, entry)}
  end

  defp filter_entries(entries, opts) do
    Enum.filter(entries, fn entry ->
      matches_filter?(entry, :pod_id, Keyword.get(opts, :pod_id)) and
        matches_filter?(entry, :agent_id, Keyword.get(opts, :agent_id)) and
        matches_filter?(entry, :request_id, Keyword.get(opts, :request_id)) and
        matches_family?(entry, Keyword.get(opts, :family, :all))
    end)
  end

  defp matches_filter?(_entry, _field, nil), do: true
  defp matches_filter?(entry, field, value), do: Map.get(entry, field) == value

  defp matches_family?(_entry, :all), do: true
  defp matches_family?(entry, family), do: entry.family == family

  defp normalize_entry(seq, event_name, measurements, metadata) do
    family = family(event_name)
    stage = event_name |> List.last() |> Atom.to_string()
    event = Enum.map_join(event_name, ".", &Atom.to_string/1)
    duration_ms = duration_ms(measurements)
    pod_id = pod_id_from_partition(Map.get(metadata, :jido_partition))
    agent_id = stringify(Map.get(metadata, :agent_id))
    signal_type = stringify(Map.get(metadata, :signal_type))
    tool_name = stringify(Map.get(metadata, :tool_name))
    request_id = stringify(Map.get(metadata, :request_id))

    %{
      seq: seq,
      at: timestamp_iso(measurements),
      family: family,
      stage: stage,
      event: event,
      pod_id: pod_id,
      agent_id: agent_id,
      agent_module: module_name(Map.get(metadata, :agent_module)),
      signal_type: signal_type,
      request_id: request_id,
      run_id: stringify(Map.get(metadata, :run_id)),
      tool_name: tool_name,
      model: stringify(Map.get(metadata, :model)),
      operation: stringify(Map.get(metadata, :operation)),
      termination_reason: stringify(Map.get(metadata, :termination_reason)),
      error_type: error_type(metadata),
      directive_count: Map.get(metadata, :directive_count),
      duration_ms: duration_ms,
      summary:
        summarize(family, stage, agent_id, signal_type, tool_name, request_id, duration_ms),
      details: %{
        event: event,
        agent_module: module_name(Map.get(metadata, :agent_module)),
        directive_types: stringify(Map.get(metadata, :directive_types)),
        measurements: normalize_map(measurements),
        metadata:
          metadata
          |> Map.take([
            :agent_id,
            :signal_type,
            :request_id,
            :run_id,
            :tool_name,
            :model,
            :operation,
            :termination_reason,
            :error_type,
            :jido_partition
          ])
          |> normalize_map()
      }
    }
  end

  defp manual_entry(seq, attrs) do
    family = Map.get(attrs, :family, :signal)
    stage = attrs |> Map.get(:stage, "event") |> stringify() |> blank("event")
    event = attrs |> Map.get(:event, "manual.event") |> stringify() |> blank("manual.event")
    agent_id = attrs |> Map.get(:agent_id) |> stringify()
    tool_name = attrs |> Map.get(:tool_name) |> stringify()
    request_id = attrs |> Map.get(:request_id) |> stringify()
    duration_ms = Map.get(attrs, :duration_ms)
    signal_type = attrs |> Map.get(:signal_type) |> stringify()

    %{
      seq: seq,
      at: now_iso(),
      family: family,
      stage: stage,
      event: event,
      pod_id: attrs |> Map.get(:pod_id) |> stringify(),
      agent_id: agent_id,
      agent_module: attrs |> Map.get(:agent_module) |> stringify(),
      signal_type: signal_type,
      request_id: request_id,
      run_id: attrs |> Map.get(:run_id) |> stringify(),
      tool_name: tool_name,
      model: attrs |> Map.get(:model) |> stringify(),
      operation: attrs |> Map.get(:operation) |> stringify(),
      termination_reason: attrs |> Map.get(:termination_reason) |> stringify(),
      error_type: attrs |> Map.get(:error_type) |> stringify(),
      directive_count: Map.get(attrs, :directive_count),
      duration_ms: duration_ms,
      summary:
        Map.get(
          attrs,
          :summary,
          summarize(family, stage, agent_id, signal_type, tool_name, request_id, duration_ms)
        ),
      details: normalize_map(Map.get(attrs, :details, %{}))
    }
  end

  defp family([:jido, :agent_server, :signal, _]), do: :signal
  defp family([:jido, :ai, :request, _]), do: :ai_request
  defp family([:jido, :ai, :tool, _]), do: :ai_tool
  defp family([:jido, :ai, :llm, _]), do: :ai_llm
  defp family(_other), do: :other

  defp summarize(:signal, stage, agent_id, signal_type, _tool_name, _request_id, duration_ms) do
    base = "#{blank(signal_type, "signal")} #{stage} on #{blank(agent_id, "agent")}"

    case duration_ms do
      nil -> base
      ms -> "#{base} (#{ms} ms)"
    end
  end

  defp summarize(:ai_tool, stage, agent_id, _signal_type, tool_name, request_id, duration_ms) do
    base =
      "#{blank(tool_name, "tool")} #{stage} for #{blank(agent_id, "assistant")}" <>
        request_suffix(request_id)

    case duration_ms do
      nil -> base
      ms -> "#{base} (#{ms} ms)"
    end
  end

  defp summarize(:ai_request, stage, agent_id, _signal_type, _tool_name, request_id, duration_ms) do
    base = "request #{stage} for #{blank(agent_id, "assistant")}" <> request_suffix(request_id)

    case duration_ms do
      nil -> base
      ms -> "#{base} (#{ms} ms)"
    end
  end

  defp summarize(:ai_llm, stage, agent_id, _signal_type, _tool_name, request_id, duration_ms) do
    base = "llm #{stage} for #{blank(agent_id, "assistant")}" <> request_suffix(request_id)

    case duration_ms do
      nil -> base
      ms -> "#{base} (#{ms} ms)"
    end
  end

  defp summarize(_family, stage, agent_id, _signal_type, _tool_name, _request_id, _duration_ms) do
    "#{stage} on #{blank(agent_id, "agent")}"
  end

  defp request_suffix(nil), do: ""
  defp request_suffix(""), do: ""
  defp request_suffix(request_id), do: " req=#{request_id}"

  defp push_entry(state, seq, entry) do
    entries =
      [entry | state.entries]
      |> Enum.take(state.max_entries)

    Phoenix.PubSub.broadcast(JidoOSDev.PubSub, @topic, {:signal_log, entry})

    %{state | entries: entries, seq: seq}
  end

  defp timestamp_iso(%{system_time: system_time}) when is_integer(system_time) do
    system_time
    |> System.convert_time_unit(:native, :millisecond)
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_iso8601()
  rescue
    _error -> now_iso()
  end

  defp timestamp_iso(_measurements), do: now_iso()

  defp now_iso do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp duration_ms(%{duration_ms: duration_ms}) when is_integer(duration_ms), do: duration_ms

  defp duration_ms(%{duration: duration}) when is_integer(duration) do
    System.convert_time_unit(duration, :native, :millisecond)
  end

  defp duration_ms(_measurements), do: nil

  defp normalize_map(map) when map == %{}, do: %{}

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)
  end

  defp module_name(nil), do: nil
  defp module_name(module) when is_atom(module), do: module |> Module.split() |> List.last()
  defp module_name(_module), do: nil

  defp pod_id_from_partition({:agent_os_kernel_pod, _kernel_name, pod_id}) when is_binary(pod_id),
    do: pod_id

  defp pod_id_from_partition({_kind, _scope, pod_id}) when is_binary(pod_id), do: pod_id
  defp pod_id_from_partition(partition), do: stringify(partition)

  defp error_type(metadata) do
    metadata[:error_type] || metadata[:kind] || metadata[:error]
  end

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_number(value), do: to_string(value)
  defp stringify(value), do: inspect(value)

  defp blank(nil, fallback), do: fallback
  defp blank("", fallback), do: fallback
  defp blank(value, _fallback), do: value
end
