defmodule YProcess.Mixfile do
  use Mix.Project

  @version "0.0.1"

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
    [{:earmark, ">= 0.0.0", only: :dev},
     {:ex_doc, "~> 0.11", only: :dev},
     {:credo, "~> 0.4", only: [:dev, :docs]},
     {:inch_ex, ">= 0.0.0", only: [:dev, :docs]}]
  end

  defp docs do
    [source_url: "https://github.com/gmtprime/y_process",
     source_ref: "v#{@version}",
     main: YProcess]
  end

  defp description do
    """
    GenServer wrapper behaviour for pubsub between processes.
    """
  end

  defp package do
    [maintainers: ["Alexander de Sousa"],
     licenses: ["MIT"],
     links: %{"Github" => "https://github.com/gmtprime/y_process"}]
  end
end
