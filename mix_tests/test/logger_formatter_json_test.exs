defmodule LoggerFormatterJsonTest do
  use ExUnit.Case

  describe "Unstructured log messages" do
    test "String with a charlist" do
      expected = ~s({"msg":"abc","level":"info"}\n)

      assert expected ==
               to_string(
                 :logger_formatter_json.format(
                   %{level: :info, msg: {:string, ~c"abc"}, meta: %{}},
                   %{}
                 )
               )
    end

    test "String with a binary" do
      expected = ~s({"msg":"abc","level":"info"}\n)

      assert expected ==
               to_string(
                 :logger_formatter_json.format(
                   %{level: :info, msg: {:string, "abc"}, meta: %{}},
                   %{}
                 )
               )
    end

    test "List of charlists" do
      expected = ~s({"msg":"abc","level":"info"}\n)

      assert expected ==
               to_string(
                 :logger_formatter_json.format(
                   %{level: :info, msg: {:string, [~c"abc"]}, meta: %{}},
                   %{}
                 )
               )
    end

    test "Erlang format string and args" do
      expected = ~s({"msg":"hello world","level":"info"}\n)

      assert expected ==
               to_string(
                 :logger_formatter_json.format(
                   %{level: :info, msg: {~c"hello ~s", [~c"world"]}, meta: %{}},
                   %{}
                 )
               )
    end

    test "String with microsecond" do
      expected = ~s({"msg":"408\\u00B5s","level":"info"}\n)

      assert expected ==
               to_string(
                 :logger_formatter_json.format(
                   %{level: :info, msg: {:string, "408µs"}, meta: %{}},
                   %{}
                 )
               )
    end

    test "String with new line after microsecond" do
      expected = ~s({"msg":"408\\u00B5s\\n","level":"info"}\n)

      assert expected ==
               to_string(
                 :logger_formatter_json.format(
                   %{level: :info, msg: {:string, "408µs\n"}, meta: %{}},
                   %{}
                 )
               )
    end
  end

  describe "Structured log messages" do
    test "Simple map" do
      expected = ~s({"msg":{"hi":"there"},"level":"info"}\n)

      assert expected ==
               to_string(
                 :logger_formatter_json.format(
                   %{level: :info, msg: {:report, %{hi: :there}}, meta: %{}},
                   %{}
                 )
               )
    end
  end
end
