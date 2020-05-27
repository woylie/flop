{:ok, _pid} = Flop.Repo.start_link()
{:ok, _} = Application.ensure_all_started(:ex_machina)
ExUnit.start()
