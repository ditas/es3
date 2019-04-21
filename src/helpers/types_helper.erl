-module(types_helper).
-author("dmitryditas").

%% API
-export([
    val_to_list/1,
    val_to_float/1,
    val_to_integer/1,
    val_to_jsx_compatible/1,
    list_to_date/1,
    list_to_datetime/1,
    list_to_seconds/1,
    bin_to_datetime/1
]).

val_to_list(Val) when is_float(Val) ->
    float_to_list(Val);
val_to_list(Val) when is_integer(Val) ->
    integer_to_list(Val);
val_to_list(Val) when is_binary(Val) ->
    binary_to_list(Val);
val_to_list(Val) ->
    Val.

val_to_float(Val) when is_float(Val) ->
    Val;
val_to_float(Val) when is_integer(Val) ->
    float(Val);
val_to_float(Val) when is_binary(Val) ->
    case (catch binary_to_float(Val)) of
        {'EXIT', _Reason} ->
            case is_numeric(Val) of
                true ->
                    float(binary_to_integer(Val));
                false ->
                    0.0
            end;
        Float ->
            Float
    end;
val_to_float(Val) when is_list(Val) ->
    val_to_float(list_to_binary(Val)).

val_to_integer(Val) when is_integer(Val) ->
    Val;
val_to_integer(Val) when is_float(Val) ->
    round(Val);
val_to_integer(Val) when is_binary(Val) ->
    case (catch binary_to_integer(Val)) of
        {'EXIT', _Reason} ->
            case is_numeric(Val) of
                true ->
                    round(binary_to_float(Val));
                false ->
                    0
            end;
        Int ->
            Int
    end;
val_to_integer(Val) when is_list(Val) ->
    val_to_integer(list_to_binary(Val)).

val_to_jsx_compatible(Val) when is_integer(Val) ->
    Val;
val_to_jsx_compatible(Val) when is_float(Val) ->
    Val;
val_to_jsx_compatible(Val) when is_list(Val) ->
    case catch list_to_binary(Val) of
        {'EXIT', _Reason} -> Val;
        List -> List
    end;
val_to_jsx_compatible(Val) when is_binary(Val) ->
    Val;
val_to_jsx_compatible(Val) when is_tuple(Val) ->
    tuple_to_list_recur(Val);
val_to_jsx_compatible(Val) when is_atom(Val) ->
    Val.

tuple_to_list_recur(Val) when is_tuple(Val) ->
    List = tuple_to_list(Val),
    lists:foldl(fun(L, Acc) ->
        case is_tuple(L) of
            true ->
                L1 = tuple_to_list_recur(L),
                Acc ++ [L1];
            false ->
                Acc ++ [val_to_jsx_compatible(L)]
        end
                end, [], List).

is_numeric(Val) ->
    Float = (catch binary_to_float(Val)),
    Int = (catch binary_to_integer(Val)),
    is_number(Float) orelse is_number(Int).

list_to_date(List) ->
    Bin = list_to_binary(List),
    [Y, M, D] = binary:split(Bin, <<"-">>, [global]),
    {binary_to_integer(Y), binary_to_integer(M), binary_to_integer(D)}.

list_to_datetime(List) ->
    Bin = list_to_binary(List),
    [BinDate, BinTime] = binary:split(Bin, <<" ">>, [global]),
    [Y, M, D] = binary:split(BinDate, <<"-">>, [global]),
    [H, Min, S] = binary:split(BinTime, <<":">>, [global]),
    {{binary_to_integer(Y), binary_to_integer(M), binary_to_integer(D)}, {binary_to_integer(H), binary_to_integer(Min), binary_to_integer(S)}}.

list_to_seconds(List) ->
    Bin = list_to_binary(List),
    [BinH, BinM, BinS] = binary:split(Bin, <<":">>, [global]),
    H = binary_to_integer(BinH),
    M = binary_to_integer(BinM),
    S = binary_to_integer(BinS),
    H*3600 + M*60 + S.

bin_to_datetime(Bin) ->
    [BinDate, BinTime] = binary:split(Bin, <<" ">>, [global]),
    [Y, M, D] = binary:split(BinDate, <<"-">>, [global]),
    [H, Min, S] = binary:split(BinTime, <<":">>, [global]),
    {{binary_to_integer(Y), binary_to_integer(M), binary_to_integer(D)}, {binary_to_integer(H), binary_to_integer(Min), binary_to_integer(S)}}.