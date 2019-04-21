%%%-------------------------------------------------------------------
%%% @author dmitryditas
%%% @copyright (C) 2018, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 27. Нояб. 2018 17:13
%%%-------------------------------------------------------------------
-module(es3_sup).
-author("dmitryditas").

-behaviour(supervisor).

%% API
-export([
    start_link/0
]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, {SupFlags :: {RestartStrategy :: supervisor:strategy(),
        MaxR :: non_neg_integer(), MaxT :: non_neg_integer()},
        [ChildSpec :: supervisor:child_spec()]
    }} |
    ignore |
    {error, Reason :: term()}).
init([]) ->
    
    io:format("---------INIT ~p~n", [{?MODULE, init}]),
    
    RestartStrategy = one_for_one,
    MaxRestarts = 10,
    MaxSecondsBetweenRestarts = 60,
    
    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
    
    Restart = permanent,
    Shutdown = infinity,
    Type = worker,
    
    AChild = {metadata, {metadata_handler, start_link, []},
        Restart, Shutdown, Type, [metadata_handler]},

    AChild1 = {chunks, {chunk_controller, start_link, []},
        Restart, Shutdown, Type, [chunk_controller]},

    _AChild1 = {executor_controller, {executor_controller, start_link, []},
        Restart, Shutdown, Type, [executor_controller]},

    _AChild2 = {reducer_controller, {reducer_controller, start_link, []},
        Restart, Shutdown, Type, [reducer_controller]},
    
    {ok, {SupFlags, [AChild, AChild1]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
