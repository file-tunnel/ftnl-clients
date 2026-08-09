-module(ftnl_client).

-export([new/1, new/2, request/4, health/1]).

-type client() :: #{base_url := string(), token := undefined | string()}.
-export_type([client/0]).

-spec new(string()) -> client().
new(BaseUrl) -> new(BaseUrl, undefined).

-spec new(string(), undefined | string()) -> client().
new(BaseUrl, Token) -> #{base_url => string:trim(BaseUrl, trailing, "/"), token => Token}.

-spec health(client()) -> term().
health(Client) -> request(Client, get, "/health", undefined).

-spec request(client(), atom(), string(), undefined | iodata()) -> term().
request(Client, Method, Path, Body) ->
    ok = ensure_started(inets),
    ok = ensure_started(ssl),
    BaseUrl = maps:get(base_url, Client),
    Token = maps:get(token, Client),
    Headers0 = [{"accept", "application/json"}],
    Headers = case Token of
        undefined -> Headers0;
        _ -> [{"authorization", "Bearer " ++ Token} | Headers0]
    end,
    Url = BaseUrl ++ "/" ++ string:trim(Path, leading, "/"),
    HttpRequest = case Body of
        undefined -> {Url, Headers};
        _ -> {Url, [{"content-type", "application/json"} | Headers], "application/json", Body}
    end,
    httpc:request(Method, HttpRequest, [{timeout, 30000}], [{body_format, binary}]).

ensure_started(Application) ->
    case application:ensure_all_started(Application) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok;
        {error, Reason} -> erlang:error({application_start_failed, Application, Reason})
    end.
