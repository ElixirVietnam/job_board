Mox.defmock(JobBoard.HTTPClient.Mock, for: JobBoard.HTTPClient)

Application.ensure_all_started(:mox)

ExUnit.start()
