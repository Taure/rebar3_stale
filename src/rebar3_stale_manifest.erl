-module(rebar3_stale_manifest).

-export([
    load/1,
    save/2,
    current_checksums/1,
    changed_modules/2,
    manifest_path/1,
    checksum_file/1
]).

-define(VERSION, 1).

-spec manifest_path(rebar_state:t()) -> file:filename().
manifest_path(State) ->
    RootDir = rebar_dir:root_dir(State),
    filename:join([RootDir, "_build", "test", ".rebar3_stale_manifest"]).

-spec load(rebar_state:t()) -> {ok, map()} | {error, not_found}.
load(State) ->
    load_file(manifest_path(State)).

-spec load_file(file:filename()) -> {ok, map()} | {error, not_found}.
load_file(Path) ->
    rebar_api:info("stale: loading manifest from ~s", [Path]),
    case file:consult(Path) of
        {ok, [#{version := ?VERSION, checksums := Encoded}]} ->
            Checksums = maps:map(fun(_K, V) -> hex_to_binary(V) end, Encoded),
            {ok, Checksums};
        {ok, Other} ->
            rebar_api:info("stale: unexpected manifest format: ~p", [Other]),
            {error, not_found};
        {error, Reason} ->
            rebar_api:info("stale: could not read manifest: ~p", [Reason]),
            {error, not_found}
    end.

-spec save(rebar_state:t(), map()) -> ok.
save(State, Checksums) ->
    Path = manifest_path(State),
    filelib:ensure_dir(Path),
    %% Encode binary checksums as hex strings for file:consult/1 compatibility
    Encoded = maps:map(fun(_K, V) -> binary_to_hex(V) end, Checksums),
    Term = #{version => ?VERSION, checksums => Encoded},
    Data = io_lib:format("~tp.~n", [Term]),
    ok = file:write_file(Path, Data).

-spec current_checksums(rebar_state:t()) -> map().
current_checksums(State) ->
    SrcDirs = source_dirs(State),
    Files = collect_files(SrcDirs),
    maps:from_list([checksum_file(F) || F <- Files]).

-spec changed_modules(map(), map()) -> ordsets:ordset(module()).
changed_modules(Old, Current) ->
    AllKeys = lists:usort(maps:keys(Old) ++ maps:keys(Current)),
    ordsets:from_list([
        Mod
     || Mod <- AllKeys,
        maps:get(Mod, Old, undefined) =/= maps:get(Mod, Current, undefined)
    ]).

%%====================================================================
%% Internal
%%====================================================================

source_dirs(State) ->
    Apps = project_apps(State),
    lists:flatmap(
        fun(AppInfo) ->
            AppDir = rebar_app_info:dir(AppInfo),
            [
                filename:join(AppDir, "src"),
                filename:join(AppDir, "include"),
                filename:join(AppDir, "test")
            ]
        end,
        Apps
    ).

project_apps(State) ->
    case rebar_state:current_app(State) of
        undefined -> rebar_state:project_apps(State);
        AppInfo -> [AppInfo]
    end.

collect_files(Dirs) ->
    lists:flatmap(
        fun(Dir) ->
            case filelib:is_dir(Dir) of
                true ->
                    ErlFiles = filelib:wildcard(filename:join([Dir, "**", "*.erl"])),
                    HrlFiles = filelib:wildcard(filename:join([Dir, "**", "*.hrl"])),
                    ErlFiles ++ HrlFiles;
                false ->
                    []
            end
        end,
        Dirs
    ).

checksum_file(FilePath) ->
    {ok, Bin} = file:read_file(FilePath),
    Hash = crypto:hash(md5, Bin),
    Mod = list_to_atom(filename:basename(FilePath, filename:extension(FilePath))),
    {Mod, Hash}.

binary_to_hex(Bin) ->
    list_to_binary([io_lib:format("~2.16.0b", [B]) || <<B>> <= Bin]).

hex_to_binary(Hex) ->
    Str = binary_to_list(Hex),
    list_to_binary([list_to_integer([H, L], 16) || <<H, L>> <= list_to_binary(Str)]).
