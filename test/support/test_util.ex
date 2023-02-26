defmodule Flop.TestUtil do
  @moduledoc false

  import Ecto.Query
  import Flop.Factory

  alias Ecto.Adapters.SQL.Sandbox
  alias Flop.Fruit
  alias Flop.Pet
  alias Flop.Repo

  def checkin_checkout do
    :ok = Sandbox.checkin(Repo)
    :ok = Sandbox.checkout(Repo)
  end

  @doc """
  Takes a list of items and applies filter operators on the list using
  `Enum.filter/2`.

  The function supports regular fields, join fields and compound fields. The
  associations need to be preloaded if join fields are used.
  """
  def filter_items(items, field, op, value \\ nil)

  def filter_items([], _, _, _), do: []

  def filter_items([%module{} = struct | _] = items, field, op, value)
      when is_atom(field) do
    case Flop.Schema.field_type(struct, field) do
      {:join, %{ecto_type: ecto_type}} = field_type
      when not is_nil(ecto_type) ->
        filter_func = matches?(op, value, ecto_type)

        Enum.filter(items, fn item ->
          item |> get_field(field_type) |> filter_func.()
        end)

      {type, _opts} = field_type when type in [:normal, :join] ->
        ecto_type = module.__schema__(:type, field)
        filter_func = matches?(op, value, ecto_type)

        Enum.filter(items, fn item ->
          item |> get_field(field_type) |> filter_func.()
        end)

      {:compound, fields} ->
        Enum.filter(
          items,
          &apply_filter_to_compound_fields(&1, fields, op, value)
        )
    end
  end

  defp apply_filter_to_compound_fields(_pet, _fields, op, _value)
       when op in [
              :==,
              :=~,
              :<=,
              :<,
              :>=,
              :>,
              :in,
              :not_in,
              :contains,
              :not_contains
            ] do
    # joined_field_value =
    #   fields
    #   |> Enum.map(&Flop.Schema.field_type(%Pet{}, &1))
    #   |> Enum.map(&get_field(pet, &1))
    #   |> Enum.map(&String.split/1)
    #   |> Enum.concat()
    #   |> Enum.join(" ")

    # joined_query_value = value |> String.split() |> Enum.join(" ")
    # matches?(op, joined_query_value).(joined_field_value)
    true
  end

  defp apply_filter_to_compound_fields(pet, fields, :empty, value) do
    filter_func = matches?(:empty, value)

    Enum.all?(fields, fn field ->
      field_type = Flop.Schema.field_type(%Pet{}, field)
      pet |> get_field(field_type) |> filter_func.()
    end)
  end

  defp apply_filter_to_compound_fields(pet, fields, op, value) do
    filter_func = matches?(op, value)

    Enum.any?(fields, fn field ->
      field_type = Flop.Schema.field_type(%Pet{}, field)
      pet |> get_field(field_type) |> filter_func.()
    end)
  end

  defp get_field(pet, {:normal, field}), do: Map.fetch!(pet, field)

  defp get_field(pet, {:join, %{path: [a, b]}}),
    do: pet |> Map.fetch!(a) |> Map.fetch!(b)

  defp matches?(op, v, _), do: matches?(op, v)
  defp matches?(:==, v), do: &(&1 == v)
  defp matches?(:!=, v), do: &(&1 != v)
  defp matches?(:empty, _), do: &empty?(&1)
  defp matches?(:not_empty, _), do: &(!empty?(&1))
  defp matches?(:<=, v), do: &(&1 <= v)
  defp matches?(:<, v), do: &(&1 < v)
  defp matches?(:>, v), do: &(&1 > v)
  defp matches?(:>=, v), do: &(&1 >= v)
  defp matches?(:in, v), do: &(&1 in v)
  defp matches?(:not_in, v), do: &(&1 not in v)
  defp matches?(:contains, v), do: &(v in &1)
  defp matches?(:not_contains, v), do: &(v not in &1)
  defp matches?(:like, v), do: &(&1 =~ v)
  defp matches?(:not_like, v), do: &(&1 =~ v == false)
  defp matches?(:=~, v), do: matches?(:ilike, v)

  defp matches?(:ilike, v) do
    v = String.downcase(v)
    &(String.downcase(&1) =~ v)
  end

  defp matches?(:not_ilike, v) do
    v = String.downcase(v)
    &(String.downcase(&1) =~ v == false)
  end

  defp matches?(:like_and, v) when is_binary(v) do
    values = String.split(v)
    &Enum.all?(values, fn v -> &1 =~ v end)
  end

  defp matches?(:like_and, v), do: &Enum.all?(v, fn v -> &1 =~ v end)

  defp matches?(:like_or, v) when is_binary(v) do
    values = String.split(v)
    &Enum.any?(values, fn v -> &1 =~ v end)
  end

  defp matches?(:like_or, v), do: &Enum.any?(v, fn v -> &1 =~ v end)

  defp matches?(:ilike_and, v) when is_binary(v) do
    values = v |> String.downcase() |> String.split()
    &Enum.all?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:ilike_and, v) do
    values = Enum.map(v, &String.downcase/1)
    &Enum.all?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:ilike_or, v) when is_binary(v) do
    values = v |> String.downcase() |> String.split()
    &Enum.any?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:ilike_or, v) do
    values = Enum.map(v, &String.downcase/1)
    &Enum.any?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp empty?(nil), do: true
  defp empty?([]), do: true
  defp empty?(map) when map == %{}, do: true
  defp empty?(_), do: false

  @doc """
  Inserts a list of items using `Flop.Factory` and sorts the list by `:id`
  field.
  """
  def insert_list_and_sort(count, factory, args \\ []) do
    count |> insert_list(factory, args) |> Enum.sort_by(& &1.id)
  end

  @doc """
  Query that returns all pets with owners joined and preloaded.
  """
  def pets_with_owners_query do
    Pet
    |> join(:left, [p], o in assoc(p, :owner), as: :owner)
    |> preload(:owner)
  end

  @doc """
  Queries all pets using `Flop.all`. Preloads the owners and sorts by Pet ID.
  """
  def query_pets_with_owners(params, opts \\ []) do
    flop =
      Flop.validate!(params,
        for: Pet,
        max_limit: 999_999_999,
        default_limit: 999_999_999
      )

    sort? = opts[:sort] || true

    q =
      Pet
      |> join(:left, [p], o in assoc(p, :owner), as: :owner)
      |> preload(:owner)

    q = if sort?, do: order_by(q, [p], p.id), else: q

    opts = opts |> Keyword.take([:extra_opts]) |> Keyword.put(:for, Pet)

    Flop.all(q, flop, opts)
  end

  @doc """
  Queries all fruits using `Flop.all`. Preloads the owners and sorts by
  Fruit ID.
  """
  def query_fruits_with_owners(params, opts \\ []) do
    flop =
      Flop.validate!(params,
        for: Fruit,
        max_limit: 999_999_999,
        default_limit: 999_999_999
      )

    sort? = opts[:sort] || true

    q =
      Fruit
      |> join(:left, [f], o in assoc(f, :owner), as: :owner)
      |> preload(:owner)

    q = if sort?, do: order_by(q, [p], p.id), else: q
    opts = opts |> Keyword.take([:extra_opts]) |> Keyword.put(:for, Fruit)
    Flop.all(q, flop, opts)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  Brought to you by Phoenix.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
