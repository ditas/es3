%%%-------------------------------------------------------------------
%%% @author d.pravosudov
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Апр. 2019 22:19
%%%-------------------------------------------------------------------
-module(chunk_controller).
-author("d.pravosudov").

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    initialize/2,
    initialize_local/2,
    write/2,
    write_local/3
]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
    chunks_handlers = #{},
    chunks_counters = #{}
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

initialize(FileName, Length) ->
    gen_server:call(?SERVER, {initialize, FileName, Length}, infinity).

initialize_local(FileName, I) ->
    gen_server:call(?SERVER, {initialize_local, FileName, I}, infinity).

write(FileName, Data) ->
    gen_server:call(?SERVER, {write, FileName, Data}, infinity).

write_local(FileName, Data, CurrentChunksCounter) ->
    gen_server:call(?SERVER, {write_local, FileName, Data, CurrentChunksCounter}, infinity).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([]) ->
    process_flag(trap_exit, true),
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call({initialize, FileName, Length}, _From, State) ->
    {ok, ChunkSize} = application:get_env(es3, chunk_size),
    ChunksCount = ceil(Length/ChunkSize),

    lager:debug("---------INITIALIZE ~p", [{?MODULE, node()}]),

    State1 = prepare(FileName, ChunksCount, State),

    {reply, initialized, State1};
handle_call({initialize_local, FileName, I}, _From, #state{chunks_handlers = CH} = State) ->
    CurrentChunksHandlers = maps:get(FileName, CH, []),
    {ok, Pid} = chunk_handler:start_link(FileName, I),
    {reply, initialized, State#state{chunks_handlers = maps:put(FileName, [{I, Pid, passive}|CurrentChunksHandlers], CH)}};
handle_call({write, FileName, Data}, _From, #state{chunks_handlers = CH, chunks_counters = CC} = State) ->
    CurrentChunksHandlers = maps:get(FileName, CH, []),
    CurrentChunksCounter = maps:get(FileName, CC),
    Nodes = nodes(),
    N = length(Nodes) + 1,
    CH1 = case (CurrentChunksCounter rem N) of
        0 ->
            CurrentChunksHandlers1 = do_write(CurrentChunksHandlers, Data, CurrentChunksCounter),
            maps:put(FileName, CurrentChunksHandlers1, CH);
        Rem ->
            Node = lists:nth(Rem, Nodes),
            case rpc:call(Node, chunk_controller, write_local, [FileName, Data, CurrentChunksCounter]) of
                {badrpc, Reason} ->
                    lager:error("node start failed ~p ~p", [Node, Reason]);
                Answer -> %% saved
                    lager:debug("file saved on node ~p ~p", [Node, Answer])
            end,
            CH
    end,
    {reply, saved, State#state{chunks_handlers = CH1, chunks_counters = maps:put(FileName, CurrentChunksCounter - 1, CC)}};
handle_call({write_local, FileName, Data, CC}, _From, #state{chunks_handlers = CH} = State) ->
    CurrentChunksHandlers = maps:get(FileName, CH, []),
    CurrentChunksHandlers1 = do_write(CurrentChunksHandlers, Data, CC),
    {reply, saved, State#state{chunks_handlers = maps:put(FileName, CurrentChunksHandlers1, CH)}};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->

    lager:error("----TRAPPED EXIT ~p", [_Info]),

    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
prepare(FileName, ChunksCount, State) ->
    Nodes = nodes(),
    N = length(Nodes) + 1,
    State1 = lists:foldl(fun(I, #state{chunks_handlers = CH, chunks_counters = CC} = S) ->
        case (I rem N) of
            0 ->

                io:format("---PREPARE LOCAL---~n"),

                CurrentChunkHandlers = maps:get(FileName, CH, []),
                {ok, Pid} = chunk_handler:start_link(FileName, I),
                S1 = S#state{chunks_handlers = maps:put(FileName, [{I, Pid, passive}|CurrentChunkHandlers], CH), chunks_counters = maps:put(FileName, ChunksCount, CC)},
                S1;
            Rem ->

                io:format("---PREPARE REMOTE---~n"),

                Node = lists:nth(Rem, Nodes),
                case rpc:call(Node, chunk_controller, initialize_local, [FileName, I]) of
                    {badrpc, Reason} ->
                        lager:error("node start failed ~p ~p", [Node, Reason]);
                    Answer -> %% initialized
                        lager:debug("chunk handlers started on node ~p ~p", [Node, Answer])
                end,
                S
        end
    end, State, lists:seq(1, ChunksCount)),

    io:format("---PREPARE ALL DONE--- ~p~n", [State1]),

    State1.

do_write(ChunksHandlers, Data, ChunksCounter) ->
    do_write(ChunksHandlers, Data, ChunksCounter, []).

do_write([{I, Pid, active}|T], Data, ChunksCounter, ActiveCH) ->
    do_write(T, Data, ChunksCounter, [{I, Pid, active}|ActiveCH]);
do_write([{I, Pid, passive}|T], Data, ChunksCounter, ActiveCH) ->
    ok = chunk_handler:write(Pid, Data, ChunksCounter),
    [{I, Pid, active}|ActiveCH] ++ T.



