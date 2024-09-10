# Used by "mix format"
[
  inputs: [
    "{mix,.formatter}.exs",
    "{config,integration_test,lib,test}/**/*.{ex,exs}"
  ],
  line_length: 80,
  import_deps: [:ecto, :stream_data]
]
