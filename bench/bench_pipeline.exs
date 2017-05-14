Code.require_file("stages.exs", "./bench/support")
Application.ensure_all_started(:gen_metrics)
alias GenMetrics.GenStage.Pipeline

data = Enum.map(1..1_000_000, fn i -> %{id: i, data: String.duplicate("a", 100)} end)

{:ok, _untracedp} = UntracedProducer.start_link()
{:ok, _untracedc} = UntracedConsumer.start_link()
{:ok, _tracedp} = TracedProducer.start_link()
{:ok, _tracedc} = TracedConsumer.start_link()
{:ok, _sampledp} = SampledProducer.start_link()
{:ok, _sampledc} = SampledConsumer.start_link()

traced_pipeline = %Pipeline{name: "traced_pipeline",
                            producer: [TracedProducer],
                            consumer: [TracedConsumer],
                            opts: [statistics: false,
                                   synchronous: true,
                                   sample_rate: 1.0]}

sampled_pipeline = %Pipeline{name: "sampled_pipeline",
                             producer: [SampledProducer],
                             consumer: [SampledConsumer],
                             opts: [statistics: false,
                                    synchronous: true,
                                    sample_rate: 0.1]}

:observer.start

Benchee.run(%{time: 30, warmup: 5}, %{
      "untraced-pipeline [max_demand: 1]" => fn ->
        for %{id: id} = item <- data do
          {:ok, ^id} = UntracedProducer.emit(item)
        end
        for i <- 1..length(data) do
          receive do
            ^i -> :ok
          end
        end
      end,
      "traced---pipeline [max_demand: 1]" => fn ->
        {:ok, traced} = GenMetrics.monitor_pipeline(traced_pipeline)
        for %{id: id} = item <- data do
          {:ok, ^id} = TracedProducer.emit(item)
        end
        for i <- 1..length(data) do
          receive do
            ^i -> :ok
          end
        end
        Process.exit(traced, :shutdown)
      end,
      "sampled--pipeline [max_demand: 1]" => fn ->
        {:ok, sampled} = GenMetrics.monitor_pipeline(sampled_pipeline)
        for %{id: id} = item <- data do
          {:ok, ^id} = SampledProducer.emit(item)
        end
        for i <- 1..length(data) do
          receive do
            ^i -> :ok
          end
        end
        Process.exit(sampled, :shutdown)
      end
})
