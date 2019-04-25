-module(es3_SUITE).
-author("d.pravosudov").

-include_lib("common_test/include/ct.hrl").

-define(FILENAME, "test.md").

%% API
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1
]).

-export([
    write_test/1,
    read_test/1,
    delete_test/1,
    read_failed_test/1,
    delete_failed_test/1
]).

all() ->
    [
        write_test,
        read_test,
        delete_test,
        read_failed_test,
        delete_failed_test
    ].

init_per_suite(Config) ->
    application:start(inets),
    {ok, _Pid} = inets:start(httpc, [{profile, none}]),
    Config.

end_per_suite(_Config) ->
    ok.

write_test(_Config) ->
    Port = ct:get_config(master_api_port),
    FileName = ?FILENAME,
    FilePath = "../../../../test/" ++ FileName,
    Boundary = "------WebKitFormBoundary1234567890123456",

    {ok, Bin} = file:read_file(FilePath),
    ReqBody = multipart(Boundary, "file", FileName, binary_to_list(Bin)),
    ContentType = lists:concat(["multipart/form-data; boundary=", Boundary]),
    ReqHeader = [{"Content-Length", integer_to_list(length(ReqBody))}],

    ct:sleep(1000),

    {ok, {{_ ,200 , _}, _, "\"ok\""}} = httpc:request(post,{"http://localhost:" ++ integer_to_list(Port), ReqHeader, ContentType, ReqBody},[],[]),

    {ReqBody, ReqHeader, ContentType}.

read_test(_Config) ->
    Port = ct:get_config(master_api_port),
    FileName = ?FILENAME,

    ct:sleep(1000),

    {ok, {{_ ,200 , _}, _, Bin}} = httpc:request(get,{"http://localhost:" ++ integer_to_list(Port) ++ "/?action=read&name=" ++ FileName, []},[],[]),

    2448 = length(Bin).

delete_test(_Config) ->
    Port = ct:get_config(master_api_port),
    FileName = ?FILENAME,

    ct:sleep(1000),

    {ok, {{_ ,200 , _}, _, "\"ok\""}} = httpc:request(get,{"http://localhost:" ++ integer_to_list(Port) ++ "/?action=delete&name=" ++ FileName, []},[],[]).

read_failed_test(_Config) ->
    Port = ct:get_config(master_api_port),
    FileName = ?FILENAME,

    ct:sleep(1000),

    {ok, {{_ ,200 , _}, _, "{\"error\":\"file not found\"}"}} = httpc:request(get,{"http://localhost:" ++ integer_to_list(Port) ++ "/?action=read&name=" ++ FileName, []},[],[]).

delete_failed_test(_Config) ->
    Port = ct:get_config(master_api_port),
    FileName = ?FILENAME,

    ct:sleep(1000),

    {ok, {{_ ,200 , _}, _, "{\"error\":\"file not found\"}"}} = httpc:request(get,{"http://localhost:" ++ integer_to_list(Port) ++ "/?action=delete&name=" ++ FileName, []},[],[]).

multipart(Boundary, FieldName, FileName, FileContent) ->
    Parts = [
        lists:concat(["--", Boundary]),
        lists:concat(["Content-Disposition: form-data; name=\"", FieldName,"\"; filename=\"",FileName,"\""]),
        lists:concat(["Content-Type: ", "application/octet-stream"]), 
        "", 
        FileContent
    ],
    Ending = [lists:concat(["--", Boundary, "--"]), ""],
    All = lists:append([Parts, Ending]),
    string:join(All, "\r\n").