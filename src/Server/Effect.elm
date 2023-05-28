module Server.Effect exposing
    ( Effect
    , always
    , andThen
    , encodeStep
    , map
    , map2
    , posixTime
    , randomInt32
    , sendRequest
    , stepFromEffect
    , toDecoder
    )

import FNV1a
import Json.Decode as JD
import Json.Encode as JE
import Server.InternalHttp as InternalHttp



-- if requests are needed, hashing needs to be introduced instead of labels,
-- since multiple requests can be made to the same endpoint with different payloads


type Effect a
    = EffectInProgress (List EffectKind) (JD.Value -> Effect a)
    | EffectSuccess a


type EffectKind
    = EffectKindHttp InternalHttp.Request
    | EffectKindRandomInt32
    | EffectKindPosixTime


hashEffectKind : EffectKind -> String
hashEffectKind effectKind =
    JE.object (effectKindEncode effectKind)
        |> JE.encode 0
        |> FNV1a.hash
        |> String.fromInt


effectKindEncode : EffectKind -> List ( String, JD.Value )
effectKindEncode effectKind =
    case effectKind of
        EffectKindHttp request ->
            [ ( "effectKind", JE.string "Http" )
            , ( "payload"
              , JE.object
                    [ ( "method"
                      , JE.string <|
                            case request.method of
                                InternalHttp.Options ->
                                    "Options"

                                InternalHttp.Get ->
                                    "Get"

                                InternalHttp.Post ->
                                    "Post"

                                InternalHttp.Put ->
                                    "Put"

                                InternalHttp.Delete ->
                                    "Delete"

                                InternalHttp.Head ->
                                    "Head"

                                InternalHttp.Trace ->
                                    "Trace"

                                InternalHttp.Connect ->
                                    "Connect"

                                InternalHttp.Patch ->
                                    "Patch"
                      )
                    , ( "headers"
                      , JE.list
                            (\(InternalHttp.Header key value) ->
                                JE.object
                                    [ ( "key", JE.string key )
                                    , ( "value", JE.string value )
                                    ]
                            )
                            request.headers
                      )
                    , ( "url", JE.string request.url )
                    , ( "body"
                      , case request.body of
                            InternalHttp.Body _ body ->
                                body

                            InternalHttp.EmptyBody ->
                                JE.null
                      )
                    ]
              )
            ]

        EffectKindRandomInt32 ->
            [ ( "effectKind", JE.string "RandomInt32" ) ]

        EffectKindPosixTime ->
            [ ( "effectKind", JE.string "PosixTime" ) ]


always : a -> Effect a
always value =
    EffectSuccess value


map : (a -> b) -> Effect a -> Effect b
map transform resolver =
    case resolver of
        EffectInProgress labels lookup ->
            EffectInProgress labels (\value -> map transform (lookup value))

        EffectSuccess a ->
            EffectSuccess (transform a)


{-| andThen needs super special handling server side
-}
andThen : (a -> Effect b) -> Effect a -> Effect b
andThen transform effect =
    case effect of
        EffectInProgress labels lookup ->
            EffectInProgress labels (\value -> andThen transform (lookup value))

        EffectSuccess a ->
            transform a


map2 : (a -> b -> c) -> Effect a -> Effect b -> Effect c
map2 transform effectA effectB =
    case ( effectA, effectB ) of
        ( EffectInProgress labelsA lookupA, EffectInProgress labelsB lookupB ) ->
            EffectInProgress (labelsA ++ labelsB) <|
                \value ->
                    map2 transform (lookupA value) (lookupB value)

        ( EffectSuccess a, EffectInProgress labelsB lookupB ) ->
            map (transform a) (EffectInProgress labelsB lookupB)

        ( EffectInProgress labelsA lookupA, EffectSuccess b ) ->
            map (\a -> transform a b) (EffectInProgress labelsA lookupA)

        ( EffectSuccess a, EffectSuccess b ) ->
            EffectSuccess (transform a b)


andMap : Effect a -> Effect (a -> b) -> Effect b
andMap =
    map2 (|>)


posixTime : Effect Int
posixTime =
    EffectInProgress [ EffectKindPosixTime ]
        (\value ->
            JD.decodeValue
                (JD.field (hashEffectKind EffectKindPosixTime) JD.int)
                value
                -- FIXME handle error, or not somehow?
                |> Result.withDefault -420
                |> EffectSuccess
        )


randomInt32 : Effect Int
randomInt32 =
    EffectInProgress [ EffectKindRandomInt32 ]
        (\value ->
            JD.decodeValue
                (JD.field (hashEffectKind EffectKindRandomInt32) JD.int)
                value
                -- FIXME handle error, or not somehow?
                |> Result.withDefault -420
                |> EffectSuccess
        )


toDecoder : Effect a -> JD.Decoder a
toDecoder effect =
    case effect of
        EffectInProgress _ lookup ->
            JD.value |> JD.andThen (toDecoder << lookup)

        EffectSuccess a ->
            JD.succeed a


type Step state a
    = Loop state
    | Done a


stepFromEffect : Effect a -> JD.Value -> Step (List EffectKind) ()
stepFromEffect effect value =
    case effect of
        EffectInProgress labels lookup ->
            JD.decodeValue (JD.keyValuePairs JD.value) value
                |> Result.map
                    (\resolvedPairs ->
                        let
                            areAllLabelsInResolvedPairs =
                                List.all
                                    (\label ->
                                        List.any (Tuple.first >> (==) (hashEffectKind label))
                                            resolvedPairs
                                    )
                                    labels
                        in
                        if areAllLabelsInResolvedPairs then
                            stepFromEffect (lookup value) value

                        else
                            Loop labels
                    )
                |> Result.withDefault (Loop labels)

        EffectSuccess _ ->
            Done ()


encodeStep : Step (List EffectKind) () -> JD.Value
encodeStep result =
    case result of
        Loop batch ->
            JE.object
                [ ( "variant", JE.string "Loop" )
                , ( "batch"
                  , batch
                        |> JE.list
                            (\a ->
                                JE.object
                                    (( "hash", JE.string (hashEffectKind a) )
                                        :: effectKindEncode a
                                    )
                            )
                  )
                ]

        Done _ ->
            JE.object
                [ ( "variant", JE.string "Done" )
                ]


sendRequest : InternalHttp.Request -> Effect InternalHttp.Response
sendRequest req =
    EffectInProgress [ EffectKindHttp req ]
        (\value ->
            JD.decodeValue
                (JD.field (hashEffectKind (EffectKindHttp req))
                    (JD.map2 InternalHttp.GoodStatus_
                        (JD.field "metadata" metadataDecoder)
                        (JD.field "value" JD.value)
                    )
                )
                value
                |> Ok
                |> Result.withDefault
                    (JD.decodeValue (JD.field "metadata" metadataDecoder) value
                        |> Result.map (\a -> InternalHttp.BadStatus_ a value)
                    )
                |> Result.withDefault InternalHttp.NetworkError_
                |> EffectSuccess
        )


metadataDecoder : JD.Decoder InternalHttp.Metadata
metadataDecoder =
    JD.map4 InternalHttp.Metadata
        (JD.field "url" JD.string)
        (JD.field "statusCode" JD.int)
        (JD.field "statusText" JD.string)
        (JD.field "headers"
            (JD.keyValuePairs JD.string
                |> JD.map (List.map (\( k, v ) -> InternalHttp.Header k v))
            )
        )
