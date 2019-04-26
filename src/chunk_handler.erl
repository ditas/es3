-module(chunk_handler).
-author("d.pravosudov").

-behaviour(gen_server).

-include_lib("kernel/include/file.hrl").

%% API
-export([
    start_link/3,
    write/3,
    read/1,
    delete/1,
    stop/2
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
    filename,
    chunk_number,
    chunkfilename,
    file,
    type
}).

%%%===================================================================
%%% API
%%%===================================================================
write(Pid, Data, N) ->

    io:format("--------WRITE ~p~n", [{node(), ?MODULE, N}]),

    gen_server:cast(Pid, {write, Data, N}).

read(Pid) ->
    gen_server:call(Pid, read).

delete(Pid) ->
    gen_server:cast(Pid, delete).

stop(Pid, Reason) ->
    gen_server:stop(Pid, Reason, 1000).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
start_link(FileName, I, Type) ->
    gen_server:start_link(?MODULE, [FileName, I, Type], []).

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
init([BinFileName, I, Type]) ->

    io:format("--------INIT ~p~n", [{node(), ?MODULE, BinFileName, Type, I}]),

    FileName = binary_to_list(BinFileName),
    ChunkFileName = FileName ++ "_" ++ integer_to_list(I),
    {ok, File} = file:open(ChunkFileName, [binary, read, write]),
    {ok, #state{filename = FileName, chunk_number = I, chunkfilename = ChunkFileName, file = File, type = Type}}.

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
handle_call(read, _From, #state{file = File, chunkfilename = ChunkFileName} = State) ->
    {ok, FileInfo} = file:read_file_info(ChunkFileName),
    {ok, Data} = file:read(File, FileInfo#file_info.size),
    {reply, Data, State};
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
handle_cast({write, Data, N}, #state{file = File, chunk_number = I, chunkfilename = ChunkFileName} = State) ->

    io:format("--------WRITE ~p~n", [{node(), ?MODULE, ChunkFileName, N}]),

    ok = file:write(File, Data),
    {stop, normal, State};
handle_cast(delete, #state{chunkfilename = ChunkFileName} = State) ->
    ok = file:delete(ChunkFileName),
    {stop, normal, State#state{type = eraser}};
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
terminate(_Reason, #state{type = Type, filename = FileName}) ->
    chunk_controller:remove_handler(Type, list_to_binary(FileName), self()),
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
