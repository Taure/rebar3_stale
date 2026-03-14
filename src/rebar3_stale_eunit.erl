-module(rebar3_stale_eunit).

-behaviour(provider).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, eunit).
-define(NAMESPACE, stale).
-define(DEPS, [{default, app_discovery}]).

init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {namespace, ?NAMESPACE},
        {module, ?MODULE},
        {bare, true},
        {deps, ?DEPS},
        {profiles, [test]},
        {example, "rebar3 stale eunit"},
        {opts, [
            {all, $a, "all", boolean, "Run all tests, ignoring stale detection"}
        ]},
        {short_desc, "Run only stale EUnit tests"},
        {desc,
            "Detects which modules changed since the last successful test run "
            "and only runs affected EUnit tests."}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

do(State) ->
    {Args, _} = rebar_state:command_parsed_args(State),
    RunAll = proplists:get_value(all, Args, false),
    case RunAll of
        true ->
            run_all(State);
        false ->
            run_stale(State)
    end.

format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%%====================================================================
%% Internal
%%====================================================================

run_all(State) ->
    rebar_api:info("stale: running all EUnit tests", []),
    case rebar_prv_eunit:do(State) of
        {ok, State1} ->
            Checksums = rebar3_stale_manifest:current_checksums(State1),
            rebar3_stale_manifest:save(State1, Checksums),
            {ok, State1};
        Error ->
            Error
    end.

run_stale(State) ->
    Current = rebar3_stale_manifest:current_checksums(State),
    case rebar3_stale_manifest:load(State) of
        {error, not_found} ->
            rebar_api:info("stale: no manifest found, running all EUnit tests", []),
            case rebar_prv_eunit:do(State) of
                {ok, State1} ->
                    rebar3_stale_manifest:save(State1, Current),
                    {ok, State1};
                Error ->
                    Error
            end;
        {ok, Old} ->
            Changed = rebar3_stale_manifest:changed_modules(Old, Current),
            case Changed of
                [] ->
                    rebar_api:info("stale: no changes detected, skipping EUnit tests", []),
                    {ok, State};
                _ ->
                    Affected = rebar3_stale_deps:affected_modules(State, Changed),
                    TestMods = filter_eunit_modules(Affected),
                    case TestMods of
                        [] ->
                            rebar_api:info(
                                "stale: changes detected but no EUnit tests affected", []
                            ),
                            rebar3_stale_manifest:save(State, Current),
                            {ok, State};
                        _ ->
                            rebar_api:info(
                                "stale: running ~B affected EUnit test module(s)",
                                [length(TestMods)]
                            ),
                            run_eunit_modules(State, TestMods, Current)
                    end
            end
    end.

run_eunit_modules(State, Modules, Current) ->
    ModStrs = [atom_to_list(M) || M <- Modules],
    %% Inject --module flag for each test module
    {Opts, _} = rebar_state:command_parsed_args(State),
    NewOpts = [{module, string:join(ModStrs, ",")} | Opts],
    State1 = rebar_state:command_parsed_args(State, {NewOpts, []}),
    case rebar_prv_eunit:do(State1) of
        {ok, State2} ->
            rebar3_stale_manifest:save(State2, Current),
            {ok, State2};
        Error ->
            Error
    end.

filter_eunit_modules(Modules) ->
    [M || M <- Modules, is_eunit_module(M)].

is_eunit_module(Mod) ->
    Name = atom_to_list(Mod),
    lists:suffix("_tests", Name) orelse lists:suffix("_test", Name).
