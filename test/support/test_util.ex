defmodule Flop.TestUtil do
  @moduledoc false

  import Ecto.Query
  import Flop.Factory

  alias Ecto.Adapters.SQL.Sandbox
  alias Flop.FieldInfo
  alias Flop.Repo
  alias MyApp.Fruit
  alias MyApp.Pet

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
  def filter_items(items, field, op, value \\ nil, ecto_adapter \\ nil)

  def filter_items([], _, _, _, _), do: []

  def filter_items(
        [struct | _] = items,
        field,
        op,
        value,
        ecto_adapter
      )
      when is_atom(field) do
    case Flop.Schema.field_info(struct, field) do
      %FieldInfo{ecto_type: ecto_type, extra: %{type: :join}} = field_info
      when not is_nil(ecto_type) ->
        filter_func = matches?(op, value, ecto_adapter)

        Enum.filter(items, fn item ->
          item |> get_field(field_info) |> filter_func.()
        end)

      %FieldInfo{extra: %{type: type}} = field_info
      when type in [:normal, :join] ->
        filter_func = matches?(op, value, ecto_adapter)

        Enum.filter(items, fn item ->
          item |> get_field(field_info) |> filter_func.()
        end)

      %FieldInfo{extra: %{type: :compound, fields: fields}} ->
        Enum.filter(
          items,
          &apply_filter_to_compound_fields(&1, fields, op, value, ecto_adapter)
        )
    end
  end

  defp apply_filter_to_compound_fields(_pet, _fields, op, _value, _ecto_adapter)
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
    true
  end

  defp apply_filter_to_compound_fields(pet, fields, :empty, value, ecto_adapter) do
    filter_func = matches?(:empty, value, ecto_adapter)

    Enum.all?(fields, fn field ->
      field_info = Flop.Schema.field_info(%Pet{}, field)
      pet |> get_field(field_info) |> filter_func.()
    end)
  end

  defp apply_filter_to_compound_fields(
         pet,
         fields,
         :like_and,
         value,
         ecto_adapter
       ) do
    value = if is_binary(value), do: String.split(value), else: value

    Enum.all?(value, fn substring ->
      filter_func = matches?(:like, substring, ecto_adapter)

      Enum.any?(fields, fn field ->
        field_info = Flop.Schema.field_info(%Pet{}, field)
        pet |> get_field(field_info) |> filter_func.()
      end)
    end)
  end

  defp apply_filter_to_compound_fields(
         pet,
         fields,
         :ilike_and,
         value,
         ecto_adapter
       ) do
    value = if is_binary(value), do: String.split(value), else: value

    Enum.all?(value, fn substring ->
      filter_func = matches?(:ilike, substring, ecto_adapter)

      Enum.any?(fields, fn field ->
        field_info = Flop.Schema.field_info(%Pet{}, field)
        pet |> get_field(field_info) |> filter_func.()
      end)
    end)
  end

  defp apply_filter_to_compound_fields(
         pet,
         fields,
         :like_or,
         value,
         ecto_adapter
       ) do
    value = if is_binary(value), do: String.split(value), else: value

    Enum.any?(value, fn substring ->
      filter_func = matches?(:like, substring, ecto_adapter)

      Enum.any?(fields, fn field ->
        field_info = Flop.Schema.field_info(%Pet{}, field)
        pet |> get_field(field_info) |> filter_func.()
      end)
    end)
  end

  defp apply_filter_to_compound_fields(
         pet,
         fields,
         :ilike_or,
         value,
         ecto_adapter
       ) do
    value = if is_binary(value), do: String.split(value), else: value

    Enum.any?(value, fn substring ->
      filter_func = matches?(:ilike, substring, ecto_adapter)

      Enum.any?(fields, fn field ->
        field_info = Flop.Schema.field_info(%Pet{}, field)
        pet |> get_field(field_info) |> filter_func.()
      end)
    end)
  end

  defp apply_filter_to_compound_fields(pet, fields, op, value, ecto_adapter) do
    filter_func = matches?(op, value, ecto_adapter)

    Enum.any?(fields, fn field ->
      field_info = Flop.Schema.field_info(%Pet{}, field)
      pet |> get_field(field_info) |> filter_func.()
    end)
  end

  defp get_field(pet, %FieldInfo{extra: %{type: :normal, field: field}}),
    do: Map.fetch!(pet, field)

  defp get_field(pet, %FieldInfo{extra: %{type: :join, path: [a, b]}}),
    do: pet |> Map.fetch!(a) |> Map.fetch!(b)

  defp matches?(:==, v, _), do: &(&1 == v)
  defp matches?(:!=, v, _), do: &(&1 != v)
  defp matches?(:empty, _, _), do: &empty?(&1)
  defp matches?(:not_empty, _, _), do: &(!empty?(&1))
  defp matches?(:<=, v, _), do: &(&1 <= v)
  defp matches?(:<, v, _), do: &(&1 < v)
  defp matches?(:>, v, _), do: &(&1 > v)
  defp matches?(:>=, v, _), do: &(&1 >= v)
  defp matches?(:in, v, _), do: &(&1 in v)
  defp matches?(:not_in, v, _), do: &(&1 not in v)
  defp matches?(:contains, v, _), do: &(v in &1)
  defp matches?(:not_contains, v, _), do: &(v not in &1)

  defp matches?(:like, v, :sqlite) do
    v = String.downcase(v)
    &(String.downcase(&1) =~ v)
  end

  defp matches?(:like, v, _), do: &(&1 =~ v)

  defp matches?(:not_like, v, :sqlite) do
    v = String.downcase(v)
    &(String.downcase(&1) =~ v == false)
  end

  defp matches?(:not_like, v, _), do: &(&1 =~ v == false)
  defp matches?(:=~, v, ecto_adapter), do: matches?(:ilike, v, ecto_adapter)

  defp matches?(:ilike, v, _) do
    v = String.downcase(v)
    &(String.downcase(&1) =~ v)
  end

  defp matches?(:not_ilike, v, _) do
    v = String.downcase(v)
    &(String.downcase(&1) =~ v == false)
  end

  defp matches?(:like_and, v, :sqlite) when is_binary(v) do
    values = v |> String.downcase() |> String.split()
    &Enum.all?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:like_and, v, :sqlite) do
    values = Enum.map(v, &String.downcase/1)
    &Enum.all?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:like_and, v, _) when is_binary(v) do
    values = String.split(v)
    &Enum.all?(values, fn v -> &1 =~ v end)
  end

  defp matches?(:like_and, v, _), do: &Enum.all?(v, fn v -> &1 =~ v end)

  defp matches?(:like_or, v, :sqlite) when is_binary(v) do
    values = v |> String.downcase() |> String.split()
    &Enum.any?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:like_or, v, :sqlite) do
    values = Enum.map(v, &String.downcase/1)
    &Enum.any?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:like_or, v, _) when is_binary(v) do
    values = String.split(v)
    &Enum.any?(values, fn v -> &1 =~ v end)
  end

  defp matches?(:like_or, v, _), do: &Enum.any?(v, fn v -> &1 =~ v end)

  defp matches?(:ilike_and, v, _) when is_binary(v) do
    values = v |> String.downcase() |> String.split()
    &Enum.all?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:ilike_and, v, _) do
    values = Enum.map(v, &String.downcase/1)
    &Enum.all?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:ilike_or, v, _) when is_binary(v) do
    values = v |> String.downcase() |> String.split()
    &Enum.any?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:ilike_or, v, _) do
    values = Enum.map(v, &String.downcase/1)
    &Enum.any?(values, fn v -> String.downcase(&1) =~ v end)
  end

  defp matches?(:starts_with, v, _) do
    v = String.downcase(v)
    &String.starts_with?(String.downcase(&1), v)
  end

  defp matches?(:ends_with, v, _) do
    v = String.downcase(v)
    &String.ends_with?(String.downcase(&1), v)
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
    flop_opts = [
      for: Fruit,
      max_limit: 999_999_999,
      default_limit: 999_999_999
    ]

    sort? = opts[:sort] || true

    params =
      if sort?,
        do: Map.merge(params, %{order_by: [:id], order_directions: [:asc]}),
        else: params

    flop = Flop.validate!(params, flop_opts)

    q =
      Fruit
      |> join(:left, [f], o in assoc(f, :owner), as: :owner)
      |> preload(:owner)

    opts = Keyword.merge(flop_opts, Keyword.take(opts, [:extra_opts]))
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
    PolymorphicEmbed.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
