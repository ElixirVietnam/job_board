use Mix.Config

import_config "#{Mix.env()}.exs"
import_config "{#{Mix.env()}.private}.exs"
