-module(es3_api_handler).
-author("d.pravosudov").

-include_lib("kernel/include/file.hrl").

%% API
-export([
    init/2,
    allowed_methods/2,
    handle_post/1,
    handle_get/1
]).

-record(reply, {
    code,
    headers,
    body,
    req
}).

init(Req, State) ->
    Req1 = case cowboy_req:method(Req) of
        <<"POST">> ->
            Reply = handle_post(Req),
            cowboy_req:reply(Reply#reply.code, Reply#reply.headers, Reply#reply.body, Reply#reply.req);
        _ ->
            handle_get(Req)
    end,
    {ok, Req1, State}.

allowed_methods(Req, State) ->
    {[<<"GET">>, <<"POST">>], Req, State}.

handle_post(Req) ->
    case cowboy_req:parse_header(<<"content-type">>, Req) of
        {<<"multipart">>, _, _} ->
            Length = cowboy_req:parse_header(<<"content-length">>, Req),
            #reply{code = 200, headers = #{"content-type" => "application/json"}, body = response(ok), req = handle_file(Req, Length)};
        _ ->
            #reply{code = 200, headers = #{"content-type" => "application/json"}, body = response({error, "wrong data"}), req = Req}
    end.

handle_get(Req) ->
    QS = cowboy_req:parse_qs(Req),
    case lists:keyfind(<<"action">>, 1, QS) of
        {<<"action">>, Action} ->
            action(Action, lists:keyfind(<<"name">>, 1, QS), Req);
        Any ->
            Reply = #reply{code = 200, headers = #{"content-type" => "application/json"}, body = response({error, "wrong request"}), req = Req},
            cowboy_req:reply(Reply#reply.code, Reply#reply.headers, Reply#reply.body, Reply#reply.req)
    end.

action(Type, {_, FileName}, Req) ->
    case chunk_controller:metadata(FileName) of
        [] ->
            Reply = #reply{code = 200, headers = #{"content-type" => "application/json"}, body = response({error, "file not found"}), req = Req},
            cowboy_req:reply(Reply#reply.code, Reply#reply.headers, Reply#reply.body, Reply#reply.req);
        MetaData ->
            action(Type, FileName, MetaData, Req)
    end.

action(<<"read">>, FileName, MetaData, Req) ->
    initialized = chunk_controller:initialize_readers(FileName, MetaData),
    send_file(MetaData, FileName, Req);
action(<<"delete">>, FileName, MetaData, Req) ->
    initialized = chunk_controller:initialize_readers(FileName, MetaData),
    deleted = chunk_controller:delete(FileName, MetaData),
    Reply = #reply{code = 200, headers = #{"content-type" => "application/json"}, body = response(ok), req = Req},
    cowboy_req:reply(Reply#reply.code, Reply#reply.headers, Reply#reply.body, Reply#reply.req);
action(_, _, _, Req) ->
    Reply = #reply{code = 200, headers = #{"content-type" => "application/json"}, body = response({error, "wrong request"}), req = Req},
    cowboy_req:reply(Reply#reply.code, Reply#reply.headers, Reply#reply.body, Reply#reply.req).

send_file(MetaData, FileName, Req) ->
    Req1 = cowboy_req:stream_reply(200, #{"content-disposition" => "filename=" ++ binary_to_list(FileName)}, Req),
    send_chunks(MetaData, FileName, Req1),
    Req1.

send_chunks([{I, Node}], FileName, Req) ->
    ChunkData = chunk_controller:read(FileName, I, Node),
    cowboy_req:stream_body(ChunkData, fin, Req);
send_chunks([{I, Node}|T], FileName, Req) ->
    ChunkData = chunk_controller:read(FileName, I, Node),
    cowboy_req:stream_body(ChunkData, nofin, Req),
    send_chunks(T, FileName, Req).

handle_file(Req, Length) ->
    case cowboy_req:read_part(Req) of
        {ok, Headers, Req1} ->
            ReqFin = case cow_multipart:form_data(Headers) of
                {data, Field} ->
                    {ok, Body, Req2} = cowboy_req:read_part_body(Req1),
                    Req2;
                {file, Field, FileName, _} ->
                    chunk_controller:initialize_writers(FileName, Length),
                    stream_file(FileName, Req1)
            end,
            handle_file(ReqFin, Length);
        {done, Req1} ->
            Req1
    end.

stream_file(FileName, Req) ->
    {ok, ChunkSize} = application:get_env(es3, chunk_size),
    case cowboy_req:read_part_body(Req, #{length => list_to_integer(ChunkSize)}) of
        {ok, LastBodyChunk, Req1} ->
            chunk_controller:write(FileName, LastBodyChunk),
            Req1;
        {more, BodyChunk, Req1} ->
            chunk_controller:write(FileName, BodyChunk),
            stream_file(FileName, Req1)
    end.

response(ok) ->
    jsx:encode(ok);
response(Data) when is_tuple(Data) ->
    case element(1, Data) of
        error ->
            jsx:encode([{<<"error">>, types_helper:val_to_jsx_compatible(element(2, Data))}]);
        Result ->
            jsx:encode([{types_helper:val_to_jsx_compatible(Result), types_helper:val_to_jsx_compatible(element(2, Data))}])
    end.