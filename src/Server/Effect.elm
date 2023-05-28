module Server.Effect exposing
    ( Effect
    , always
    , andThen
    , effectResultFrom
    , encodeEffectResult
    , map
    , map2
    , posixTime
    , randomInt32
    , toDecoder
    )

import Json.Decode as JD
import Json.Encode as JE



-- if requests are needed, hashing needs to be introduced instead of labels,
-- since multiple requests can be made to the same endpoint with different payloads


type Effect a
    = EffectInProgress (List String) (JD.Value -> Effect a)
    | EffectSuccess a


type EffectStep a
    = EffectStepLabels (List String)
    | EffectStepSuccess a


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
    EffectInProgress [ "PosixTime" ]
        (\value ->
            JD.decodeValue
                (JD.field "PosixTime" JD.int)
                value
                -- FIXME handle error, or not somehow?
                |> Result.withDefault -420
                |> EffectSuccess
        )


randomInt32 : Effect Int
randomInt32 =
    EffectInProgress [ "RandomInt32" ]
        (\value ->
            JD.decodeValue
                (JD.field "RandomInt32" JD.int)
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


type EffectResult
    = EffectResultLabels (List String)
    | EffectResultSuccess


effectResultFrom : Effect a -> JD.Value -> EffectResult
effectResultFrom effect value =
    case effect of
        EffectInProgress labels lookup ->
            JD.decodeValue (JD.keyValuePairs JD.value) value
                |> Result.map
                    (\resolvedPairs ->
                        let
                            areAllLabelsInResolvedPairs =
                                List.all
                                    (\label ->
                                        List.any (Tuple.first >> (==) label)
                                            resolvedPairs
                                    )
                                    labels
                        in
                        if areAllLabelsInResolvedPairs then
                            effectResultFrom (lookup value) value

                        else
                            EffectResultLabels labels
                    )
                |> Result.withDefault (EffectResultLabels labels)

        EffectSuccess a ->
            EffectResultSuccess


encodeEffectResult : EffectResult -> JD.Value
encodeEffectResult result =
    case result of
        EffectResultLabels labels ->
            JE.object
                [ ( "variant", JE.string "EffectResultLabels" )
                , ( "payload", JE.list JE.string labels )
                ]

        EffectResultSuccess ->
            JE.object
                [ ( "variant", JE.string "EffectResultSuccess" )
                ]
