defmodule JidoOSDevWeb.RepoPodLive do
  use JidoOSDevWeb, :live_view

  alias JidoOSDev.{ObservabilityLog, RepoWorkspace}

  @demo_task %{
    title: "Trace the repo pod workflow",
    goal:
      "Explain how the planner, coder, and reviewer collaborate inside this durable repo pod and which repo-aware tools each stage relies on."
  }

  @signal_limit 140

  @workflow_steps [
    %{
      key: :plan,
      kind: "planner",
      label: "Plan",
      title: "Planner reads repo state",
      description: "Ground the task in repo status, current files, and the selected pod context."
    },
    %{
      key: :draft,
      kind: "coder",
      label: "Draft",
      title: "Coder proposes implementation",
      description:
        "Turn the plan into a concrete patch outline or pseudo-diff against the checkout."
    },
    %{
      key: :review,
      kind: "reviewer",
      label: "Review",
      title: "Reviewer pressure-tests the draft",
      description: "Call out risks, missing tests, and correctness gaps before real edits happen."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      ObservabilityLog.subscribe()
    end

    default_pod_id = RepoWorkspace.default_pod_id()
    default_repo_path = RepoWorkspace.default_repo_path()

    {:ok,
     socket
     |> assign(:page_title, "AgentOS Coding Workflow")
     |> assign(:pod_id_input, default_pod_id)
     |> assign(:repo_path_input, default_repo_path)
     |> assign(:task_title_input, "")
     |> assign(:task_goal_input, "")
     |> assign(:chat_prompt_input, "")
     |> assign(:chat_histories, %{})
     |> assign(:chat_history, [])
     |> assign(:signal_entries, [])
     |> assign(:active_pod_id, nil)
     |> assign(:known_pods, [])
     |> assign(:kernel_status, %{})
     |> assign(:configured_pod, nil)
     |> assign(:pod_runtime, %{node_snapshots: []})
     |> assign(:repo, empty_repo_state(default_repo_path))
     |> assign(:task_board, %{tasks: [], active_task_id: nil, activity_log: []})
     |> assign(:specialists, %{})
     |> assign(:ai_ready, RepoWorkspace.ai_ready?())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    pod_id =
      params["pod_id"]
      |> blank_to_nil()
      |> Kernel.||(RepoWorkspace.default_pod_id())

    {:noreply, refresh_assigns(socket, pod_id)}
  end

  @impl true
  def handle_info({:signal_log, entry}, socket) do
    if relevant_signal?(entry, socket.assigns.active_pod_id) do
      {:noreply,
       assign(
         socket,
         :signal_entries,
         [entry | socket.assigns.signal_entries] |> Enum.take(@signal_limit)
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "set-pod-form",
        %{"pod" => %{"id" => pod_id, "repo_path" => repo_path}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:pod_id_input, pod_id)
     |> assign(:repo_path_input, repo_path)}
  end

  def handle_event("ensure-pod", %{"pod" => %{"id" => pod_id, "repo_path" => repo_path}}, socket) do
    pod_id = normalize_input(pod_id)
    repo_path = normalize_input(repo_path)

    case RepoWorkspace.ensure_pod(pod_id, repo_path) do
      {:ok, _pid} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ensured repo pod #{pod_id}.")
         |> assign(:pod_id_input, pod_id)
         |> assign(:repo_path_input, repo_path)
         |> push_patch(to: pod_path(pod_id))}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to ensure repo pod: #{format_reason(reason)}")
         |> assign(:pod_id_input, pod_id)
         |> assign(:repo_path_input, repo_path)
         |> refresh_assigns(socket.assigns.active_pod_id)}
    end
  end

  def handle_event("select-pod", %{"id" => pod_id}, socket) do
    {:noreply, push_patch(socket, to: pod_path(pod_id))}
  end

  def handle_event("refresh-repo", _params, %{assigns: %{active_pod_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Create or select a pod before syncing the repo.")}
  end

  def handle_event("refresh-repo", _params, socket) do
    repo_path = socket.assigns.repo_path_input

    case RepoWorkspace.sync_repo(socket.assigns.active_pod_id, repo_path) do
      {:ok, _repo} ->
        {:noreply,
         socket
         |> put_flash(:info, "Repo scan complete.")
         |> refresh_assigns(socket.assigns.active_pod_id)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Repo scan failed: #{format_reason(reason)}")
         |> refresh_assigns(socket.assigns.active_pod_id)}
    end
  end

  def handle_event("set-task-form", %{"task" => %{"title" => title, "goal" => goal}}, socket) do
    {:noreply,
     socket
     |> assign(:task_title_input, title)
     |> assign(:task_goal_input, goal)}
  end

  def handle_event("add-task", %{"task" => %{"title" => title, "goal" => goal}}, socket) do
    queue_task(socket, title, goal)
  end

  def handle_event("queue-demo-task", _params, socket) do
    queue_task(socket, @demo_task.title, @demo_task.goal)
  end

  def handle_event("set-chat-form", %{"chat" => %{"prompt" => prompt}}, socket) do
    {:noreply, assign(socket, :chat_prompt_input, prompt)}
  end

  def handle_event(
        "ask-pod",
        %{"chat" => %{"prompt" => prompt}},
        %{assigns: %{active_pod_id: nil}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:chat_prompt_input, prompt)
     |> put_flash(:error, "Create or select a pod before asking the assistant.")}
  end

  def handle_event("ask-pod", %{"chat" => %{"prompt" => prompt}}, socket) do
    prompt = normalize_input(prompt)

    case RepoWorkspace.chat_with_pod(socket.assigns.active_pod_id, prompt) do
      {:ok, %{answer: answer, tool_events: tool_events}} ->
        {:noreply,
         socket
         |> assign(:chat_prompt_input, "")
         |> append_chat_messages(socket.assigns.active_pod_id, [
           chat_message("user", prompt),
           chat_message("assistant", answer, tool_events)
         ])
         |> put_flash(:info, "Assistant responded.")
         |> refresh_assigns(socket.assigns.active_pod_id)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:chat_prompt_input, prompt)
         |> put_flash(:error, "Assistant request failed: #{format_reason(reason)}")
         |> refresh_assigns(socket.assigns.active_pod_id)}
    end
  end

  def handle_event("queue-chat-task", _params, %{assigns: %{active_pod_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Create or select a pod before queueing work.")}
  end

  def handle_event("queue-chat-task", _params, socket) do
    prompt = normalize_input(socket.assigns.chat_prompt_input)

    case prompt do
      "" ->
        {:noreply, put_flash(socket, :error, "Write a chat prompt before queueing it as a task.")}

      _prompt ->
        queue_task(socket, prompt_title(prompt), prompt)
    end
  end

  def handle_event("select-task", %{"id" => task_id}, socket) do
    case RepoWorkspace.select_task(socket.assigns.active_pod_id, task_id) do
      {:ok, _task_board} ->
        {:noreply,
         socket
         |> put_flash(:info, "Selected task #{task_id}.")
         |> refresh_assigns(socket.assigns.active_pod_id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to select task: #{format_reason(reason)}")}
    end
  end

  def handle_event("run-workflow", %{"task-id" => task_id}, socket) do
    case RepoWorkspace.run_workflow(socket.assigns.active_pod_id, task_id) do
      {:ok, _outputs} ->
        {:noreply,
         socket
         |> put_flash(:info, "Completed planner, coder, and reviewer passes.")
         |> refresh_assigns(socket.assigns.active_pod_id)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Workflow run failed: #{format_reason(reason)}")
         |> refresh_assigns(socket.assigns.active_pod_id)}
    end
  end

  def handle_event("run-specialist", %{"kind" => kind, "task-id" => task_id}, socket) do
    result =
      case kind do
        "planner" -> RepoWorkspace.plan_task(socket.assigns.active_pod_id, task_id)
        "coder" -> RepoWorkspace.draft_task(socket.assigns.active_pod_id, task_id)
        "reviewer" -> RepoWorkspace.review_task(socket.assigns.active_pod_id, task_id)
        _other -> {:error, :unknown_specialist}
      end

    case result do
      {:ok, _output} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{String.capitalize(kind)} run completed.")
         |> refresh_assigns(socket.assigns.active_pod_id)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "#{String.capitalize(kind)} run failed: #{format_reason(reason)}")
         |> refresh_assigns(socket.assigns.active_pod_id)}
    end
  end

  def handle_event("wake-specialist", %{"name" => name}, socket) do
    specialist = String.to_existing_atom(name)

    case RepoWorkspace.wake_specialist(socket.assigns.active_pod_id, specialist) do
      {:ok, _pid} ->
        {:noreply,
         socket
         |> put_flash(:info, "Started #{name}.")
         |> refresh_assigns(socket.assigns.active_pod_id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to start #{name}: #{format_reason(reason)}")}
    end
  end

  def handle_event("reconcile-pod", _params, socket) do
    case RepoWorkspace.reconcile_pod(socket.assigns.active_pod_id) do
      {:ok, _report} ->
        {:noreply,
         socket
         |> put_flash(:info, "Reconciled eager agents.")
         |> refresh_assigns(socket.assigns.active_pod_id)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Pod reconcile failed: #{format_reason(reason)}")
         |> refresh_assigns(socket.assigns.active_pod_id)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <% active_task = active_task(@task_board) %>

    <div class="workflow-shell">
      <div class="workflow-page">
        <section class="panel topbar">
          <div>
            <p class="eyebrow topbar-eyebrow">Repo pod demo</p>
            <h1>AgentOS Coding Workflow</h1>
            <p class="muted topbar-copy">
              Short chat for repo questions, an explicit workflow lane for real work, and a live signal log for the runtime.
            </p>
          </div>

          <div class="summary-pills">
            <span class="pill">kernel: <%= @kernel_status.kernel_name || "jido_os_dev" %></span>
            <span class="pill">pod: <%= @active_pod_id || "not started" %></span>
            <span class="pill">branch: <%= @repo.branch || "not scanned" %></span>
            <span class="pill">changed: <%= @repo.changed_count %></span>
            <span class="pill">ai: <%= if @ai_ready, do: "ready", else: "offline" %></span>
            <span class="pill">task: <%= @task_board.active_task_id || "none" %></span>
          </div>
        </section>

        <%= if Phoenix.Flash.get(@flash, :info) do %>
          <div class="flash info"><%= Phoenix.Flash.get(@flash, :info) %></div>
        <% end %>

        <%= if Phoenix.Flash.get(@flash, :error) do %>
          <div class="flash error"><%= Phoenix.Flash.get(@flash, :error) %></div>
        <% end %>

        <div class="workspace-grid compact">
          <main class="workspace-main">
            <section class="panel stack">
              <div class="section-head">
                <div>
                  <p class="eyebrow dark">Interactive entry</p>
                  <h2>Ask the Pod</h2>
                </div>
                <span class="pill">assistant: repo-aware</span>
              </div>

              <p class="muted">
                Use the chat for short questions. When the prompt turns into real work, queue it directly onto the task board.
              </p>

              <div class="chat-thread">
                <%= if @chat_history == [] do %>
                  <div class="blank-state compact">
                    <h3>No chat yet</h3>
                    <p>Ask a quick repo question, or queue the same prompt as a coding task.</p>
                  </div>
                <% else %>
                  <%= for message <- @chat_history do %>
                    <article class={["chat-message", message.role]}>
                      <div class="chat-head">
                        <span class="pill"><%= String.capitalize(message.role) %></span>
                        <span class="muted"><%= message.at %></span>
                      </div>

                      <div class="artifact compact">
                        <pre><%= message.content %></pre>
                      </div>

                      <%= if message.tool_events != [] do %>
                        <div class="tool-trail">
                          <%= for event <- message.tool_events do %>
                            <span class="tool-pill">
                              <%= event.tool_name %> <%= event.stage %><%= duration_suffix(event.duration_ms) %>
                            </span>
                          <% end %>
                        </div>
                      <% end %>
                    </article>
                  <% end %>
                <% end %>
              </div>

              <.form for={%{}} as={:chat} phx-change="set-chat-form" phx-submit="ask-pod">
                <div class="stack">
                  <div class="field">
                    <label for="chat-prompt">Prompt</label>
                    <textarea id="chat-prompt" name="chat[prompt]"><%= @chat_prompt_input %></textarea>
                  </div>

                  <div class="button-row">
                    <button
                      class="primary"
                      type="submit"
                      phx-disable-with="Asking pod..."
                      disabled={is_nil(@active_pod_id) or not @ai_ready}
                    >
                      Ask Pod
                    </button>
                    <button
                      class="secondary"
                      type="button"
                      phx-click="queue-chat-task"
                      disabled={is_nil(@active_pod_id)}
                    >
                      Queue as Task
                    </button>
                    <button
                      class="secondary"
                      type="button"
                      phx-click="queue-demo-task"
                      disabled={is_nil(@active_pod_id)}
                    >
                      Use Demo Task
                    </button>
                  </div>
                </div>
              </.form>

              <%= unless @ai_ready do %>
                <p class="muted">
                  Set `OPENAI_API_KEY` in `.env` if you want the assistant and specialists to execute real `Jido.AI.Agent` passes.
                </p>
              <% end %>
            </section>

            <section class="panel stack">
              <div class="section-head">
                <div>
                  <p class="eyebrow dark">Execution</p>
                  <h2>Workflow Lane</h2>
                </div>

                <%= if active_task do %>
                  <button
                    class="primary"
                    type="button"
                    phx-click="run-workflow"
                    phx-value-task-id={active_task.id}
                    phx-disable-with="Running workflow..."
                    disabled={not @ai_ready}
                  >
                    Run Full Pass
                  </button>
                <% end %>
              </div>

              <%= if active_task do %>
                <div class="selected-task">
                  <div>
                    <span class="pill"><%= active_task.status %></span>
                    <h3><%= active_task.title %></h3>
                    <p><%= active_task.goal %></p>
                  </div>

                  <div class="selected-task-meta">
                    <span class="pill">task: <%= active_task.id %></span>
                    <span class="pill">updated: <%= active_task.updated_at %></span>
                  </div>
                </div>

                <div class="stage-grid compact">
                  <%= for step <- task_workflow_steps(active_task, @ai_ready) do %>
                    <article class={["stage-card", stage_state_class(step.state)]}>
                      <div class="stage-head">
                        <div>
                          <h3><%= step.title %></h3>
                          <p class="muted"><%= step.description %></p>
                        </div>
                        <span class="pill"><%= state_label(step.state) %></span>
                      </div>

                      <div class="button-row">
                        <button
                          class="secondary"
                          type="button"
                          phx-click="run-specialist"
                          phx-value-kind={step.kind}
                          phx-value-task-id={active_task.id}
                          phx-disable-with={"Running #{step.label}..."}
                          disabled={not @ai_ready}
                        >
                          Run <%= step.label %>
                        </button>
                      </div>

                      <%= if present?(step.content) do %>
                        <div class="artifact artifact-scroll">
                          <strong><%= step.label %> output</strong>
                          <pre><%= step.content %></pre>
                        </div>
                      <% else %>
                        <p class="muted">
                          <%= if step.state == :waiting_ai do %>
                            Configure `OPENAI_API_KEY` to execute this specialist.
                          <% else %>
                            No output captured for this stage yet.
                          <% end %>
                        </p>
                      <% end %>
                    </article>
                  <% end %>
                </div>
              <% else %>
                <div class="blank-state">
                  <h3>No task selected</h3>
                  <p>Queue work from the chat composer or the task board to activate the workflow lane.</p>
                  <button
                    class="primary"
                    type="button"
                    phx-click="queue-demo-task"
                    disabled={is_nil(@active_pod_id)}
                  >
                    Queue Demo Task
                  </button>
                </div>
              <% end %>
            </section>
          </main>

          <aside class="control-rail">
            <section class="panel stack">
              <div class="section-head">
                <div>
                  <p class="eyebrow dark">Setup</p>
                  <h2>Pod Workspace</h2>
                </div>
                <span class="pill">topology: <%= @configured_pod && @configured_pod.topology_name || "repo_pod" %></span>
              </div>

              <.form for={%{}} as={:pod} phx-change="set-pod-form" phx-submit="ensure-pod">
                <div class="stack">
                  <div class="field">
                    <label for="pod-id">Pod ID</label>
                    <input id="pod-id" name="pod[id]" value={@pod_id_input} />
                  </div>

                  <div class="field">
                    <label for="repo-path">Repo Path</label>
                    <input id="repo-path" name="pod[repo_path]" value={@repo_path_input} />
                  </div>

                  <div class="button-row">
                    <button class="primary" type="submit" phx-disable-with="Ensuring pod...">
                      Ensure Repo Pod
                    </button>
                    <button class="secondary" type="button" phx-click="refresh-repo">
                      Sync Repo
                    </button>
                  </div>
                </div>
              </.form>

              <div class="repo-summary">
                <div>
                  <span class="card-label">Repo</span>
                  <strong><%= @repo.repo_name || Path.basename(@repo_path_input) %></strong>
                </div>
                <div>
                  <span class="card-label">Head</span>
                  <strong><%= @repo.head || "n/a" %></strong>
                </div>
                <div>
                  <span class="card-label">Files</span>
                  <strong><%= @repo.file_count %></strong>
                </div>
                <div>
                  <span class="card-label">Dirty</span>
                  <strong><%= @repo.dirty %></strong>
                </div>
              </div>

              <div class="file-list compact">
                <%= if @repo.changed_files == [] do %>
                  <span class="muted">No changed files in the checkout.</span>
                <% else %>
                  <%= for file <- Enum.take(@repo.changed_files, 8) do %>
                    <span class="file-pill"><%= file %></span>
                  <% end %>
                <% end %>
              </div>

              <div class="pill-list">
                <%= if @known_pods == [] do %>
                  <span class="muted">No pods started yet.</span>
                <% else %>
                  <%= for pod_id <- @known_pods do %>
                    <button
                      class={["secondary", selected_pod?(pod_id, @active_pod_id) && "selected"]}
                      type="button"
                      phx-click="select-pod"
                      phx-value-id={pod_id}
                    >
                      <%= pod_id %>
                    </button>
                  <% end %>
                <% end %>
              </div>
            </section>

            <section class="panel stack">
              <div class="section-head">
                <div>
                  <p class="eyebrow dark">Task board</p>
                  <h2>Queue and Select Work</h2>
                </div>
                <span class="pill">active: <%= @task_board.active_task_id || "none" %></span>
              </div>

              <.form for={%{}} as={:task} phx-change="set-task-form" phx-submit="add-task">
                <div class="stack">
                  <div class="field">
                    <label for="task-title">Task Title</label>
                    <input id="task-title" name="task[title]" value={@task_title_input} />
                  </div>

                  <div class="field">
                    <label for="task-goal">Task Goal</label>
                    <textarea id="task-goal" name="task[goal]"><%= @task_goal_input %></textarea>
                  </div>

                  <div class="button-row">
                    <button class="primary" type="submit" phx-disable-with="Queueing task...">
                      Queue Task
                    </button>
                    <button class="secondary" type="button" phx-click="queue-demo-task">
                      Use Demo Prompt
                    </button>
                  </div>
                </div>
              </.form>

              <div class="task-list compact">
                <%= if @task_board.tasks == [] do %>
                  <div class="muted">No tasks queued yet.</div>
                <% else %>
                  <%= for task <- @task_board.tasks do %>
                    <article class={["task-card", task.id == @task_board.active_task_id && "selected"]}>
                      <div class="task-card-head">
                        <div>
                          <strong><%= task.title %></strong>
                          <p class="muted"><%= task.goal %></p>
                        </div>
                        <span class="pill"><%= task.status %></span>
                      </div>

                      <div class="pill-row">
                        <span class="pill">task: <%= task.id %></span>
                        <span class="pill"><%= artifact_count(task) %> outputs</span>
                      </div>

                      <div class="button-row">
                        <button class="secondary" type="button" phx-click="select-task" phx-value-id={task.id}>
                          Select
                        </button>
                        <button
                          class="secondary"
                          type="button"
                          phx-click="run-workflow"
                          phx-value-task-id={task.id}
                          disabled={not @ai_ready}
                        >
                          Run Full Pass
                        </button>
                      </div>
                    </article>
                  <% end %>
                <% end %>
              </div>
            </section>

            <details class="panel advanced-shell">
              <summary>Advanced Runtime</summary>

              <div class="advanced-content stack">
                <section class="stack">
                  <div class="section-head">
                    <div>
                      <p class="eyebrow dark">Maintenance</p>
                      <h3>Raw AgentOS Verbs</h3>
                    </div>
                  </div>

                  <div class="button-row">
                    <button class="secondary" type="button" phx-click="reconcile-pod">
                      Reconcile Eager Agents
                    </button>
                    <button class="secondary" type="button" phx-click="wake-specialist" phx-value-name="assistant">
                      Wake Assistant
                    </button>
                    <button class="secondary" type="button" phx-click="wake-specialist" phx-value-name="planner">
                      Wake Planner
                    </button>
                    <button class="secondary" type="button" phx-click="wake-specialist" phx-value-name="coder">
                      Wake Coder
                    </button>
                    <button class="secondary" type="button" phx-click="wake-specialist" phx-value-name="reviewer">
                      Wake Reviewer
                    </button>
                  </div>
                </section>

                <section class="stack">
                  <div class="section-head">
                    <div>
                      <p class="eyebrow dark">Specialists</p>
                      <h3>Agent State</h3>
                    </div>
                  </div>

                  <div class="node-grid compact">
                    <%= for {name, specialist} <- sorted_specialists(@specialists) do %>
                      <article class="node-card compact">
                        <div class="node-head">
                          <h3><%= name %></h3>
                          <span class="pill"><%= if specialist.running, do: "running", else: "idle" %></span>
                        </div>
                        <div class="muted">completed: <%= specialist.completed %></div>
                        <%= if present?(specialist.last_query) do %>
                          <div class="artifact compact artifact-scroll">
                            <strong>Last query</strong>
                            <pre><%= specialist.last_query %></pre>
                          </div>
                        <% end %>
                        <%= if present?(specialist.last_answer) do %>
                          <div class="artifact compact artifact-scroll">
                            <strong>Last answer</strong>
                            <pre><%= specialist.last_answer %></pre>
                          </div>
                        <% end %>
                      </article>
                    <% end %>
                  </div>
                </section>

                <section class="stack">
                  <div class="section-head">
                    <div>
                      <p class="eyebrow dark">Runtime</p>
                      <h3>Pod Nodes</h3>
                    </div>
                    <span class="pill"><%= length(@pod_runtime.node_snapshots || []) %> nodes</span>
                  </div>

                  <div class="node-grid compact">
                    <%= for node <- @pod_runtime.node_snapshots do %>
                      <article class="node-card compact">
                        <div class="node-head">
                          <h3><%= node.name %></h3>
                          <span class="pill"><%= node.status %></span>
                        </div>
                        <div class="muted">activation: <%= node.activation %></div>
                        <div class="muted">manager: <%= node.manager %></div>
                      </article>
                    <% end %>
                  </div>
                </section>

                <section class="stack">
                  <div class="section-head">
                    <div>
                      <p class="eyebrow dark">Activity</p>
                      <h3>Workflow Feed</h3>
                    </div>
                  </div>

                  <div class="event-list compact">
                    <%= if @task_board.activity_log == [] do %>
                      <div class="muted">No pod activity recorded yet.</div>
                    <% else %>
                      <%= for event <- @task_board.activity_log do %>
                        <article class="artifact compact">
                          <strong><%= event.kind %></strong>
                          <div class="muted"><%= event.at %></div>
                          <div><%= event.message %></div>
                        </article>
                      <% end %>
                    <% end %>
                  </div>
                </section>
              </div>
            </details>
          </aside>
        </div>

        <section class="panel stack signal-dock">
          <div class="section-head">
            <div>
              <p class="eyebrow dark">Observability</p>
              <h2>Signal Log</h2>
            </div>
            <span class="pill">live tail</span>
          </div>

          <div class="signal-list">
            <%= if @signal_entries == [] do %>
              <div class="muted">No signals captured yet for this pod.</div>
            <% else %>
              <%= for entry <- @signal_entries do %>
                <article class={["signal-row", Atom.to_string(entry.family)]}>
                  <div class="signal-row-head">
                    <div class="signal-row-meta">
                      <span class="pill"><%= signal_family_label(entry.family) %></span>
                      <%= if entry.pod_id do %>
                        <span class="pill">pod: <%= entry.pod_id %></span>
                      <% end %>
                      <%= if entry.duration_ms do %>
                        <span class="pill"><%= entry.duration_ms %> ms</span>
                      <% end %>
                    </div>
                    <span class="muted"><%= entry.at %></span>
                  </div>

                  <strong><%= entry.summary %></strong>

                  <div class="signal-row-detail">
                    <%= if entry.signal_type do %>
                      <span>signal: <%= entry.signal_type %></span>
                    <% end %>
                    <%= if entry.tool_name do %>
                      <span>tool: <%= entry.tool_name %></span>
                    <% end %>
                    <%= if entry.agent_id do %>
                      <span>agent: <%= entry.agent_id %></span>
                    <% end %>
                    <%= if entry.request_id do %>
                      <span>request: <%= entry.request_id %></span>
                    <% end %>
                    <span>event: <%= entry.event %></span>
                  </div>
                </article>
              <% end %>
            <% end %>
          </div>
        </section>
      </div>
    </div>
    """
  end

  defp queue_task(%{assigns: %{active_pod_id: nil}} = socket, _title, _goal) do
    {:noreply, put_flash(socket, :error, "Create or select a pod before queuing tasks.")}
  end

  defp queue_task(socket, title, goal) do
    case RepoWorkspace.add_task(socket.assigns.active_pod_id, title, goal) do
      {:ok, _task_board} ->
        {:noreply,
         socket
         |> put_flash(:info, "Queued coding task.")
         |> assign(:task_title_input, "")
         |> assign(:task_goal_input, "")
         |> refresh_assigns(socket.assigns.active_pod_id)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Unable to queue task: #{format_reason(reason)}")
         |> assign(:task_title_input, title)
         |> assign(:task_goal_input, goal)
         |> refresh_assigns(socket.assigns.active_pod_id)}
    end
  end

  defp refresh_assigns(socket, pod_id) do
    known_pods = RepoWorkspace.list_pods()
    active_pod_id = if pod_id in known_pods, do: pod_id, else: nil
    chat_history = pod_chat_history(socket.assigns[:chat_histories] || %{}, active_pod_id)
    signal_entries = load_signal_entries(active_pod_id)

    case active_pod_id && RepoWorkspace.pod_overview(active_pod_id) do
      {:ok, overview} ->
        socket
        |> assign(:known_pods, known_pods)
        |> assign(:active_pod_id, active_pod_id)
        |> assign(:kernel_status, overview.kernel)
        |> assign(:configured_pod, overview.configured_pod)
        |> assign(:pod_runtime, overview.pod)
        |> assign(:repo, overview.repo)
        |> assign(:task_board, overview.task_board)
        |> assign(:specialists, overview.specialists)
        |> assign(:ai_ready, overview.ai_ready)
        |> assign(:chat_history, chat_history)
        |> assign(:signal_entries, signal_entries)

      _ ->
        socket
        |> assign(:known_pods, known_pods)
        |> assign(:active_pod_id, nil)
        |> assign(:kernel_status, RepoWorkspace.kernel_status())
        |> assign(:configured_pod, RepoWorkspace.configured_pod())
        |> assign(:pod_runtime, %{node_snapshots: []})
        |> assign(:repo, empty_repo_state(socket.assigns[:repo_path_input]))
        |> assign(:task_board, %{tasks: [], active_task_id: nil, activity_log: []})
        |> assign(:specialists, %{})
        |> assign(:ai_ready, RepoWorkspace.ai_ready?())
        |> assign(:chat_history, chat_history)
        |> assign(:signal_entries, signal_entries)
    end
  end

  defp empty_repo_state(path) do
    %{
      repo_path: path,
      repo_name: path |> to_string() |> Path.basename(),
      branch: nil,
      head: nil,
      dirty: false,
      changed_files: [],
      file_count: 0,
      changed_count: 0,
      last_scan_at: nil
    }
  end

  defp append_chat_messages(socket, nil, _messages), do: socket

  defp append_chat_messages(socket, pod_id, messages) do
    histories = socket.assigns[:chat_histories] || %{}

    updated_history =
      histories
      |> Map.get(pod_id, [])
      |> Kernel.++(messages)
      |> Enum.take(-8)

    histories = Map.put(histories, pod_id, updated_history)

    socket
    |> assign(:chat_histories, histories)
    |> assign(:chat_history, updated_history)
  end

  defp pod_chat_history(_histories, nil), do: []
  defp pod_chat_history(histories, pod_id), do: Map.get(histories, pod_id, [])

  defp load_signal_entries(nil), do: ObservabilityLog.list_entries(limit: @signal_limit)

  defp load_signal_entries(pod_id) do
    scoped = ObservabilityLog.list_entries(limit: @signal_limit, pod_id: pod_id)

    if scoped == [] do
      ObservabilityLog.list_entries(limit: @signal_limit)
    else
      scoped
    end
  end

  defp relevant_signal?(_entry, nil), do: true
  defp relevant_signal?(%{pod_id: nil}, _active_pod_id), do: true
  defp relevant_signal?(%{pod_id: pod_id}, active_pod_id), do: pod_id == active_pod_id

  defp chat_message(role, content, tool_events \\ []) do
    %{
      id: System.unique_integer([:positive]),
      role: role,
      content: content,
      at: now_iso(),
      tool_events: tool_events
    }
  end

  defp now_iso do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp active_task(%{tasks: tasks, active_task_id: task_id}) when is_list(tasks) do
    Enum.find(tasks, &(&1.id == task_id))
  end

  defp active_task(_task_board), do: nil

  defp task_workflow_steps(nil, ai_ready) do
    Enum.map(@workflow_steps, fn step ->
      Map.put(step, :state, if(ai_ready, do: :idle, else: :waiting_ai))
      |> Map.put(:content, nil)
    end)
  end

  defp task_workflow_steps(task, ai_ready) do
    {steps, _next_open?} =
      Enum.map_reduce(@workflow_steps, true, fn step, next_open? ->
        content = Map.get(task, step.key)
        complete? = present?(content)

        state =
          cond do
            complete? -> :complete
            next_open? and ai_ready -> :next
            next_open? -> :waiting_ai
            true -> :blocked
          end

        {Map.put(step, :content, content) |> Map.put(:state, state), next_open? and complete?}
      end)

    steps
  end

  defp sorted_specialists(specialists) do
    Enum.sort_by(specialists, fn {name, _specialist} -> Atom.to_string(name) end)
  end

  defp artifact_count(task) do
    Enum.count([task.plan, task.draft, task.review], &present?/1)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp state_label(:complete), do: "complete"
  defp state_label(:next), do: "next"
  defp state_label(:blocked), do: "blocked"
  defp state_label(:waiting_ai), do: "needs AI"
  defp state_label(:idle), do: "idle"

  defp stage_state_class(:complete), do: "complete"
  defp stage_state_class(:next), do: "next"
  defp stage_state_class(:blocked), do: "blocked"
  defp stage_state_class(:waiting_ai), do: "waiting"
  defp stage_state_class(:idle), do: "idle"

  defp selected_pod?(pod_id, active_pod_id), do: pod_id == active_pod_id

  defp signal_family_label(:signal), do: "signal"
  defp signal_family_label(:ai_request), do: "request"
  defp signal_family_label(:ai_tool), do: "tool"
  defp signal_family_label(:ai_llm), do: "llm"
  defp signal_family_label(_other), do: "event"

  defp duration_suffix(nil), do: ""
  defp duration_suffix(duration_ms), do: " (#{duration_ms} ms)"

  defp prompt_title(prompt) do
    prompt
    |> String.split(~r/[.!?\n]/, parts: 2)
    |> List.first()
    |> blank_to_nil()
    |> case do
      nil ->
        "Follow up from pod chat"

      title ->
        title
        |> String.slice(0, 68)
        |> String.trim()
    end
  end

  defp pod_path(pod_id), do: "/pods/#{pod_id}"

  defp normalize_input(value), do: value |> to_string() |> String.trim()

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
