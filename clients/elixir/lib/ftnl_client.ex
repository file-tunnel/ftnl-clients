defmodule FtnlClient do
  @moduledoc "Dependency-light File Tunnel API transport."

  defstruct [:base_url, :token, timeout: 30_000]

  @type t :: %__MODULE__{base_url: String.t(), token: String.t() | nil, timeout: pos_integer()}

  @spec new(String.t(), keyword()) :: t()
  def new(base_url, options \\ []) do
    %__MODULE__{base_url: String.trim_trailing(base_url, "/"), token: Keyword.get(options, :token), timeout: Keyword.get(options, :timeout, 30_000)}
  end

  @spec health(t()) :: {:ok, term()} | {:error, term()}
  def health(client), do: request(client, :get, "/health")

  @spec request(t(), atom(), String.t(), binary() | nil) :: {:ok, term()} | {:error, term()}
  def request(client, method, path, body \\ nil) do
    :inets.start()
    :ssl.start()
    url = String.to_charlist(client.base_url <> "/" <> String.trim_leading(path, "/"))
    headers = [{~c"accept", ~c"application/json"}] ++ if(client.token, do: [{~c"authorization", String.to_charlist("Bearer " <> client.token)}], else: [])
    request = if body, do: {url, [{~c"content-type", ~c"application/json"} | headers], ~c"application/json", body}, else: {url, headers}
    :httpc.request(method, request, [timeout: client.timeout], body_format: :binary)
  end
end
