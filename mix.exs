defmodule YProcess.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project do
    [app: :y_process,
     version: @version,
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: description,
     package: package,
     docs: docs,
     deps: deps]
  end

  def application do
    [applications: []]
  end

  defp deps do
    [{:phoenix_pubsub, "~> 1.0"},
     {:earmark, ">= 0.0.0", only: :dev},
     {:ex_doc, "~> 0.12", only: :dev},
     {:credo, "~> 0.4.5", only: [:dev, :docs]},
     {:inch_ex, ">= 0.0.0", only: [:dev, :docs]}]
  end

  defp docs do
    [source_url: "https://github.com/gmtprime/y_process",
     source_ref: "v#{@version}",
     main: YProcess]
  end

  defp description do
    """
    GenServer wrapper behaviour for pub/sub between processes using pg2 and
    Phoenix pub/sub (with any adapter) and a behaviour to create custom
    pub/sub backends.
    """
  end

  defp package do
    [maintainers: ["Alexander de Sousa"],
     licenses: ["MIT"],
     links: %{"Github" => "https://github.com/gmtprime/y_process"}]
  end
end
