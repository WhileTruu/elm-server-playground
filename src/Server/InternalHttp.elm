module Server.InternalHttp exposing
    ( Body(..)
    , Error(..)
    , Header(..)
    , Metadata
    , Method(..)
    , MimeType(..)
    , Request
    , Response(..)
    , TimeoutConfig(..)
    )

import Json.Decode


type alias Request =
    { method : Method
    , headers : List Header
    , url : String
    , body : Body
    , timeout : TimeoutConfig
    }


type Method
    = Options
    | Get
    | Post
    | Put
    | Delete
    | Head
    | Trace
    | Connect
    | Patch


type Header
    = Header String String


{-| Name is distinguished from the Timeout tag used in Response and Error
-}
type TimeoutConfig
    = TimeoutMilliseconds Int
    | NoTimeout


type Body
    = Body (MimeType String) Json.Decode.Value
    | EmptyBody


type MimeType a
    = MimeType a


type Response
    = NetworkError_
    | BadStatus_ Metadata Json.Decode.Value
    | GoodStatus_ Metadata Json.Decode.Value


type alias Metadata =
    { url : String
    , statusCode : Int
    , statusText : String
    , headers : List Header
    }


type Error
    = BadRequest String
    | Timeout
    | NetworkError
    | BadStatus Int
    | BadBody String
