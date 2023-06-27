defmodule Flop.Generators do
  @moduledoc false
  use ExUnitProperties

  alias Flop.Filter

  @dialyzer {:nowarn_function, [filter: 0, pagination_parameters: 1, pet: 0]}

  @order_directions [
    :asc,
    :asc_nulls_first,
    :asc_nulls_last,
    :desc,
    :desc_nulls_first,
    :desc_nulls_last
  ]

  @whitespace ["\u0020", "\u2000", "\u3000"]

  def pet do
    gen all name <- string(:alphanumeric, min_length: 2),
            age <- integer(1..500),
            species <- string(:alphanumeric, min_length: 2) do
      %{name: name, age: age, species: species}
    end
  end

  def filterable_pet_field do
    member_of(Flop.Schema.filterable(%MyApp.Pet{}))
  end

  def filterable_pet_field(:string) do
    member_of([:full_name, :name, :owner_name, :pet_and_owner_name, :species])
  end

  def filterable_pet_field(:integer) do
    member_of([:age, :owner_age])
  end

  def uniq_list_of_strings(len) do
    uniq_list_of(string(:alphanumeric, min_length: 2), length: len)
  end

  def uniq_list_of_pets(opts) do
    length_range = Keyword.fetch!(opts, :length)

    gen all length <- integer(length_range),
            names <- uniq_list_of_strings(length),
            family_names <- uniq_list_of_strings(length),
            given_names <- uniq_list_of_strings(length),
            owners <- uniq_list_of_owners(length),
            ages <- uniq_list_of(integer(1..500), length: length),
            species <- uniq_list_of_strings(length) do
      [names, ages, species, family_names, given_names, owners]
      |> Enum.zip()
      |> Enum.map(fn {name, age, species, family_name, given_name, owner} ->
        %MyApp.Pet{
          name: name,
          age: age,
          species: species,
          family_name: family_name,
          given_name: given_name,
          owner: owner
        }
      end)
    end
  end

  def uniq_list_of_owners(len) do
    gen all names <- uniq_list_of_strings(len),
            ages <- uniq_list_of(integer(1..500), length: len),
            emails <- uniq_list_of_strings(len) do
      [names, ages, emails]
      |> Enum.zip()
      |> Enum.map(fn {name, age, email} ->
        %MyApp.Owner{name: name, age: age, email: email}
      end)
    end
  end

  def pagination_parameters(type) when type in [:offset, :page] do
    gen all val_1 <- positive_integer(),
            val_2 <- one_of([positive_integer(), constant(nil)]) do
      [a, b] = Enum.shuffle([val_1, val_2])

      case type do
        :offset -> %{offset: a, limit: b}
        :page -> %{page: a, page_size: b}
      end
    end
  end

  def pagination_parameters(type) when type in [:first, :last] do
    gen all val_1 <- positive_integer(),
            val_2 <- one_of([string(:alphanumeric), constant(nil)]) do
      case type do
        :first -> %{first: val_1, after: val_2}
        :last -> %{last: val_1, before: val_2}
      end
    end
  end

  def filter do
    gen all field <- member_of([:age, :name, :owner_name]),
            value <- value_by_field(field),
            op <- operator_by_type(value) do
      %Filter{field: field, op: op, value: value}
    end
  end

  def value_by_field(:age), do: integer()

  def value_by_field(:name),
    do: string(:alphanumeric, min_length: 1)

  def value_by_field(:owner_age), do: integer()

  def value_by_field(:owner_name),
    do: string(:alphanumeric, min_length: 1)

  def compare_value_by_field(:age), do: integer(1..30)

  def compare_value_by_field(:name),
    do: string(?a..?z, min_length: 1, max_length: 3)

  def compare_value_by_field(:owner_age), do: integer(1..100)

  defp operator_by_type(a) when is_binary(a),
    do:
      member_of([
        :==,
        :!=,
        :=~,
        :<=,
        :<,
        :>=,
        :>,
        :like,
        :not_like,
        :like_and,
        :like_or,
        :ilike,
        :not_ilike,
        :ilike_and,
        :ilike_or
      ])

  defp operator_by_type(a) when is_number(a),
    do: member_of([:==, :!=, :<=, :<, :>=, :>])

  def cursor_fields(%{} = schema) do
    schema
    |> Flop.Schema.sortable()
    |> Enum.shuffle()
    |> constant()
  end

  def order_directions(%{} = schema) do
    field_count =
      schema
      |> Flop.Schema.sortable()
      |> length()

    @order_directions
    |> member_of()
    |> list_of(length: field_count)
  end

  @doc """
  Generates a random sub string for the given string. Empty sub strings are
  filtered.
  """
  def substring(s) when is_binary(s) do
    str_length = String.length(s)

    gen all start_at <- integer(0..(str_length - 1)),
            end_at <- integer(start_at..(str_length - 1)),
            query_value = String.slice(s, start_at..end_at),
            query_value != " " do
      query_value
    end
  end

  @doc """
  Generates a search string consisting of two random substrings
  or a list of search strings consisting of two random substrings from the given
  string.
  """
  def search_text_or_list(s) when is_binary(s) do
    gen all string_or_list <- one_of([search_text(s), search_text_list(s)]) do
      string_or_list
    end
  end

  defp search_text_list(s) when is_binary(s) do
    str_length = String.length(s)

    gen all start_at_a <- integer(0..(str_length - 2)),
            end_at_a <- integer((start_at_a + 1)..(str_length - 1)),
            start_at_b <- integer(0..(str_length - 2)),
            end_at_b <- integer((start_at_b + 1)..(str_length - 1)),
            query_value_a <-
              s
              |> String.slice(start_at_a..end_at_a)
              |> String.trim()
              |> constant(),
            query_value_a != "",
            query_value_b <-
              s
              |> String.slice(start_at_b..end_at_b)
              |> String.trim()
              |> constant(),
            query_value_b != "" do
      [query_value_a, query_value_b]
    end
  end

  defp search_text(s) when is_binary(s) do
    gen all whitespace_character <- member_of(@whitespace),
            text_list <- search_text_list(s) do
      Enum.join(text_list, whitespace_character)
    end
  end
end
