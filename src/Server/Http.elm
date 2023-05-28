module Server.Http exposing
    ( Body
    , Error
    , Header
    , Metadata
    , Method
    , Request
    , Response
    , TimeoutConfig
    , defaultRequest
    , emptyBody
    , errorToString
    , get
    , header
    , send
    )

import Json.Decode
import Json.Encode
import Server.Effect as Effect
import Server.InternalHttp as InternalHttp
import Server.InternalTask as InternalTask
import Server.Task as Task exposing (Task)


type alias Request =
    InternalHttp.Request


type alias Method =
    InternalHttp.Method


type alias Header =
    InternalHttp.Header


type alias TimeoutConfig =
    InternalHttp.TimeoutConfig


type alias Body =
    InternalHttp.Body


type alias Response =
    InternalHttp.Response


type alias Metadata =
    InternalHttp.Metadata


type alias Error =
    InternalHttp.Error


defaultRequest : Request
defaultRequest =
    { method = InternalHttp.Get
    , headers = []
    , url = ""
    , body = emptyBody
    , timeout = InternalHttp.NoTimeout
    }


header : String -> String -> Header
header =
    InternalHttp.Header


emptyBody : Body
emptyBody =
    InternalHttp.EmptyBody


jsonBody : Json.Encode.Value -> Body
jsonBody value =
    InternalHttp.Body (InternalHttp.MimeType "application/json") value


handleJsonResponse : (Json.Decode.Value -> Result String a) -> Response -> Result Error a
handleJsonResponse fromValue response =
    case response of
        InternalHttp.BadRequest_ err ->
            Err (InternalHttp.BadRequest err)

        InternalHttp.Timeout_ ->
            Err InternalHttp.Timeout

        InternalHttp.NetworkError_ ->
            Err InternalHttp.NetworkError

        InternalHttp.BadStatus_ metadata _ ->
            Err (InternalHttp.BadStatus metadata.statusCode)

        InternalHttp.GoodStatus_ _ bodyJson ->
            fromValue bodyJson |> Result.mapError InternalHttp.BadBody


errorToString : Error -> String
errorToString err =
    case err of
        InternalHttp.BadRequest e ->
            "Invalid Request: " ++ e

        InternalHttp.Timeout ->
            "Request timed out"

        InternalHttp.NetworkError ->
            "Network error"

        InternalHttp.BadStatus code ->
            "Request failed with status " ++ String.fromInt code

        InternalHttp.BadBody details ->
            "Request failed. Invalid body. " ++ details


send : Json.Decode.Decoder a -> Request -> Task Error a
send decoder req =
    Effect.sendRequest req
        |> Effect.map
            (handleJsonResponse
                (Json.Decode.decodeValue decoder
                    >> Result.mapError Json.Decode.errorToString
                )
            )
        |> InternalTask.fromEffect


get :
    { url : String
    , decoder : Json.Decode.Decoder a
    }
    -> Task Error a
get { url, decoder } =
    send decoder
        { method = InternalHttp.Get
        , headers = []
        , url = url
        , body = emptyBody
        , timeout = InternalHttp.NoTimeout
        }
