%% @doc
%% Formatter for the Erlang logger library which outputs JSON.
%% https://www.erlang.org/doc/apps/kernel/logger_chapter.html#formatters
%%
%% @end
%%
-module(logger_formatter_json).

-export([format/2]).
-export([check_config/1]).

-ifdef(TEST).
-export([format_msg/3]).
-endif.

%%%-----------------------------------------------------------------
%%% Types
-type config() :: #{chars_limit     => pos_integer() | unlimited,
                    depth           => pos_integer() | unlimited,
                    max_size        => pos_integer() | unlimited,
                    names           => map() | [map()],
                    types           => map() | [map()],
                    report_cb       => logger:report_cb(),
                    single_line     => boolean(),
                    template        => template(),
                    time_designator => byte(),
                    time_offset     => integer() | [byte()]}.
-type template() :: [metakey() | {metakey(),template(),template()} | unicode:chardata()].
-type metakey() :: atom() | [atom()].

% -type log_event() :: #{level:=level(),
%                        msg:={io:format(),[term()]} | {report,report()} | {string,unicode:chardata()},
%                        meta:=metadata()}.
%
% -type metadata() :: #{pid    => pid(),
%                       gl     => pid(),
%                       time   => timestamp(),
%                       mfa    => {module(),atom(),non_neg_integer()},
%                       file   => file:filename(),
%                       line   => non_neg_integer(),
%                       domain => [atom()],
%                       report_cb => report_cb(),
%                       atom() => term()}.

-define(IS_STRING(String),
        (is_list(String) orelse is_binary(String))).

%%%-----------------------------------------------------------------
%%% API
-spec format(LogEvent,Config) -> unicode:chardata() when
      LogEvent :: logger:log_event(),
      Config :: config().
format(#{level:=Level,msg:=Msg0,meta:=Meta},Config0)
  when is_map(Config0) ->
    Config = add_default_config(Config0),
    Template = maps:get(template,Config),
    {BT,AT0} = lists:splitwith(fun(msg) -> false; (_) -> true end, Template),
    {DoMsg,AT} =
        case AT0 of
            [msg|Rest] -> {true,Rest};
            _ ->{false,AT0}
        end,
    MsgResult =
        if DoMsg ->
            case format_msg(Msg0,Meta,Config) of
                Msg when is_map(Msg) ->
                    maps:to_list(Msg);
                Msg ->
                    {map_name(msg,Config), iolist_to_binary(Msg)}
                end;
            true ->
               []
        end,
    Result0 = [
        do_format(Level,Meta,BT,Config),
        MsgResult,
        do_format(Level,Meta,AT,Config)
    ],
    Result = lists:flatten(Result0),
    [thoas:encode_to_iodata(Result), "\n"].

-spec map_name(Key, Config) -> atom() when
      Key :: atom(),
      Config :: config().
map_name(Key, Config) ->
    Names = maps:get(names, Config),
    maps:get(Key, Names, Key).

-spec map_type(Key, Config) -> atom() | {atom(), atom()} when
      Key :: atom(),
      Config :: config().
map_type(Key, Config) ->
    Types = maps:get(types, Config),
    maps:get(Key, Types, Key).

do_format(Level,Data0,[all|_Format],Config) ->
    Data = maps:put(level,Level,Data0),
    lists:map(fun({K,V}) -> {map_name(K,Config), to_binary(K,V,Config)} end, maps:to_list(Data));
do_format(Level,Data,[level|Format],Config) ->
    [{map_name(level,Config),to_binary(map_type(level, Config),Level,Config)}|do_format(Level,Data,Format,Config)];
do_format(Level,Data,[{Key,IfExist,Else}|Format],Config) ->
    String0 =
        case value(Key,Data) of
            {ok,Value} -> do_format(Level,Data#{Key=>Value},IfExist,Config);
            error -> do_format(Level,Data,Else,Config)
        end,
    case String0 of
        [] ->
            do_format(Level,Data,Format,Config);
        String ->
            [{map_name(Key,Config),String}|do_format(Level,Data,Format,Config)]
    end;
do_format(Level,Data,[Key|Format],Config)
  when is_atom(Key) orelse
       (is_list(Key) andalso is_atom(hd(Key))) ->
    String0 =
        case value(Key,Data) of
            {ok,Value} -> to_binary(map_type(Key, Config),Value,Config);
            error -> []
        end,
    case String0 of
        [] ->
            do_format(Level,Data,Format,Config);
        String ->
            [{map_name(Key,Config),String}|do_format(Level,Data,Format,Config)]
    end;
do_format(Level,Data,[Str|Format],Config) ->
    [Str|do_format(Level,Data,Format,Config)];
do_format(_Level,_Data,[],_Config) ->
    [].

value(Key,Meta) when is_map_key(Key,Meta) ->
    {ok,maps:get(Key,Meta)};
value([Key|Keys],Meta) when is_map_key(Key,Meta) ->
    value(Keys,maps:get(Key,Meta));
value([],Value) ->
    {ok,Value};
value(_,_) ->
    error.

to_binary(Key,Value,Config) ->
    iolist_to_binary(to_string(Key,Value,Config)).

%% system_time is the system time in microseconds
to_string({level, OutputFormat}, Value, Config) ->
    format_level(OutputFormat, Value, Config);
to_string(system_time,Value,Config) ->
    format_time(Value,Config);
% to_string({system_time, OutputFormat},Value,Config) ->
%     format_time(OutputFormat, Value,Config);
to_string(mfa,Value,Config) ->
    format_mfa(Value,Config);
% to_string(crash_reason,Value,Config) ->
%     format_crash_reason(Value,Config);
to_string(_,Value,Config) ->
    to_string(Value,Config).

to_string(X,_) when is_atom(X) ->
    atom_to_list(X);
to_string(X,_) when is_integer(X) ->
    integer_to_list(X);
to_string(X,_) when is_pid(X) ->
    pid_to_list(X);
to_string(X,_) when is_reference(X) ->
    ref_to_list(X);
to_string(X,Config) when is_list(X) ->
    case printable_list(lists:flatten(X)) of
        true -> X;
        _ -> io_lib:format(p(Config),[X])
    end;
to_string(X,Config) ->
    io_lib:format(p(Config),[X]).

printable_list([]) ->
    false;
printable_list(X) ->
    io_lib:printable_list(X).

format_msg({string,Chardata},Meta,Config) ->
    format_msg({"~ts",[Chardata]},Meta,Config);
format_msg({report,_}=Msg,Meta,#{report_cb:=Fun}=Config)
  when is_function(Fun,1); is_function(Fun,2) ->
    format_msg(Msg,Meta#{report_cb=>Fun},maps:remove(report_cb,Config));
format_msg({report,Report},#{report_cb:=Fun}=Meta,Config) when is_function(Fun,1) ->
    try Fun(Report) of
        {Format,Args} when is_list(Format), is_list(Args) ->
            format_msg({Format,Args},maps:remove(report_cb,Meta),Config);
        Other ->
            P = p(Config),
            format_msg({"REPORT_CB/1 ERROR: "++P++"; Returned: "++P,
                        [Report,Other]},Meta,Config)
    catch C:R:S ->
            P = p(Config),
            format_msg({"REPORT_CB/1 CRASH: "++P++"; Reason: "++P,
                        [Report,{C,R,logger:filter_stacktrace(?MODULE,S)}]},
                       Meta,Config)
    end;
format_msg({report,Report},#{report_cb:=Fun}=Meta,Config) when is_function(Fun,2) ->
    try Fun(Report,maps:with([depth,chars_limit,single_line],Config)) of
        Chardata when ?IS_STRING(Chardata) ->
            try chardata_to_list(Chardata) % already size limited by report_cb
            catch _:_ ->
                    P = p(Config),
                    format_msg({"REPORT_CB/2 ERROR: "++P++"; Returned: "++P,
                                [Report,Chardata]},Meta,Config)
            end;
        Other ->
            P = p(Config),
            format_msg({"REPORT_CB/2 ERROR: "++P++"; Returned: "++P,
                        [Report,Other]},Meta,Config)
    catch C:R:S ->
            P = p(Config),
            format_msg({"REPORT_CB/2 CRASH: "++P++"; Reason: "++P,
                        [Report,{C,R,logger:filter_stacktrace(?MODULE,S)}]},
                       Meta,Config)
    end;
% format_msg({report,#{label:={error_logger,_}, format:=Format, args:=Args},Meta,Config) ->
%     format_msg({Format, Args}, Meta, Config);
format_msg({report,Report},_Meta,_Config) when is_map(Report) ->
    Report;
format_msg({report,Report},Meta,Config) ->
    format_msg({report,Report},
               Meta#{report_cb=>fun logger:format_report/1},
               Config);
format_msg(Msg,_Meta,#{depth:=Depth,chars_limit:=CharsLimit,
                       single_line:=Single}) ->
    Opts = chars_limit_to_opts(CharsLimit),
    format_msg(Msg, Depth, Opts, Single).

chars_limit_to_opts(unlimited) -> [];
chars_limit_to_opts(CharsLimit) -> [{chars_limit,CharsLimit}].

format_msg({Format0,Args},Depth,Opts,Single) ->
    try
        Format1 = io_lib:scan_format(Format0, Args),
        Format = reformat(Format1, Depth, Single),
        io_lib:build_text(Format,Opts)
    catch C:R:S ->
            P = p(Single),
            FormatError = "FORMAT ERROR: "++P++" - "++P,
            case Format0 of
                FormatError ->
                    %% already been here - avoid failing cyclically
                    erlang:raise(C,R,S);
                _ ->
                    format_msg({FormatError,[Format0,Args]},Depth,Opts,Single)
            end
    end.

reformat(Format,unlimited,false) ->
    Format;
reformat([#{control_char:=C}=M|T], Depth, true) when C =:= $p ->
    [limit_depth(M#{width => 0}, Depth)|reformat(T, Depth, true)];
reformat([#{control_char:=C}=M|T], Depth, true) when C =:= $P ->
    [M#{width => 0}|reformat(T, Depth, true)];
reformat([#{control_char:=C}=M|T], Depth, Single) when C =:= $p; C =:= $w ->
    [limit_depth(M, Depth)|reformat(T, Depth, Single)];
reformat([H|T], Depth, Single) ->
    [H|reformat(T, Depth, Single)];
reformat([], _, _) ->
    [].

limit_depth(M0, unlimited) ->
    M0;
limit_depth(#{control_char:=C0, args:=Args}=M0, Depth) ->
    C = C0 - ($a - $A),				%To uppercase.
    M0#{control_char:=C,args:=Args++[Depth]}.

chardata_to_list(Chardata) ->
    case unicode:characters_to_list(Chardata,unicode) of
        List when is_list(List) ->
            List;
        Error ->
            throw(Error)
    end.


% https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#LogSeverity
format_level(gcp, emergency, _Config) -> <<"EMERGENCY">>;
format_level(gcp, alert, _Config) -> <<"ALERT">>;
format_level(gcp, critical, _Config) -> <<"CRITICAL">>;
format_level(gcp, error, _Config) -> <<"ERROR">>;
format_level(gcp, warning, _Config) -> <<"WARNING">>;
format_level(gcp, notice, _Config) -> <<"INFO">>;
format_level(gcp, info, _Config) -> <<"INFO">>;
format_level(gcp, debug, _Config) -> <<"DEBUG">>;
format_level(gcp, _, _Config) -> <<"DEFAULT">>.

%% SysTime is the system time in microseconds
format_time(SysTime, Config)
  when is_integer(SysTime) ->
    #{time_offset:=Offset,time_designator:=Des} = Config,
    calendar:system_time_to_rfc3339(SysTime,[{unit,microsecond},
                                             {offset,Offset},
                                             {time_designator,Des}]).

format_mfa({M,F,A},_) when is_atom(M), is_atom(F), is_integer(A) ->
    io_lib:fwrite("~tw:~tw/~w", [M, F, A]);
format_mfa({M,F,A},Config) when is_atom(M), is_atom(F), is_list(A) ->
    format_mfa({M,F,length(A)},Config);
format_mfa(MFA,Config) ->
    to_string(MFA,Config).

% format_crash_reason({throw, Reason} ->
% format_crash_reason({exit, Reason} ->
% format_crash_reason({error, Exception, Stacktrace} ->

%% Ensure that all valid configuration parameters exist in the final
%% configuration map
-spec add_default_config(Config) -> config() when
      Config :: logger:formatter_config().
add_default_config(Config0) ->
    Default =
        #{chars_limit=>unlimited,
          error_logger_notice_header=>info,
          legacy_header=>false,
          single_line=>true,
          time_designator=>$T},
    MaxSize = get_max_size(maps:get(max_size,Config0,undefined)),
    Depth = get_depth(maps:get(depth,Config0,undefined)),
    Offset = get_offset(maps:get(time_offset,Config0,undefined)),
    Names = get_names(maps:get(names,Config0,#{})),
    Types = get_types(maps:get(types,Config0,#{})),
    add_default_template(maps:merge(Default,Config0#{max_size=>MaxSize,
                                                     depth=>Depth,
                                                     names=>Names,
                                                     types=>Types,
                                                     time_offset=>Offset})).

add_default_template(#{template:=_}=Config) ->
    Config;
add_default_template(Config) ->
    Config#{template=>default_template(Config)}.

default_template(_) ->
    [msg,all].

% default_template(_) ->
%     [
%      time,
%      level,
%      msg,
%      file,
%      line,
%      mfa,
%      pid,
%      trace_id,
%      span_id
%     ].

get_max_size(undefined) ->
    unlimited;
get_max_size(S) ->
    max(10,S).

get_depth(undefined) ->
    error_logger:get_format_depth();
get_depth(S) ->
    max(5,S).

get_names(Names) when is_list(Names) ->
    lists:foldl(fun(M, Acc) -> maps:merge(Acc, default_names(M)) end, #{}, Names);
get_names(Names) ->
    default_names(Names).

-spec default_names(Names) -> map() when
      Names :: atom() | map().
default_names(Names) when is_map(Names) ->
    Names;
default_names(datadog) ->
    % https://docs.datadoghq.com/logs/log_configuration/processors/
    % https://docs.datadoghq.com/logs/log_configuration/attributes_naming_convention/#source-code
    % https://docs.datadoghq.com/tracing/faq/why-cant-i-see-my-correlated-logs-in-the-trace-id-panel/?tab=jsonlogs
    #{
      time => <<"date">>,
      level => <<"status">>,
      msg => <<"message">>,
      trace_id => <<"dd.trace_id">>,
      span_id => <<"dd.span_id">>,
      % level => <<"syslog.severity">>,
      % time => <<"syslog.timestamp">>,
      file => <<"logger.file_name">>,
      mfa => <<"logger.method_name">>,
      pid => <<"logger.thread_name">>
      % error.kind	string	The error type or kind (or code in some cases).
      % error.message	string	A concise, human-readable, one-line message explaining the event.
      % error.stack	string	The stack trace or the complementary information about the error.
    };
default_names(undefined) ->
    #{}.


get_types(Types) when is_list(Types) ->
    Defaults = #{
      time => system_time,
      level => level,
      mfa => mfa,
      initial_call => mfa
    },
    lists:foldl(fun(M, Acc) -> maps:merge(Acc, default_types(M)) end, Defaults, Types);
get_types(Types) ->
    default_types(Types).

-spec default_types(Types) -> map() when
      Types :: atom() | map().
default_types(Types) when is_map(Types) ->
    Types;
default_types(gcp) ->
    % https://cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#LogSeverity
    #{
      level => {level, gcp}
    };
default_types(undefined) ->
    #{}.

get_offset(undefined) ->
    utc_to_offset(get_utc_config());
get_offset(Offset) ->
    Offset.

utc_to_offset(true) ->
    "Z";
utc_to_offset(false) ->
    "".

get_utc_config() ->
    %% SASL utc_log overrides stdlib config - in order to have uniform
    %% timestamps in log messages
    case application:get_env(sasl, utc_log) of
        {ok, Val} when is_boolean(Val) -> Val;
        _ ->
            case application:get_env(stdlib, utc_log) of
                {ok, Val} when is_boolean(Val) -> Val;
                _ -> false
            end
    end.

-spec check_config(Config) -> ok | {error,term()} when
      Config :: config().
check_config(Config) when is_map(Config) ->
    do_check_config(maps:to_list(Config));
check_config(Config) ->
    {error,{invalid_formatter_config,?MODULE,Config}}.

do_check_config([{Type,L}|Config]) when Type == chars_limit;
                                        Type == depth;
                                        Type == max_size ->
    case check_limit(L) of
        ok -> do_check_config(Config);
        error -> {error,{invalid_formatter_config,?MODULE,{Type,L}}}
    end;
do_check_config([{single_line,SL}|Config]) when is_boolean(SL) ->
    do_check_config(Config);
do_check_config([{legacy_header,LH}|Config]) when is_boolean(LH) ->
    do_check_config(Config);
do_check_config([{error_logger_notice_header,ELNH}|Config]) when ELNH == info;
                                                                 ELNH == notice ->
    do_check_config(Config);
do_check_config([{report_cb,RCB}|Config]) when is_function(RCB,1);
                                               is_function(RCB,2) ->
    do_check_config(Config);
do_check_config([{template,T}|Config]) ->
    case check_template(T) of
        ok -> do_check_config(Config);
        error -> {error,{invalid_formatter_template,?MODULE,T}}
    end;
do_check_config([{time_offset,Offset}|Config]) ->
    case check_offset(Offset) of
        ok ->
            do_check_config(Config);
        error ->
            {error,{invalid_formatter_config,?MODULE,{time_offset,Offset}}}
    end;
do_check_config([{names,Names}|Config]) ->
    case check_names(Names) of
        ok ->
            do_check_config(Config);
        error ->
            {error,{invalid_formatter_config,?MODULE,{names,Names}}}
    end;
do_check_config([{types,Names}|Config]) ->
    case check_types(Names) of
        ok ->
            do_check_config(Config);
        error ->
            {error,{invalid_formatter_config,?MODULE,{types,Names}}}
    end;
do_check_config([{time_designator,Char}|Config]) when Char>=0, Char=<255 ->
    case io_lib:printable_latin1_list([Char]) of
        true ->
            do_check_config(Config);
        false ->
            {error,{invalid_formatter_config,?MODULE,{time_designator,Char}}}
    end;
do_check_config([C|_]) ->
    {error,{invalid_formatter_config,?MODULE,C}};
do_check_config([]) ->
    ok.

check_limit(L) when is_integer(L), L>0 ->
    ok;
check_limit(unlimited) ->
    ok;
check_limit(_) ->
    error.

check_template([Key|T]) when is_atom(Key) ->
    check_template(T);
check_template([Key|T]) when is_list(Key), is_atom(hd(Key)) ->
    case lists:all(fun(X) when is_atom(X) -> true;
                      (_) -> false
                   end,
                   Key) of
        true ->
            check_template(T);
        false ->
            error
    end;
check_template([{Key,IfExist,Else}|T])
  when is_atom(Key) orelse
       (is_list(Key) andalso is_atom(hd(Key))) ->
    case check_template(IfExist) of
        ok ->
            case check_template(Else) of
                ok ->
                    check_template(T);
                error ->
                    error
            end;
        error ->
            error
    end;
check_template([Str|T]) when is_list(Str) ->
    case io_lib:printable_unicode_list(Str) of
        true -> check_template(T);
        false -> error
    end;
check_template([Bin|T]) when is_binary(Bin) ->
    case unicode:characters_to_list(Bin) of
        Str when is_list(Str) -> check_template([Str|T]);
        _Error -> error
    end;
check_template([]) ->
    ok;
check_template(_) ->
    error.

check_names(Names) when is_atom(Names) ->
    ok;
check_names(Names) when is_map(Names) ->
    ok;
check_names(Names) when is_list(Names) ->
    case lists:all(fun(N) -> is_atom(N) orelse is_map(N) end, Names) of
        true ->
            ok;
        false ->
            error
    end;
check_names(_) ->
    error.

check_types(Types) when is_atom(Types) ->
    ok;
check_types(Types) when is_map(Types) ->
    ok;
check_types(Types) when is_list(Types) ->
    case lists:all(fun(N) -> is_atom(N) orelse is_map(N) end, Types) of
        true ->
            ok;
        false ->
            error
    end;
check_types(_) ->
    error.

check_offset(I) when is_integer(I) ->
    ok;
check_offset(Tz) when Tz=:=""; Tz=:="Z"; Tz=:="z" ->
    ok;
check_offset([Sign|Tz]) when Sign=:=$+; Sign=:=$- ->
    check_timezone(Tz);
check_offset(_) ->
    error.

check_timezone(Tz) ->
    try io_lib:fread("~d:~d", Tz) of
        {ok, [_, _], []} ->
            ok;
        _ ->
            error
    catch _:_ ->
            error
    end.

p(#{single_line:=Single}) ->
    p(Single);
p(true) ->
    "~0tp";
p(false) ->
    "~tp".
