-module(rebar3_stale).

-export([init/1]).

init(State0) ->
    {ok, State1} = rebar3_stale_eunit:init(State0),
    {ok, State2} = rebar3_stale_ct:init(State1),
    {ok, State2}.
