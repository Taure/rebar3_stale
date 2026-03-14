-module(rebar3_stale_deps).

-export([
    affected_modules/2,
    build_graph/1
]).

-spec affected_modules(rebar_state:t(), ordsets:ordset(module())) ->
    ordsets:ordset(module()).
affected_modules(State, ChangedModules) ->
    BeamDirs = beam_dirs(State),
    Graph = build_graph(BeamDirs),
    try
        Affected = reachable(ChangedModules, Graph),
        ordsets:union(ChangedModules, Affected)
    after
        digraph:delete(Graph)
    end.

-spec build_graph([file:filename()]) -> digraph:graph().
build_graph(BeamDirs) ->
    Graph = digraph:new([acyclic]),
    BeamFiles = lists:flatmap(
        fun(Dir) ->
            filelib:wildcard(filename:join(Dir, "*.beam"))
        end,
        BeamDirs
    ),
    lists:foreach(fun(Beam) -> add_edges(Graph, Beam) end, BeamFiles),
    Graph.

%%====================================================================
%% Internal
%%====================================================================

beam_dirs(State) ->
    Apps = project_apps(State),
    RootDir = rebar_dir:root_dir(State),
    AppDirs = [
        filename:join(rebar_app_info:out_dir(AppInfo), "ebin")
     || AppInfo <- Apps
    ],
    %% Also include test beams
    TestDirs = [
        filename:join([
            RootDir, "_build", "test", "lib", binary_to_list(rebar_app_info:name(AppInfo)), "test"
        ])
     || AppInfo <- Apps
    ],
    [D || D <- AppDirs ++ TestDirs, filelib:is_dir(D)].

project_apps(State) ->
    case rebar_state:current_app(State) of
        undefined -> rebar_state:project_apps(State);
        AppInfo -> [AppInfo]
    end.

add_edges(Graph, BeamFile) ->
    case beam_lib:chunks(BeamFile, [imports]) of
        {ok, {Mod, [{imports, Imports}]}} ->
            ensure_vertex(Graph, Mod),
            ImportedMods = lists:usort([M || {M, _F, _A} <- Imports]),
            lists:foreach(
                fun(Dep) ->
                    ensure_vertex(Graph, Dep),
                    %% Edge: Dep -> Mod (if Dep changes, Mod is affected)
                    case digraph:add_edge(Graph, Dep, Mod) of
                        {error, {bad_edge, _}} ->
                            %% Would create a cycle, skip
                            ok;
                        _ ->
                            ok
                    end
                end,
                ImportedMods
            );
        _ ->
            ok
    end.

ensure_vertex(Graph, V) ->
    case digraph:vertex(Graph, V) of
        false -> digraph:add_vertex(Graph, V);
        _ -> ok
    end.

reachable(Modules, Graph) ->
    Reached = digraph_utils:reachable(Modules, Graph),
    ordsets:subtract(ordsets:from_list(Reached), ordsets:from_list(Modules)).
