%%%-------------------------------------------------------------------
%%% @author d.pravosudov
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Апр. 2019 13:26
%%%-------------------------------------------------------------------
-module(es3_api_handler).
-author("d.pravosudov").

%% API
-export([
    init/2,
    allowed_methods/2,
    handle_post/1,
    handle_get/2
]).

-record(reply, {
    code,
    headers,
    body,
    req
}).

init(Req, State) ->
%%    handle(Req, State).

    lager:debug("----INIT ~p", [?MODULE]),

    Reply =  case cowboy_req:method(Req) of
        <<"POST">> ->
            handle_post(Req);
        _ ->
            handle_get(Req, State)
    end,
    Req1 = cowboy_req:reply(Reply#reply.code, Reply#reply.headers, Reply#reply.body, Reply#reply.req),
    {ok, Req1, State}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"POST">>], Req, State}.

%%handle(Req, State) ->
%%
%%    lager:debug("----HANDLE ~p", [?MODULE]),
%%
%%    case cowboy_req:method(Req) of
%%        <<"POST">> ->
%%
%%            lager:debug("----POST"),
%%
%%            Req1 = multipart(Req),
%%            Req2 = cowboy_req:reply(200, #{}, <<"ok">>, Req1),
%%            {ok, Req2, State};
%%        _ ->
%%            Req1 = cowboy_req:reply(200, #{}, <<"error">>, Req),
%%            {ok, Req1, State}
%%    end.

handle_post(Req) ->

    lager:debug("----POST REQ ~p", [Req]),

    case cowboy_req:parse_header(<<"content-type">>, Req) of
        {<<"multipart">>, _, _} ->
            Length = cowboy_req:parse_header(<<"content-length">>, Req),
            #reply{code = 200, headers = #{"content-type" => "application/json"}, body = response(ok), req = handle_file(Req, Length)};
        _ ->
            #reply{code = 200, headers = #{"content-type" => "application/json"}, body = response({error, "wrong data"}), req = Req}
    end.

handle_get(Req, State) ->

    lager:debug("----GET REQ ~p", [Req]),

    {ok, Req, State}.

handle_file(Req, Length) ->
    case cowboy_req:read_part(Req) of
        {ok, Headers, Req1} ->

            lager:debug("------HEADERS ~p", [Headers]),

            ReqFin = case cow_multipart:form_data(Headers) of
                {data, Field} ->
                    {ok, Body, Req2} = cowboy_req:read_part_body(Req1),
                    Req2;
                {file, Field, FileName, _} ->
%%                    {ok, File} = file:open(FileName, [write]),
%%                    stream_file(Req1, File)
                    chunk_controller:initialize(FileName, Length),
                    stream_file(FileName, Req1)
            end,
            handle_file(ReqFin, Length);
        {done, Req1} ->
            Req1
    end.

%%multipart(Req0) ->
%%    case cowboy_req:read_part(Req0) of
%%        {ok, Headers, Req1} ->
%%            Req = case cow_multipart:form_data(Headers) of
%%                      {data, FieldName} ->
%%
%%                          lager:debug("----DATA ~p", [FieldName]),
%%
%%                          {ok, Body, Req2} = cowboy_req:read_part_body(Req1),
%%
%%                          lager:debug("----DATA ~p", [Body]),
%%
%%                          Req2;
%%                      {file, FieldName, Filename, _CType} ->
%%
%%                          lager:debug("----FILE ~p", [{FieldName, Filename}]),
%%
%%                          {ok, File} = file:open(Filename,[write]),
%%                          stream_file(Req1, File)
%%                  end,
%%            multipart(Req);
%%        {done, Req} ->
%%            Req
%%    end.

%%stream_file(Req, File) ->
%%    {ok, ChunkSize} = application:get_env(es3, chunk_size),
%%    case cowboy_req:read_part_body(Req, #{length => ChunkSize}) of
%%        {ok, LastBodyChunk, Req1} ->
%%
%%            lager:debug("----STREAM FILE ~p", [File]),
%%
%%            file:write(File, LastBodyChunk),
%%            Req1;
%%        {more, BodyChunk, Req1} ->
%%
%%            lager:debug("----MORE STREAM FILE ~p", [File]),
%%
%%            file:write(File, BodyChunk),
%%            stream_file(Req1, File)
%%    end.
stream_file(FileName, Req) ->
    {ok, ChunkSize} = application:get_env(es3, chunk_size),
    case cowboy_req:read_part_body(Req, #{length => ChunkSize}) of
        {ok, LastBodyChunk, Req1} ->

            lager:debug("----STREAM FILE"),

            chunk_controller:write(FileName, LastBodyChunk),
            Req1;
        {more, BodyChunk, Req1} ->

            lager:debug("----MORE STREAM FILE"),

            chunk_controller:write(FileName, BodyChunk),
            stream_file(FileName, Req1)
    end.

response(ok) ->
    jsx:encode(ok);
response(Data) when is_tuple(Data) ->
    case element(1, Data) of
        error ->

            lager:debug("----ERROR ~p", [Data]),

            jsx:encode([{<<"error">>, types_helper:val_to_jsx_compatible(element(2, Data))}]);
        Result ->

            lager:debug("----ANY ~p", [Data]),

            jsx:encode([{types_helper:val_to_jsx_compatible(Result), types_helper:val_to_jsx_compatible(element(2, Data))}])
    end.