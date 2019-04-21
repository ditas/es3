%%%-------------------------------------------------------------------
%%% @author pravosudov
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 14. Sep 2017 18:22
%%%-------------------------------------------------------------------
-module(es3_app).
-author("pravosudov").

-behaviour(application).

%% Application callbacks
-export([start/2,
         stop/1]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @end
%%--------------------------------------------------------------------
-spec(start(StartType :: normal | {takeover, node()} | {failover, node()},
            StartArgs :: term()) ->
               {ok, pid()} |
               {ok, pid(), State :: term()} |
               {error, Reason :: term()}).
start(_StartType, _StartArgs) ->
    
    {ok, Nodes} = application:get_env(es3, nodes),

    io:format("---------START ~p~n", [Nodes]),

    lists:foreach(fun(N) ->
        Res = net_adm:ping(N),

        io:format("---------START ~p~n", [Res])

    end, Nodes),
    
    io:format("---------START ~p~n", [{?MODULE, start}]),

    Dispatch = cowboy_router:compile([
        {'_', [{"/", es3_api_handler, []}]}
    ]),
    {ok, _} = cowboy:start_clear(es3_api,
        [{port, 5555}],
        #{env => #{dispatch => Dispatch}}
    ),
    
    case es3_sup:start_link() of
        {ok, Pid} ->
            {ok, Pid};
        Error ->
            Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application has stopped. It
%% is intended to be the opposite of Module:start/2 and should do
%% any necessary cleaning up. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec(stop(State :: term()) -> term()).
stop(_State) ->
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================
