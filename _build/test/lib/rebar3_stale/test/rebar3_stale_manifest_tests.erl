-module(rebar3_stale_manifest_tests).

-include_lib("eunit/include/eunit.hrl").

checksum_consistency_test() ->
    %% Same content should produce same checksum
    Dir = make_temp_dir(),
    File = filename:join(Dir, "test.erl"),
    ok = file:write_file(File, "-module(test).\n"),
    {test, Hash1} = rebar3_stale_manifest:checksum_file(File),
    {test, Hash2} = rebar3_stale_manifest:checksum_file(File),
    ?assertEqual(Hash1, Hash2),
    cleanup_dir(Dir).

checksum_changes_on_modification_test() ->
    Dir = make_temp_dir(),
    File = filename:join(Dir, "test.erl"),
    ok = file:write_file(File, "-module(test).\n"),
    {test, Hash1} = rebar3_stale_manifest:checksum_file(File),
    ok = file:write_file(File, "-module(test).\n-export([foo/0]).\n"),
    {test, Hash2} = rebar3_stale_manifest:checksum_file(File),
    ?assertNotEqual(Hash1, Hash2),
    cleanup_dir(Dir).

changed_modules_detects_new_test() ->
    Old = #{foo => <<1, 2, 3>>},
    Current = #{foo => <<1, 2, 3>>, bar => <<4, 5, 6>>},
    Changed = rebar3_stale_manifest:changed_modules(Old, Current),
    ?assertEqual([bar], Changed).

changed_modules_detects_deleted_test() ->
    Old = #{foo => <<1, 2, 3>>, bar => <<4, 5, 6>>},
    Current = #{foo => <<1, 2, 3>>},
    Changed = rebar3_stale_manifest:changed_modules(Old, Current),
    ?assertEqual([bar], Changed).

changed_modules_detects_modified_test() ->
    Old = #{foo => <<1, 2, 3>>},
    Current = #{foo => <<9, 9, 9>>},
    Changed = rebar3_stale_manifest:changed_modules(Old, Current),
    ?assertEqual([foo], Changed).

changed_modules_empty_when_identical_test() ->
    Checksums = #{foo => <<1, 2, 3>>, bar => <<4, 5, 6>>},
    Changed = rebar3_stale_manifest:changed_modules(Checksums, Checksums),
    ?assertEqual([], Changed).

manifest_roundtrip_test() ->
    Dir = make_temp_dir(),
    Path = filename:join(Dir, ".manifest"),
    Checksums = #{foo => crypto:hash(md5, "hello"), bar => crypto:hash(md5, "world")},
    Term = #{version => 1, checksums => Checksums},
    Data = io_lib:format("~tp.~n", [Term]),
    ok = file:write_file(Path, Data),
    {ok, [Loaded]} = file:consult(Path),
    ?assertEqual(Checksums, maps:get(checksums, Loaded)),
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
    Files = filelib:wildcard(filename:join(Dir, "*")),
    lists:foreach(fun file:delete/1, Files),
    file:del_dir(Dir).
