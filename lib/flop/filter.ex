defmodule Flop.Filter do
  @moduledoc """
  Defines a filter.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Flop.Schema

  alias Ecto.Changeset
  alias Flop.CustomTypes.Any
  alias Flop.CustomTypes.ExistingAtom

  @typedoc """
  Represents filter query parameters.

  ### Fields

  - `field`: The field the filter is applied to. The allowed fields can be
    restricted by deriving `Flop.Schema` in your Ecto schema.
  - `op`: The filter operator.
  - `value`: The comparison value of the filter.
  """
  @type t :: %__MODULE__{
          field: atom | String.t(),
          op: op,
          value: any
        }

  @typedoc """
  Represents valid filter operators.

  | Operator        | Value               | WHERE clause                                            |
  | :-------------- | :------------------ | ------------------------------------------------------- |
  | `:==`           | `"Salicaceae"`      | `WHERE column = 'Salicaceae'`                           |
  | `:!=`           | `"Salicaceae"`      | `WHERE column != 'Salicaceae'`                          |
  | `:=~`           | `"cyth"`            | `WHERE column ILIKE '%cyth%'`                           |
  | `:empty`        | `true`              | `WHERE (column IS NULL) = true`                         |
  | `:empty`        | `false`             | `WHERE (column IS NULL) = false`                        |
  | `:not_empty`    | `true`              | `WHERE (column IS NOT NULL) = true`                     |
  | `:not_empty`    | `false`             | `WHERE (column IS NOT NULL) = false`                    |
  | `:<=`           | `10`                | `WHERE column <= 10`                                    |
  | `:<`            | `10`                | `WHERE column < 10`                                     |
  | `:>=`           | `10`                | `WHERE column >= 10`                                    |
  | `:>`            | `10`                | `WHERE column > 10`                                     |
  | `:in`           | `["pear", "plum"]`  | `WHERE column = ANY('pear', 'plum')`                    |
  | `:not_in`       | `["pear", "plum"]`  | `WHERE column = NOT IN('pear', 'plum')`                 |
  | `:contains`     | `"pear"`            | `WHERE 'pear' = ANY(column)`                            |
  | `:not_contains` | `"pear"`            | `WHERE 'pear' = NOT IN(column)`                         |
  | `:like`         | `"cyth"`            | `WHERE column LIKE '%cyth%'`                            |
  | `:not_like`     | `"cyth"`            | `WHERE column NOT LIKE '%cyth%'`                        |
  | `:like_and`     | `["Rubi", "Rosa"]`  | `WHERE column LIKE '%Rubi%' AND column LIKE '%Rosa%'`   |
  | `:like_and`     | `"Rubi Rosa"`       | `WHERE column LIKE '%Rubi%' AND column LIKE '%Rosa%'`   |
  | `:like_or`      | `["Rubi", "Rosa"]`  | `WHERE column LIKE '%Rubi%' OR column LIKE '%Rosa%'`    |
  | `:like_or`      | `"Rubi Rosa"`       | `WHERE column LIKE '%Rubi%' OR column LIKE '%Rosa%'`    |
  | `:ilike`        | `"cyth"`            | `WHERE column ILIKE '%cyth%'`                           |
  | `:not_ilike`    | `"cyth"`            | `WHERE column NOT ILIKE '%cyth%'`                       |
  | `:ilike_and`    | `["Rubi", "Rosa"]`  | `WHERE column ILIKE '%Rubi%' AND column ILIKE '%Rosa%'` |
  | `:ilike_and`    | `"Rubi Rosa"`       | `WHERE column ILIKE '%Rubi%' AND column ILIKE '%Rosa%'` |
  | `:ilike_or`     | `["Rubi", "Rosa"]`  | `WHERE column ILIKE '%Rubi%' OR column ILIKE '%Rosa%'`  |
  | `:ilike_or`     | `"Rubi Rosa"`       | `WHERE column ILIKE '%Rubi%' OR column ILIKE '%Rosa%'`  |

  The filter operators `:empty` and `:not_empty` will regard empty arrays as
  empty values if the field is known to be an array field.

  The filter operators `:ilike_and`, `:ilike_or`, `:like_and` and `:like_or`
  accept both strings and list of strings.

  - If the filter value is a string, it will be split at whitespace characters
    and the segments are combined with `and` or `or`.
  - If a list of strings is passed, the individual strings are not split, and
    the list items are combined with `and` or `or`.
  """
  @type op ::
          :==
          | :!=
          | :=~
          | :empty
          | :not_empty
          | :<=
          | :<
          | :>=
          | :>
          | :in
          | :not_in
          | :contains
          | :not_contains
          | :like
          | :not_like
          | :like_and
          | :like_or
          | :ilike
          | :not_ilike
          | :ilike_and
          | :ilike_or

  @primary_key false
  embedded_schema do
    field :field, ExistingAtom

    field :op, Ecto.Enum,
      default: :==,
      values: [
        :==,
        :!=,
        :=~,
        :empty,
        :not_empty,
        :<=,
        :<,
        :>=,
        :>,
        :in,
        :not_in,
        :contains,
        :not_contains,
        :like,
        :not_like,
        :like_and,
        :like_or,
        :ilike,
        :not_ilike,
        :ilike_and,
        :ilike_or
      ]

    field :value, Any
  end

  @doc false
  @spec changeset(__MODULE__.t(), map, keyword) :: Changeset.t()
  def changeset(filter, %{} = params, opts \\ []) do
    filter
    |> cast(params, [:field, :op, :value])
    |> validate_required([:field, :op])
    |> validate_filterable(opts[:for])
    |> validate_op(opts[:for])
  end

  @spec validate_filterable(Changeset.t(), module | nil) :: Changeset.t()
  defp validate_filterable(changeset, nil), do: changeset

  defp validate_filterable(changeset, module) when is_atom(module) do
    filterable_fields =
      module
      |> struct()
      |> filterable()

    validate_inclusion(changeset, :field, filterable_fields)
  end

  defp validate_op(changeset, nil), do: changeset

  defp validate_op(%Changeset{valid?: true} = changeset, module)
       when is_atom(module) do
    field = Changeset.get_field(changeset, :field)
    op = Changeset.get_field(changeset, :op)
    allowed_operators = allowed_operators(module, field)

    if op in allowed_operators do
      changeset
    else
      add_error(changeset, :op, "is invalid")
    end
  end

  defp validate_op(%Changeset{valid?: false} = changeset, module)
       when is_atom(module) do
    changeset
  end

  @doc """
  Returns the allowed operators for the given schema module and field.

  For regular Ecto schema fields, the type is derived via schema reflection.

  If the given schema module derives `Flop.Schema`, the type of join and
  custom fields is determined via the `ecto_type` option. Compound files are
  always handled as string fields, minus unsupported operators.

  If the type cannot be determined or if the type is not a native Ecto type, a
  list with all operators is returned.

      iex> allowed_operators(Pet, :age)
      [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  """
  @spec allowed_operators(atom, atom) :: [op]
  def allowed_operators(module, field)
      when is_atom(module) and is_atom(field) do
    struct = struct!(module)

    if Flop.Schema.impl_for(struct) != Flop.Schema.Any do
      module
      |> field_type_from_flop_schema(struct, field)
      |> allowed_operators()
    else
      :type |> module.__schema__(field) |> allowed_operators()
    end
  end

  defp field_type_from_flop_schema(module, struct, field) do
    case Flop.Schema.field_type(struct, field) do
      {:normal, _} ->
        module.__schema__(:type, field)

      {:join, %{ecto_type: type}} ->
        type

      {:custom, %{ecto_type: type}} ->
        type

      {:compound, _} ->
        :flop_compound

      _ ->
        nil
    end
  end

  @doc """
  Returns the allowed operators for the given Ecto type.

  If the given value is not a native Ecto type, a list with all operators is
  returned.

      iex> allowed_operators(:integer)
      [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  """
  @spec allowed_operators(atom) :: [op]
  def allowed_operators(type) when type in [:decimal, :float, :id, :integer] do
    [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  end

  def allowed_operators(type) when type in [:binary_id, :string] do
    [
      :==,
      :!=,
      :=~,
      :empty,
      :not_empty,
      :<=,
      :<,
      :>=,
      :>,
      :in,
      :not_in,
      :like,
      :not_like,
      :like_and,
      :like_or,
      :ilike,
      :not_ilike,
      :ilike_and,
      :ilike_or
    ]
  end

  def allowed_operators(:boolean) do
    [:==, :!=, :=~, :empty, :not_empty]
  end

  def allowed_operators({:array, _}) do
    [
      :==,
      :!=,
      :empty,
      :not_empty,
      :<=,
      :<,
      :>=,
      :>,
      :in,
      :not_in,
      :contains,
      :not_contains
    ]
  end

  def allowed_operators({:map, _}) do
    [:==, :!=, :empty, :not_empty, :in, :not_in]
  end

  def allowed_operators(:map) do
    [:==, :!=, :empty, :not_empty, :in, :not_in]
  end

  def allowed_operators(type)
      when type in [
             :date,
             :time,
             :time_usec,
             :naive_datetime,
             :naive_datetime_usec,
             :utc_datetime,
             :utc_datetime_usec
           ] do
    [:==, :!=, :empty, :not_empty, :<=, :<, :>=, :>, :in, :not_in]
  end

  def allowed_operators({:parameterized, Ecto.Enum, _}) do
    [
      :==,
      :!=,
      :empty,
      :not_empty,
      :<=,
      :<,
      :>=,
      :>,
      :in,
      :not_in
    ]
  end

  def allowed_operators(:flop_compound) do
    [
      :=~,
      :like,
      :not_like,
      :like_and,
      :like_or,
      :ilike,
      :not_ilike,
      :ilike_and,
      :ilike_or,
      :empty,
      :not_empty
    ]
  end

  def allowed_operators(_) do
    [
      :==,
      :!=,
      :=~,
      :empty,
      :not_empty,
      :<=,
      :<,
      :>=,
      :>,
      :in,
      :not_in,
      :contains,
      :not_contains,
      :like,
      :not_like,
      :like_and,
      :like_or,
      :ilike,
      :not_ilike,
      :ilike_and,
      :ilike_or
    ]
  end

  @doc """
  Fetches the first filter for the given field and returns it in a tuple.

  ## Examples

      iex> fetch([], :name)
      :error

      iex> fetch([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      {:ok, %Flop.Filter{field: :name, op: :==, value: "Joe"}}

      iex> fetch([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      :error

      iex> fetch(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      {:ok, %Flop.Filter{field: :name, op: :==, value: "Joe"}}
  """
  @doc since: "0.19.0"
  @spec fetch([t()], atom) :: {:ok, t()} | :error
  def fetch(filters, field) when is_list(filters) and is_atom(field) do
    filters
    |> Enum.find(fn
      %{field: ^field} -> true
      _ -> false
    end)
    |> case do
      nil -> :error
      filter -> {:ok, filter}
    end
  end

  @doc """
  Returns the first filter for the given field.

  ## Examples

      iex> get([], :name)
      nil

      iex> get([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      %Flop.Filter{field: :name, op: :==, value: "Joe"}

      iex> get([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      nil

      iex> get(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      %Flop.Filter{field: :name, op: :==, value: "Joe"}
  """
  @doc since: "0.19.0"
  @spec get([t()], atom) :: t() | nil
  def get(filters, field) when is_list(filters) and is_atom(field) do
    Enum.find(filters, fn
      %{field: ^field} -> true
      _ -> false
    end)
  end

  @doc """
  Returns the all filters for the given field.

  ## Examples

      iex> get_all([], :name)
      []

      iex> get_all([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      [%Flop.Filter{field: :name, op: :==, value: "Joe"}]

      iex> get_all([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      []

      iex> get_all(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [
        %Flop.Filter{field: :name, op: :==, value: "Joe"},
        %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ]
  """
  @doc since: "0.19.0"
  @spec get_all([t()], atom) :: [t()]
  def get_all(filters, field) when is_list(filters) and is_atom(field) do
    Enum.filter(filters, fn
      %{field: ^field} -> true
      _ -> false
    end)
  end

  @doc """
  Deletes the filters for the given field from a list of filters.

  ## Examples

      iex> delete(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8}
      ...>   ],
      ...>   :name
      ...> )
      [%Flop.Filter{field: :age, op: :>, value: 8}]

      iex> delete(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [%Flop.Filter{field: :age, op: :>, value: 8}]

      iex> delete([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      [%Flop.Filter{field: :name, op: :==, value: "Joe"}]
  """
  @doc since: "0.19.0"
  @spec delete([t], atom) :: [t]
  def delete(filters, field) when is_list(filters) and is_atom(field) do
    Enum.reject(filters, fn
      %{field: ^field} -> true
      _ -> false
    end)
  end

  @doc """
  Deletes the first filter in list of filters for the given field.

  ## Examples

      iex> delete_first(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   :name
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ]

      iex> delete_first([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      [%Flop.Filter{field: :name, op: :==, value: "Joe"}]
  """
  @doc since: "0.19.0"
  @spec delete_first([t], atom) :: [t]
  def delete_first(filters, field) when is_list(filters) and is_atom(field) do
    delete_first_filter(filters, field)
  end

  defp delete_first_filter([%{field: field} | tail], field) do
    tail
  end

  defp delete_first_filter([%{} = filter | tail], field) do
    [filter | delete_first_filter(tail, field)]
  end

  defp delete_first_filter([], _field) do
    []
  end

  @doc """
  Removes the filters for the given fields from a list of filters.

  ## Examples

      iex> drop(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :color, op: :==, value: "blue"}
      ...>   ],
      ...>   [:name, :color]
      ...> )
      [%Flop.Filter{field: :age, op: :>, value: 8}]

      iex> drop(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :color, op: :==, value: "blue"},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   [:name, :species]
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :color, op: :==, value: "blue"}
      ]
  """
  @doc since: "0.19.0"
  @spec drop([t], [atom]) :: [t]
  def drop(filters, fields) when is_list(filters) and is_list(fields) do
    Enum.reject(filters, fn
      %{field: field} -> field in fields
    end)
  end

  @doc """
  Creates a list of filters from an enumerable.

  The default operator is `:==`.

      iex> new(%{name: "George", age: 8})
      [
        %Flop.Filter{field: :age, op: :==, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

      iex> new([name: "George", age: 8])
      [
        %Flop.Filter{field: :name, op: :==, value: "George"},
        %Flop.Filter{field: :age, op: :==, value: 8},
      ]

  You can optionally pass a mapping from field names to operators as a map
  with atom keys.

      iex> new(
      ...>   %{name: "George", age: 8},
      ...>   operators: %{name: :ilike_and}
      ...> )
      [
        %Flop.Filter{field: :age, op: :==, value: 8},
        %Flop.Filter{field: :name, op: :ilike_and, value: "George"}
      ]

  You can also pass a map to rename fields.

      iex> new(
      ...>   %{s: "George", age: 8},
      ...>   rename: %{s: :name}
      ...> )
      [
        %Flop.Filter{field: :age, op: :==, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

      iex> new(
      ...>   %{s: "George", cat: true},
      ...>   rename: %{s: :name, cat: :dog}
      ...> )
      [
        %Flop.Filter{field: :dog, op: :==, value: true},
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

  If both a rename option and an operator are set for a field, the operator
  option needs to use the new field name.

      iex> new(
      ...>   %{n: "George"},
      ...>   rename: %{n: :name},
      ...>   operators: %{name: :ilike_or}
      ...> )
      [%Flop.Filter{field: :name, op: :ilike_or, value: "George"}]

  If the enumerable uses string keys as field names, the function attempts to
  convert them to existing atoms. If the atom does not exist, the filter is
  removed from the list.

      iex> new(%{"name" => "George", "age" => 8})
      [
        %Flop.Filter{field: :age, op: :==, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

      iex> new(%{"name" => "George", "doesnotexist" => 8})
      [
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]

  Other key types are also removed.

      iex> new(%{"name" => "George", 2 => 8})
      [
        %Flop.Filter{field: :name, op: :==, value: "George"}
      ]
  """
  @doc since: "0.19.0"
  @spec new(Enumerable.t(), keyword) :: [t]
  def new(enum, opts \\ []) do
    operators = opts[:operators]
    renamings = opts[:rename]

    enum
    |> Enum.map(fn
      {field, value} when is_atom(field) or is_binary(field) ->
        if field = rename_field(field, renamings) do
          %Flop.Filter{
            field: field,
            op: op_from_mapping(field, operators),
            value: value
          }
        end

      {_, _} ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp op_from_mapping(_field, nil), do: :==

  defp op_from_mapping(field, %{} = operators) when is_atom(field) do
    Map.get(operators, field, :==)
  end

  defp op_from_mapping(field, %{} = operators) when is_binary(field) do
    atom_key = String.to_existing_atom(field)
    Map.get(operators, atom_key, :==)
  rescue
    ArgumentError -> :==
  end

  defp rename_field(field, nil) when is_atom(field), do: field

  defp rename_field(field, nil) when is_binary(field) do
    String.to_existing_atom(field)
  rescue
    ArgumentError -> nil
  end

  defp rename_field(field, %{} = renamings) when is_atom(field) do
    Map.get(renamings, field, field)
  end

  defp rename_field(field, %{} = renamings) when is_binary(field) do
    atom_key = String.to_existing_atom(field)
    Map.get(renamings, atom_key, field)
  rescue
    ArgumentError -> nil
  end

  @doc """
  Takes all filters for the given fields from a filter list.

  ## Examples

      iex> take(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :color, op: :==, value: "blue"},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   [:name, :color]
      ...> )
      [
        %Flop.Filter{field: :name, op: :==, value: "Joe"},
        %Flop.Filter{field: :color, op: :==, value: "blue"},
        %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ]
  """
  @doc since: "0.19.0"
  @spec take([t], [atom]) :: [t]
  def take(filters, fields) when is_list(filters) and is_list(fields) do
    Enum.filter(filters, &(&1.field in fields))
  end

  @doc """
  Returns the first filter for the given field and removes all other filters for
  the same field from the filter list.

  Returns a tuple with the first matching filter first value for `key` and the
  remaining filter list. If there is no filter for the field in the list, the
  default value is returned as the first tuple element.

  See also `Flop.Filter.pop_first/3`.

  ## Examples

      iex> pop([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      {%Flop.Filter{field: :name, op: :==, value: "Joe"}, []}

      iex> pop([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      {nil, [%Flop.Filter{field: :name, op: :==, value: "Joe"}]}

      iex> pop(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :age,
      ...>   %Flop.Filter{field: :age, op: :>, value: 8}
      ...> )
      {
        %Flop.Filter{field: :age, op: :>, value: 8},
        [%Flop.Filter{field: :name, op: :==, value: "Joe"}]
      }

      iex> pop(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"},
      ...>   ],
      ...>   :name
      ...> )
      {
        %Flop.Filter{field: :name, op: :==, value: "Joe"},
        [%Flop.Filter{field: :age, op: :>, value: 8}]
      }
  """
  @doc since: "0.19.0"
  @spec pop([t], atom, any) :: {t, [t]}
  def pop(filters, field, default \\ nil)
      when is_list(filters) and is_atom(field) do
    case fetch(filters, field) do
      {:ok, value} -> {value, delete(filters, field)}
      :error -> {default, filters}
    end
  end

  @doc """
  Returns the first filter for the given field and a filter list with all
  remaining filters.

  Returns a tuple with the first matching filter first value for `key` and the
  remaining filter list. If there is no filter for the field in the list, the
  default value is returned as the first tuple element.

  See also `Flop.Filter.pop/3`.

  ## Examples

      iex> pop_first([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :name)
      {%Flop.Filter{field: :name, op: :==, value: "Joe"}, []}

      iex> pop_first([%Flop.Filter{field: :name, op: :==, value: "Joe"}], :age)
      {nil, [%Flop.Filter{field: :name, op: :==, value: "Joe"}]}

      iex> pop_first(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   :age,
      ...>   %Flop.Filter{field: :age, op: :>, value: 8}
      ...> )
      {
        %Flop.Filter{field: :age, op: :>, value: 8},
        [%Flop.Filter{field: :name, op: :==, value: "Joe"}]
      }

      iex> pop_first(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"},
      ...>   ],
      ...>   :name
      ...> )
      {
        %Flop.Filter{field: :name, op: :==, value: "Joe"},
        [
          %Flop.Filter{field: :age, op: :>, value: 8},
          %Flop.Filter{field: :name, op: :==, value: "Jim"}
        ]
      }
  """
  @doc since: "0.19.0"
  @spec pop_first([t], atom, any) :: {t, [t]}
  def pop_first(filters, field, default \\ nil)
      when is_list(filters) and is_atom(field) do
    case fetch(filters, field) do
      {:ok, value} -> {value, delete_first(filters, field)}
      :error -> {default, filters}
    end
  end

  @doc """
  Adds the given filter to the filter list and removes all existing filters for
  the same field from the list.

  ## Examples

      iex> put(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   %Flop.Filter{field: :age, op: :>, value: 8}
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Joe"}
      ]

      iex> put(
      ...>   [
      ...>     %Flop.Filter{field: :name, op: :==, value: "Joe"},
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   %Flop.Filter{field: :name, op: :==, value: "Jane"}
      ...> )
      [
        %Flop.Filter{field: :name, op: :==, value: "Jane"},
        %Flop.Filter{field: :age, op: :>, value: 8}
      ]
  """
  @doc since: "0.19.0"
  @spec put([t], t) :: [t]
  def put(filters, %Flop.Filter{field: field} = filter)
      when is_list(filters) and is_atom(field) do
    [filter | delete(filters, field)]
  end

  @doc """
  Adds the given filter to the filter list only if no filter for the field
  exists yet.

  ## Examples

      iex> put_new(
      ...>   [%Flop.Filter{field: :name, op: :==, value: "Joe"}],
      ...>   %Flop.Filter{field: :age, op: :>, value: 8}
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Joe"}
      ]

      iex> put_new(
      ...>   [
      ...>     %Flop.Filter{field: :age, op: :>, value: 8},
      ...>     %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ...>   ],
      ...>   %Flop.Filter{field: :name, op: :==, value: "Jane"}
      ...> )
      [
        %Flop.Filter{field: :age, op: :>, value: 8},
        %Flop.Filter{field: :name, op: :==, value: "Jim"}
      ]
  """
  @doc since: "0.19.0"
  @spec put_new([t], t) :: [t]
  def put_new(filters, %Flop.Filter{field: field} = filter)
      when is_list(filters) and is_atom(field) do
    case fetch(filters, field) do
      {:ok, _} -> filters
      :error -> [filter | filters]
    end
  end
end
