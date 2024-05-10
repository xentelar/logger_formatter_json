-module(logger_formatter_json_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

all() -> [to_string, is_printable, unstructured, structured, metadata, duplicate_keys].

to_string(_) ->
  Config = #{single_line => true},
  ?assertEqual("foo", logger_formatter_json:to_string("foo", Config)),
  ?assertEqual("foo", logger_formatter_json:to_string(foo, Config)),
  ?assertEqual(["[]"], logger_formatter_json:to_string([], Config)),
  ?assertEqual(<<>>, logger_formatter_json:to_string(<<>>, Config)),
  ?assertEqual(<<"foo">>, logger_formatter_json:to_string(<<"foo">>, Config)),
  ?assertEqual(
    <<"foo\nbar">>,
    iolist_to_binary(logger_formatter_json:to_string(<<"foo\nbar">>, Config))
  ),
  ?assertEqual(
    <<"793µs"/utf8>>,
    iolist_to_binary(logger_formatter_json:to_string(<<"793µs"/utf8>>, Config))
  ).


is_printable(_) ->
  ?assertEqual(true, logger_formatter_json:is_printable(<<"foo">>)),
  % ?assertEqual(nomatch, re:run(<<"foo\nbar">>, <<"[[:^print:]]">>, [{capture, none}, unicode])),
  ?assertEqual(true, logger_formatter_json:is_printable(<<"foo\nbar">>)),
  ?assertEqual(true, logger_formatter_json:is_printable(<<"foo\nbar"/utf8>>)),
  ?assertEqual(false, logger_formatter_json:is_printable(<<0>>)).


unstructured() -> [{docs, "logs that aren't structured get passed through with a re-frame"}].

unstructured(_) ->
  Config = #{single_line => true},
  ?assertEqual(
    <<"{\"msg\":\"abc\",\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(#{level => info, msg => {string, "abc"}, meta => #{}}, Config)
    )
  ),
  ?assertEqual(
    <<"{\"msg\":\"abc\",\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {string, [<<"abc">>]}, meta => #{}},
        Config
      )
    )
  ),
  ?assertEqual(
    <<"{\"msg\":\"793\\u00B5s\",\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {string, [<<"793µs"/utf8>>]}, meta => #{}},
        Config
      )
    )
  ),
  ?assertEqual(
    <<"{\"msg\":\"\",\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(#{level => info, msg => {string, <<>>}, meta => #{}}, Config)
    )
  ),
  ?assertEqual(
    <<"{\"msg\":\"foo\\nbar\",\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {string, <<"foo\nbar">>}, meta => #{}},
        Config
      )
    )
  ),
  ?assertEqual(
    <<"{\"msg\":\"foo\\n\",\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {string, <<"foo\n">>}, meta => #{}},
        Config
      )
    )
  ),
  ?assertEqual(
    <<"{\"msg\":\"793\\u00B5s\\n\",\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {string, <<"793µs\n"/utf8>>}, meta => #{}},
        Config
      )
    )
  ),
  ?assertEqual(
    <<
      "{\"msg\":\"GET \\/phoenix\\/live_reload\\/socket\\/websocket - Sent 404 in 793\\u00B5s\",\"level\":\"info\"}\n"
    >>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{
          level => info,
          msg
          =>
          {
            string,
            [
              [<<"GET">>, 32, <<"/phoenix/live_reload/socket/websocket">>],
              <<" - ">>,
              <<"Sent">>,
              32,
              <<"404">>,
              <<" in ">>,
              <<"793µs"/utf8>>
            ]
          },
          meta => #{}
        },
        #{}
      )
    )
  ),
  ?assertEqual(
    <<"{\"msg\":\"hello world\",\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {"hello ~s", ["world"]}, meta => #{}},
        #{}
      )
    )
  ),
  ?assertEqual(
    <<"{\"msg\":\"hello world\",\"level\":\"info\",\"request_id\":\"F6R64Fh3F9NzEscAAAaB\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{
          level => info,
          msg => {"hello ~s", ["world"]},
          meta => #{request_id => <<"F6R64Fh3F9NzEscAAAaB">>}
        },
        #{template => [msg, level, request_id]}
      )
    )
  ),
  ?assertEqual(
    <<"{\"msg\":\"hello world\",\"level\":\"info\",\"request_id\":\"string with spaces\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{
          level => info,
          msg => {"hello ~s", ["world"]},
          meta => #{request_id => <<"string with spaces">>}
        },
        #{template => [msg, level, request_id]}
      )
    )
  ),
  % Binary data
  ?assertEqual(
    <<"{\"msg\":\"hello world\",\"level\":\"info\",\"foo\":\"<<0,1,2,3>>\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {"hello ~s", ["world"]}, meta => #{foo => <<0, 1, 2, 3>>}},
        #{template => [msg, level, foo]}
      )
    )
  ),
  ok.


duplicate_keys(_) ->
  ?assertEqual(
    <<"{\"msg\":\"hello world\",\"level\":\"info\",\"foo\":\"bar\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {"hello ~s", ["world"]}, meta => #{foo => "bar"}},
        #{template => [msg, level, foo, foo]}
      )
    )
  ),
  ok.


structured(_) ->
  %Pid = self(),
  %Fun = fun() -> #{} end,
  ?assertEqual(
    <<"{\"msg\":{\"id\":[[91,[[112,105,112,101],44,[119,111,114,107,101,114],44,[39,50,39]],93]],\"pid\":\"pid\",\"reason\":\"normal\",\"self\":\"pid\",\"what\":[108,97,115,116,32,110,111,100,101,32,116,101,114,109,105,110,97,116,101,100,59,32,112,105,112,101,32,112,114,111,99,101,115,115,32,101,120,105,116,105,110,103]},\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {report,#{id => [pipe,worker,'2'],pid => <<"pid">>,reason => normal,self => <<"pid">>,what => "last node terminated; pipe process exiting"}}, meta => #{}},
        #{}
      )
    )
  ),
  ?assertEqual(
    <<"{\"msg\":{\"pid\":\"pid\",\"what\":[83,116,97,114,116,105,110,103,32,115,101,114,118,101,114,95,103,101,110,32,112,114,111,99,101,115,115],\"initial_data\":[[123,[[105,110,105,116,95,100,97,116,97],44,[91,[[115,101,114,118,101,114,95,112,105,112,101],44,[114,101,112,108,105,99,97,116,105,111,110,95,119,111,114,107,101,114],44,[39,48,39],44,[39,48,39]],93],44,[115,101,114,118,101,114,95,103,101,110,95,109,97,112],44,[123,[[115,101,114,118,101,114,95,103,101,110,95,109,97,112],44,[60,60,[34,112,105,100,34],62,62]],125],44,[105,110,102,105,110,105,116,121],44,[49]],125]]},\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {report,#{pid => <<"pid">>,what => "Starting server_gen process",initial_data => {init_data,[server_pipe,replication_worker,'0','0'],server_gen_map,{server_gen_map,<<"pid">>},infinity,1}}}, meta => #{}},
        #{}
      )
    )
  ),
  ?assertEqual(
    <<"{\"msg\":{\"label\":[[123,[[97,112,112,108,105,99,97,116,105,111,110,95,99,111,110,116,114,111,108,108,101,114],44,[112,114,111,103,114,101,115,115]],125]],\"report\":[[91,[[123,[[97,112,112,108,105,99,97,116,105,111,110],44,[115,97,115,108]],125],44,[123,[[115,116,97,114,116,101,100,95,97,116],44,[110,111,110,111,100,101,64,110,111,104,111,115,116]],125]],93]]},\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {report,#{label => {application_controller,progress},report => [{application,sasl},{started_at,nonode@nohost}]}}, meta => #{}},
        #{}
      )
    )
  ),
  ?assertEqual(
    <<"{\"msg\":{\"hi\":\"there\"},\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {report, #{hi => there}}, meta => #{}},
        #{}
      )
    )
  ),
  % report_cb callback fun ignored for structured logs
  ?assertEqual(
    <<"{\"msg\":{\"hi\":\"there\"},\"level\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {report, #{hi => there}}, meta => #{}},
        #{report_cb => fun (_) -> {"ho ho ho", []} end}
      )
    )
  ),
  % Metadata with map value is embedded as map value
  ?assertEqual(
    <<"{\"msg\":{\"hi\":\"there\"},\"level\":\"info\",\"foo\":{\"biz\":\"baz\"}}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {report, #{hi => there}}, meta => #{foo => #{biz => baz}}},
        #{template => [msg, level, rest]}
      )
    )
  ),
  ?assertEqual(
    <<"{\"level\":\"info\",\"hi\":\"there\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {report, #{hi => there}}, meta => #{}},
        #{map_msg => merge, template => [msg, level, rest]}
      )
    )
  ),
  ?assertEqual(
    <<"{\"level\":\"info\",\"biz\":\"baz\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(
        #{level => info, msg => {report, #{foo => bar, biz => baz}}, meta => #{}},
        #{map_msg => merge, template => [level, biz]}
      )
    )
  ),
  ok.


metadata(_) ->
  Config = #{names => datadog},
  ?assertEqual(
    <<"{\"message\":\"abc\",\"status\":\"info\"}\n">>,
    iolist_to_binary(
      logger_formatter_json:format(#{level => info, msg => {string, "abc"}, meta => #{}}, Config)
    )
  ),
  ok.
