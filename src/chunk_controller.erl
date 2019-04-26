-module(chunk_controller).
-author("d.pravosudov").

-behaviour(gen_server).

-include_lib("kernel/include/file.hrl").

%% API
-export([
    start_link/0,
    initialize_writers/2,
    initialize_writers_local/3,
    write/2,
    write_local/3,
    metadata/1,
    metadata_local/1,
    initialize_readers/2,
    initialize_readers_local/2,
    read/3,
    read_local/2,
    delete/2,
    delete_local/2,
    remove_handler/3
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
    chunks_counters = #{},
    chunks_readers = #{},
    metadata = #{}
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

initialize_writers(FileName, Length) ->
    gen_server:call(?SERVER, {initialize_writers, FileName, Length}, infinity).

initialize_writers_local(FileName, I, Type) ->
    gen_server:call(?SERVER, {initialize_writers_local, FileName, I, Type}, infinity).

write(FileName, Data) ->

    io:format("---WRITE 1---~n"),

    gen_server:call(?SERVER, {write, FileName, Data}, infinity).

write_local(FileName, Data, CurrentChunksCounter) ->

    io:format("---WRITE 2---~n"),

    gen_server:call(?SERVER, {write_local, FileName, Data, CurrentChunksCounter}, infinity).

metadata(FileName) ->
    gen_server:call(?SERVER, {metadata, FileName}, infinity).

metadata_local(FileName) ->
    gen_server:call(?SERVER, {metadata_local, FileName}, infinity).

initialize_readers(FileName, MetaData) ->
    gen_server:call(?SERVER, {initialize_readers, FileName, MetaData}, infinity).

initialize_readers_local(FileName, I) ->
    gen_server:call(?SERVER, {initialize_readers_local, FileName, I}, infinity).

read(FileName, I, Node) ->
    gen_server:call(?SERVER, {read, FileName, I, Node}, infinity).

read_local(FileName, I) ->
    gen_server:call(?SERVER, {read_local, FileName, I}, infinity).

delete(FileName, MetaData) ->
    gen_server:call(?SERVER, {delete, FileName, MetaData}, infinity).

delete_local(FileName, I) ->
    gen_server:call(?SERVER, {delete_local, FileName, I}, infinity).

remove_handler(Type, FileName, Pid) ->
    gen_server:cast(?SERVER, {Type, FileName, Pid}).

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
handle_call({initialize_writers, FileName, Length}, _From, State) ->
    {ok, ChunkSize} = application:get_env(es3, chunk_size),
    ChunksCount = ceil(Length/list_to_integer(ChunkSize)),

    State1 = prepare(FileName, ChunksCount, State),

    {reply, initialized, State1};
handle_call({initialize_writers_local, FileName, I, Type}, _From, #state{chunks_handlers = CH} = State) ->
    CurrentChunksHandlers = maps:get(FileName, CH, []),
    {ok, Pid} = chunk_handler:start_link(FileName, I, Type),
    {reply, initialized, State#state{chunks_handlers = maps:put(FileName, [{I, Pid, passive}|CurrentChunksHandlers], CH)}};
handle_call({write, FileName, Data}, _From, #state{chunks_handlers = CH, chunks_counters = CC} = State) ->

    io:format("---WRITE 3---~n"),

    CurrentChunksHandlers = maps:get(FileName, CH, []),
    CurrentChunksCounter = maps:get(FileName, CC, 0),
    Nodes = nodes(),
    N = length(Nodes) + 1,

    io:format("---------------------------HANDLE CALL WRITE----- ~p~n", [{CurrentChunksCounter, N, (CurrentChunksCounter rem N)}]),

    CH1 = case (CurrentChunksCounter rem N) of
        0 ->

            io:format("---WRITE 3.1---~n"),

            CurrentChunksHandlers1 = do_write(CurrentChunksHandlers, Data, CurrentChunksCounter),
            maps:put(FileName, CurrentChunksHandlers1, CH);
        Rem ->

            io:format("---WRITE 3.2---~n"),

            Node = lists:nth(Rem, Nodes),

            io:format("---WRITE NODE---~p~n", [Node]),

            case rpc:call(Node, chunk_controller, write_local, [FileName, Data, CurrentChunksCounter]) of
                {badrpc, Reason} ->

                    io:format("---WRITE 3.2.1---~n"),

                    error(Reason);
                saved -> %% saved

                    io:format("---WRITE 3.2.2---~n"),

                    ok
            end,
            CH
    end,
    State1 = State#state{chunks_handlers = CH1, chunks_counters = maps:put(FileName, CurrentChunksCounter + 1, CC)},

   io:format("---WRITE MAIN--- ~p~n", [State1]),

    {reply, saved, State1};
handle_call({write_local, FileName, Data, CC}, _From, #state{chunks_handlers = CH} = State) ->

    io:format("---WRITE LOCAL---~n"),

    CurrentChunksHandlers = maps:get(FileName, CH, []),
    CurrentChunksHandlers1 = do_write(CurrentChunksHandlers, Data, CC),
    {reply, saved, State#state{chunks_handlers = maps:put(FileName, CurrentChunksHandlers1, CH)}};
handle_call({metadata, FileName}, _From, #state{metadata = MD} = State) ->
    Data = case maps:get(FileName, MD, []) of
        [] ->
            find_metadata(FileName);
        List ->
            [{node(), List}|find_metadata(FileName)]
    end,
    {reply, organize(Data), State};
handle_call({metadata_local, FileName}, _From, #state{metadata = MD} = State) ->
    Data = maps:get(FileName, MD, []),
    {reply, Data, State};
handle_call({initialize_readers, FileName, MetaData}, _From, #state{chunks_readers = CR} = State) ->
    CurrentChunksReaders = maps:get(FileName, CR, []),
    CurrentChunksReaders1 = lists:foldl(fun({I, Node}, Acc) ->
        case Node == node() of
            true ->
                {ok, Pid} = chunk_handler:start_link(FileName, I, reader),
                [{I, Pid}|Acc];
            false ->
                case rpc:call(Node, chunk_controller, initialize_readers_local, [FileName, I]) of
                   {badrpc, Reason} ->
                       error(Reason);
                   initialized ->
                       ok
                end,
                Acc
        end
    end, CurrentChunksReaders, MetaData),
    {reply, initialized, State#state{chunks_readers = maps:put(FileName, CurrentChunksReaders1, CR)}};
handle_call({initialize_readers_local, FileName, I}, _From, #state{chunks_readers = CR} = State) ->
    CurrentChunksReaders = maps:get(FileName, CR, []),
    {ok, Pid} = chunk_handler:start_link(FileName, I, reader),
    {reply, initialized, State#state{chunks_readers = maps:put(FileName, [{I, Pid}|CurrentChunksReaders], CR)}};
handle_call({read, FileName, I, Node}, _From, #state{chunks_readers = CR} = State) when Node == node() ->
    CurrentChunksReaders = maps:get(FileName, CR),
    {I, Pid} = lists:keyfind(I, 1, CurrentChunksReaders),
    Data = chunk_handler:read(Pid),
    ok = chunk_handler:stop(Pid, normal),
    {reply, Data, State};
handle_call({read, FileName, I, Node}, _From, State) ->
    Data = case rpc:call(Node, chunk_controller, read_local, [FileName, I]) of
        {badrpc, Reason} ->
            error(Reason);
        Bin ->
            Bin
    end,
    {reply, Data, State};
handle_call({read_local, FileName, I}, _From, #state{chunks_readers = CR} = State) ->
    CurrentChunksReaders = maps:get(FileName, CR),
    {I, Pid} = lists:keyfind(I, 1, CurrentChunksReaders),
    Data = chunk_handler:read(Pid),
    ok = chunk_handler:stop(Pid, normal),
    {reply, Data, State};
handle_call({delete, FileName, MetaData}, _From, #state{chunks_readers = CR, metadata = MD} = State) ->
    CurrentChunksReaders = maps:get(FileName, CR),
    deleted = do_delete(FileName, CurrentChunksReaders, MetaData),
    {reply, deleted, State#state{metadata = maps:remove(FileName, MD)}};
handle_call({delete_local, FileName, I}, _From, #state{chunks_readers = CR, metadata = MD} = State) ->
    CurrentChunksReaders = maps:get(FileName, CR),
    {I, Pid} = lists:keyfind(I, 1, CurrentChunksReaders),
    ok = chunk_handler:delete(Pid),
    {reply, deleted, State#state{metadata = maps:remove(FileName, MD)}};
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
handle_cast({writer, FileName, Pid}, #state{chunks_handlers = CW, chunks_counters = CC, metadata = MD} = State) ->
    CurrentMD = maps:get(FileName, MD, []),
    State1 = case maps:get(FileName, CW, []) of
        [] ->
%%            State#state{chunks_handlers = maps:remove(FileName, CW), chunks_counters = maps:remove(FileName, CC)};
            State#state{chunks_handlers = maps:remove(FileName, CW)};
        Writers ->
            case lists:keytake(Pid, 2, Writers) of
                {value, {I, Pid, _Status}, Writers1} when Writers1 =/= [] ->
                    State#state{chunks_handlers = maps:put(FileName, Writers1, CW), metadata = maps:put(FileName, [I|CurrentMD], MD)};
                {value, {I, Pid, _Status}, Writers1} ->
%%                    State#state{chunks_handlers = maps:remove(FileName, CW), chunks_counters = maps:remove(FileName, CC), metadata = maps:put(FileName, [I|CurrentMD], MD)};
                    State#state{chunks_handlers = maps:remove(FileName, CW), metadata = maps:put(FileName, [I|CurrentMD], MD)};
                false ->
                    State
            end
    end,

   io:format("---REMOVE WRITER--- ~p~n", [State1]),

    {noreply, State1};
handle_cast({reader, FileName, Pid}, #state{chunks_readers = CR} = State) ->
    State1 = case maps:get(FileName, CR, []) of
                 [] ->
                     State#state{chunks_readers = maps:remove(FileName, CR)};
                 Readers ->
                     case lists:keytake(Pid, 2, Readers) of
                         {value, {_I, Pid}, Readers1} when Readers1 =/= [] ->
                             State#state{chunks_readers = maps:put(FileName, Readers1, CR)};
                         {value, {_I, Pid}, Readers1} ->
                             State#state{chunks_readers = maps:remove(FileName, CR)};
                         false ->
                             State
                     end
             end,

   io:format("---REMOVE READER--- ~p~n", [State1]),

    {noreply, State1};
handle_cast({eraser, FileName, Pid}, #state{chunks_readers = CR, metadata = MD} = State) ->
    State1 = case maps:get(FileName, CR, []) of
                 [] ->
                     State#state{chunks_readers = maps:remove(FileName, CR), metadata = maps:remove(FileName, MD)};
                 Readers ->
                     case lists:keytake(Pid, 2, Readers) of
                         {value, {_I, Pid}, Readers1} when Readers1 =/= [] ->
                             State#state{chunks_readers = maps:put(FileName, Readers1, CR)};
                         {value, {_I, Pid}, Readers1} ->
                             State#state{chunks_readers = maps:remove(FileName, CR), metadata = maps:remove(FileName, MD)};
                         false ->
                             State
                     end
             end,

   io:format("---REMOVE READER--- ~p~n", [State1]),

    {noreply, State1};
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

               io:format("---PREPARE LOCAL--- ~p~n", [I]),

                CurrentChunkHandlers = maps:get(FileName, CH, []),
                {ok, Pid} = chunk_handler:start_link(FileName, I, writer),
                S1 = S#state{chunks_handlers = maps:put(FileName, [{I, Pid, passive}|CurrentChunkHandlers], CH), chunks_counters = maps:put(FileName, 1, CC)},
                S1;
            Rem ->
                Node = lists:nth(Rem, Nodes),

                io:format("---PREPARE REMOTE--- ~p~n", [{I, Node}]),

                case rpc:call(Node, chunk_controller, initialize_writers_local, [FileName, I, writer]) of
                    {badrpc, Reason} ->
                        error(Reason);
                    initialized -> %% initialized
                        ok
                end,
                S
        end
    end, State, lists:seq(1, ChunksCount)),

   io:format("---PREPARE ALL DONE--- ~p~n", [State1]),

    State1.

do_write([], Data, ChunksCounter) ->

    io:format("--------------------ERROR-------------------- ~p~n", [{node(), ChunksCounter}]),

    [];
do_write(ChunksHandlers, Data, ChunksCounter) ->
    do_write(ChunksHandlers, Data, ChunksCounter, []).

do_write([{I, Pid, passive}|T], Data, ChunksCounter, ActiveCH) when I =:= ChunksCounter ->
    ok = chunk_handler:write(Pid, Data, ChunksCounter),
    [{I, Pid, active}|ActiveCH] ++ T;
do_write([H|T], Data, ChunksCounter, ActiveCH) ->
    do_write(T, Data, ChunksCounter, [H|ActiveCH]).

find_metadata(FileName) ->
    Nodes = nodes(),
    lists:foldl(fun(N, Acc) ->
        case rpc:call(N, chunk_controller, metadata_local, [FileName]) of
            {badrpc, Reason} ->
                error(Reason);
            List ->
                [{N, List}|Acc]
        end
    end, [], Nodes).

organize(List) ->
    organize(List, []).

organize([], Acc) ->
    lists:keysort(1, Acc);
organize([{Node, Chunks}|T], Acc) ->
    Chunks1 = lists:foldl(fun(I, Acc) ->
        [{I, Node}|Acc]
    end, [], Chunks),
    organize(T, Acc ++ Chunks1).

do_delete(_FileName, _CurrentChunksReaders, []) ->
    deleted;
do_delete(FileName, CurrentChunksReaders, [{I, Node}|T]) when Node == node() ->
    {I, Pid} = lists:keyfind(I, 1, CurrentChunksReaders),
    ok = chunk_handler:delete(Pid),
    do_delete(FileName, CurrentChunksReaders, T);
do_delete(FileName, CurrentChunksReaders, [{I, Node}|T]) ->
    case rpc:call(Node, chunk_controller, delete_local, [FileName, I]) of
        {badrpc, Reason} ->
            error(Reason);
        deleted ->
            do_delete(FileName, CurrentChunksReaders, T)
    end.

