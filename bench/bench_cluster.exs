Code.require_file("server.exs", "./bench/support")
Application.ensure_all_started(:gen_metrics)

data = Enum.map(1..1_000_000, fn i -> %{id: i, data: String.duplicate("a", 100)} end)

{:ok, _untraced} = UntracedServer.start_link(length(data))
{:ok, _traced}   = TracedServer.start_link(length(data))
{:ok, _sampled}  = SampledServer.start_link(length(data))

alias GenMetrics.GenServer.Cluster
traced_cluster = %Cluster{name: "traced_cluster",
                          servers: [TracedServer],
                          opts: [statistics: false,
                                 sample_rate: 1.0,
                                 synchronous: true]}
sampled_cluster = %Cluster{name: "sampled_cluster",
                          servers: [SampledServer],
                          opts: [statistics: false,
                                 sample_rate: 0.1,
                                 synchronous: true]}

:observer.start

Benchee.run(%{time: 30, warmup: 5}, %{
      "untraced-server [ call ]" => fn ->
          UntracedServer.init_state(length(data))
          pid = self()
          for item <- data do
            UntracedServer.do_call(%{item | id: pid})
          end
          receive do
            :benchmark_completed -> :ok
          end
      end,
      "traced---server [ call ]" => fn ->
        {:ok, tpid} = GenMetrics.monitor_cluster(traced_cluster)
        TracedServer.init_state(length(data))
        pid = self()
        for item <- data do
          TracedServer.do_call(%{item | id: pid})
        end
        receive do
          :benchmark_completed -> :ok
        end
        Process.exit(tpid, :shutdown)
      end,
      "sampled--server [ call ]" => fn ->
        {:ok, spid} = GenMetrics.monitor_cluster(sampled_cluster)
        SampledServer.init_state(length(data))
        pid = self()
        for item <- data do
          SampledServer.do_call(%{item | id: pid})
        end
        receive do
          :benchmark_completed -> :ok
        end
        Process.exit(spid, :shutdown)
      end
})
