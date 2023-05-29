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


type Effect a
    = EffectInProgress (List EffectKind) (JD.Value -> Effect a)
    | EffectSuccess a
    | EffectPlatformFailure String


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

        EffectPlatformFailure err ->
            EffectPlatformFailure err


andThen : (a -> Effect b) -> Effect a -> Effect b
andThen transform effect =
    case effect of
        EffectInProgress labels lookup ->
            EffectInProgress labels (\value -> andThen transform (lookup value))

        EffectSuccess a ->
            transform a

        EffectPlatformFailure err ->
            EffectPlatformFailure err


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

        ( EffectPlatformFailure errA, EffectPlatformFailure errB ) ->
            EffectPlatformFailure (errA ++ " " ++ errB)

        ( EffectPlatformFailure err, _ ) ->
            EffectPlatformFailure err

        ( _, EffectPlatformFailure err ) ->
            EffectPlatformFailure err


andMap : Effect a -> Effect (a -> b) -> Effect b
andMap =
    map2 (|>)


toDecoder : Effect a -> JD.Decoder a
toDecoder effect =
    case effect of
        EffectInProgress _ lookup ->
            JD.value |> JD.andThen (toDecoder << lookup)

        EffectSuccess a ->
            JD.succeed a

        EffectPlatformFailure err ->
            JD.fail err



-- EFFECT KIND


type EffectKind
    = EffectKindHttp InternalHttp.Request
    | EffectKindRandomInt32
    | EffectKindPosixTime


effectKindHash : EffectKind -> String
effectKindHash effectKind =
    JE.object (effectKindEncode effectKind)
        |> JE.encode 0
        |> FNV1a.hash
        |> String.fromInt


effectKindEncode : EffectKind -> List ( String, JD.Value )
effectKindEncode effectKind =
    case effectKind of
        EffectKindHttp request ->
            [ ( "effectKind", JE.string "Http" )
            , ( "payload", encodeRequest request )
            ]

        EffectKindRandomInt32 ->
            [ ( "effectKind", JE.string "RandomInt32" ) ]

        EffectKindPosixTime ->
            [ ( "effectKind", JE.string "PosixTime" ) ]



-- EFFECT STEP


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
                                        List.any (Tuple.first >> (==) (effectKindHash label))
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

        EffectPlatformFailure _ ->
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
                                    (( "hash", JE.string (effectKindHash a) )
                                        :: effectKindEncode a
                                    )
                            )
                  )
                ]

        Done _ ->
            JE.object
                [ ( "variant", JE.string "Done" )
                ]



-- POSIX TIME EFFECT


posixTime : Effect Int
posixTime =
    EffectInProgress [ EffectKindPosixTime ]
        (\value ->
            let
                result =
                    JD.decodeValue
                        (JD.field (effectKindHash EffectKindPosixTime) JD.int)
                        value
            in
            case result of
                Ok a ->
                    EffectSuccess a

                Err err ->
                    EffectPlatformFailure ("posixTime: " ++ JD.errorToString err)
        )



-- RANDOM INT 32 EFFECT


randomInt32 : Effect Int
randomInt32 =
    EffectInProgress [ EffectKindRandomInt32 ]
        (\value ->
            let
                result =
                    JD.decodeValue
                        (JD.field (effectKindHash EffectKindRandomInt32) JD.int)
                        value
            in
            case result of
                Ok a ->
                    EffectSuccess a

                Err err ->
                    EffectPlatformFailure ("randomInt32: " ++ JD.errorToString err)
        )



-- REQUEST EFFECT


sendRequest : InternalHttp.Request -> Effect InternalHttp.Response
sendRequest req =
    EffectInProgress [ EffectKindHttp req ]
        (\value ->
            JD.decodeValue
                (JD.field (effectKindHash (EffectKindHttp req))
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


encodeRequest : InternalHttp.Request -> JD.Value
encodeRequest request =
    JE.object
        [ ( "method", JE.string (requestMethodToString request.method) )
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


requestMethodToString : InternalHttp.Method -> String
requestMethodToString method =
    case method of
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
