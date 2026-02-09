defmodule KamalOps.Secrets do
  @moduledoc """
  Ops-friendly secrets loading without printing secret values.

  Uses `Dotenvy` so we parse the same Kamal secrets file format.
  """

  @spec load_file!(String.t()) :: %{optional(String.t()) => String.t()}
  def load_file!(path) when is_binary(path) do
    if not File.exists?(path) do
      raise Mix.Error, "Missing secrets file: #{path}"
    end

    case Dotenvy.source([path]) do
      {:ok, envs} ->
        # Last wins if duplicated.
        Map.new(envs)

      {:error, reason} ->
        raise Mix.Error, "Failed to load secrets file #{path}: #{inspect(reason)}"
    end
  end

  @spec get!(map(), String.t()) :: String.t()
  def get!(secrets, key) when is_map(secrets) and is_binary(key) do
    case Map.get(secrets, key) do
      nil -> raise Mix.Error, "Missing required secret key: #{key}"
      "" -> raise Mix.Error, "Secret key is present but blank: #{key}"
      value -> value
    end
  end

  @spec get(map(), String.t(), String.t() | nil) :: String.t() | nil
  def get(secrets, key, default \\ nil) when is_map(secrets) and is_binary(key) do
    case Map.get(secrets, key) do
      nil -> default
      "" -> default
      value -> value
    end
  end
end
