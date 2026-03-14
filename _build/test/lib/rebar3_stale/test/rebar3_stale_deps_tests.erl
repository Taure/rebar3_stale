-module(rebar3_stale_deps_tests).

-include_lib("eunit/include/eunit.hrl").

build_graph_empty_test() ->
    Graph = rebar3_stale_deps:build_graph([]),
    ?assertEqual([], digraph:vertices(Graph)),
    digraph:delete(Graph).

build_graph_from_beams_test() ->
    Dir = make_temp_dir(),
    %% Create two modules: dep_mod and caller_mod where caller imports dep_mod
    DepSrc = filename:join(Dir, "dep_mod.erl"),
    CallerSrc = filename:join(Dir, "caller_mod.erl"),
    ok = file:write_file(DepSrc, "-module(dep_mod).\n-export([hello/0]).\nhello() -> world.\n"),
    ok = file:write_file(
        CallerSrc,
        "-module(caller_mod).\n-export([go/0]).\ngo() -> dep_mod:hello().\n"
    ),
    {ok, dep_mod, DepBin} = compile:file(DepSrc, [binary, debug_info]),
    {ok, caller_mod, CallerBin} = compile:file(CallerSrc, [binary, debug_info]),
    EbinDir = filename:join(Dir, "ebin"),
    ok = filelib:ensure_dir(filename:join(EbinDir, ".")),
    ok = file:write_file(filename:join(EbinDir, "dep_mod.beam"), DepBin),
    ok = file:write_file(filename:join(EbinDir, "caller_mod.beam"), CallerBin),

    Graph = rebar3_stale_deps:build_graph([EbinDir]),
    %% dep_mod -> caller_mod edge should exist (if dep changes, caller is affected)
    Reachable = digraph_utils:reachable([dep_mod], Graph),
    ?assert(lists:member(caller_mod, Reachable)),
    digraph:delete(Graph),
    cleanup_dir(Dir).

no_false_dependency_test() ->
    Dir = make_temp_dir(),
    %% Two independent modules
    ModASrc = filename:join(Dir, "mod_a.erl"),
    ModBSrc = filename:join(Dir, "mod_b.erl"),
    ok = file:write_file(ModASrc, "-module(mod_a).\n-export([a/0]).\na() -> 1.\n"),
    ok = file:write_file(ModBSrc, "-module(mod_b).\n-export([b/0]).\nb() -> 2.\n"),
    {ok, mod_a, ABin} = compile:file(ModASrc, [binary, debug_info]),
    {ok, mod_b, BBin} = compile:file(ModBSrc, [binary, debug_info]),
    EbinDir = filename:join(Dir, "ebin"),
    ok = filelib:ensure_dir(filename:join(EbinDir, ".")),
    ok = file:write_file(filename:join(EbinDir, "mod_a.beam"), ABin),
    ok = file:write_file(filename:join(EbinDir, "mod_b.beam"), BBin),

    Graph = rebar3_stale_deps:build_graph([EbinDir]),
    Reachable = digraph_utils:reachable([mod_a], Graph),
    ?assertNot(lists:member(mod_b, Reachable)),
    digraph:delete(Graph),
    cleanup_dir(Dir).

transitive_dependency_test() ->
    Dir = make_temp_dir(),
    %% a -> b -> c (c calls b, b calls a)
    ASrc = filename:join(Dir, "trans_a.erl"),
    BSrc = filename:join(Dir, "trans_b.erl"),
    CSrc = filename:join(Dir, "trans_c.erl"),
    ok = file:write_file(ASrc, "-module(trans_a).\n-export([a/0]).\na() -> ok.\n"),
    ok = file:write_file(
        BSrc, "-module(trans_b).\n-export([b/0]).\nb() -> trans_a:a().\n"
    ),
    ok = file:write_file(
        CSrc, "-module(trans_c).\n-export([c/0]).\nc() -> trans_b:b().\n"
    ),
    {ok, trans_a, ABin} = compile:file(ASrc, [binary, debug_info]),
    {ok, trans_b, BBin} = compile:file(BSrc, [binary, debug_info]),
    {ok, trans_c, CBin} = compile:file(CSrc, [binary, debug_info]),
    EbinDir = filename:join(Dir, "ebin"),
    ok = filelib:ensure_dir(filename:join(EbinDir, ".")),
    ok = file:write_file(filename:join(EbinDir, "trans_a.beam"), ABin),
    ok = file:write_file(filename:join(EbinDir, "trans_b.beam"), BBin),
    ok = file:write_file(filename:join(EbinDir, "trans_c.beam"), CBin),

    Graph = rebar3_stale_deps:build_graph([EbinDir]),
    %% Changing trans_a should affect both trans_b and trans_c transitively
    Reachable = digraph_utils:reachable([trans_a], Graph),
    ?assert(lists:member(trans_b, Reachable)),
    ?assert(lists:member(trans_c, Reachable)),
    digraph:delete(Graph),
    cleanup_dir(Dir).

%%====================================================================
%% Helpers
%%====================================================================

make_temp_dir() ->
    Base = filename:basedir(user_cache, "rebar3_stale_test"),
    Dir = filename:join(Base, integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_dir(filename:join(Dir, ".")),
    Dir.

cleanup_dir(Dir) ->
    cleanup_dir_recursive(Dir).

cleanup_dir_recursive(Dir) ->
    case file:list_dir(Dir) of
        {ok, Entries} ->
            lists:foreach(
                fun(Entry) ->
                    Path = filename:join(Dir, Entry),
                    case filelib:is_dir(Path) of
                        true -> cleanup_dir_recursive(Path);
                        false -> file:delete(Path)
                    end
                end,
                Entries
            ),
            file:del_dir(Dir);
        _ ->
            ok
    end.
