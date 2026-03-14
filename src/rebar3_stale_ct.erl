-module(rebar3_stale_ct).

-behaviour(provider).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, ct).
-define(NAMESPACE, stale).
-define(DEPS, [{default, compile}]).

init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {namespace, ?NAMESPACE},
        {module, ?MODULE},
        {bare, true},
        {deps, ?DEPS},
        {example, "rebar3 stale ct"},
        {opts, [
            {all, $a, "all", boolean, "Run all tests, ignoring stale detection"}
        ]},
        {short_desc, "Run only stale Common Test suites"},
        {desc,
            "Detects which modules changed since the last successful test run "
            "and only runs affected Common Test suites."}
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
    rebar_api:info("stale: running all Common Test suites", []),
    case rebar_prv_common_test:do(State) of
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
            rebar_api:info("stale: no manifest found, running all Common Test suites", []),
            case rebar_prv_common_test:do(State) of
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
                    rebar_api:info("stale: no changes detected, skipping Common Test suites", []),
                    {ok, State};
                _ ->
                    Affected = rebar3_stale_deps:affected_modules(State, Changed),
                    Suites = filter_ct_suites(Affected),
                    case Suites of
                        [] ->
                            rebar_api:info(
                                "stale: changes detected but no Common Test suites affected", []
                            ),
                            rebar3_stale_manifest:save(State, Current),
                            {ok, State};
                        _ ->
                            rebar_api:info(
                                "stale: running ~B affected Common Test suite(s)",
                                [length(Suites)]
                            ),
                            run_ct_suites(State, Suites, Current)
                    end
            end
    end.

run_ct_suites(State, Suites, Current) ->
    SuiteStrs = [atom_to_list(S) || S <- Suites],
    {Opts, _} = rebar_state:command_parsed_args(State),
    NewOpts = [{suite, string:join(SuiteStrs, ",")} | Opts],
    State1 = rebar_state:command_parsed_args(State, {NewOpts, []}),
    case rebar_prv_common_test:do(State1) of
        {ok, State2} ->
            rebar3_stale_manifest:save(State2, Current),
            {ok, State2};
        Error ->
            Error
    end.

filter_ct_suites(Modules) ->
    [M || M <- Modules, is_ct_suite(M)].

is_ct_suite(Mod) ->
    Name = atom_to_list(Mod),
    lists:suffix("_SUITE", Name).
