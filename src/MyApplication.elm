module MyApplication exposing (..)

import Browser
import Json.Decode as JD
import Json.Encode as JE
import Random


type alias MyApplication flags model msg =
    { init : flags -> ( model, Cmd msg )
    , view : model -> Browser.Document msg
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , resolver : Resolver flags
    }


toBrowserDocument : MyApplication flags model msg -> Program JD.Value model msg
toBrowserDocument a =
    Browser.document
        { init =
            let
                myInit : JD.Value -> ( model, Cmd msg )
                myInit value =
                    JD.decodeValue (resolverToDecoder a.resolver) value
                        |> Result.map a.init
                        |> resultWithDefaultLazy
                            (\_ ->
                                -- FIXME avoid crash
                                myInit value
                            )
            in
            myInit
        , view = a.view
        , update = a.update
        , subscriptions = a.subscriptions
        }


resultWithDefaultLazy : (() -> a) -> Result x a -> a
resultWithDefaultLazy toDef result =
    case result of
        Ok a ->
            a

        Err _ ->
            toDef ()


type Resolver a
    = Resolver
        { task : ResolverTask
        , decoder : JD.Decoder a
        }


resolverMap : (a -> b) -> Resolver a -> Resolver b
resolverMap f (Resolver resolver) =
    Resolver
        { task = resolver.task
        , decoder = resolver.decoder |> JD.map f
        }


resolverToDecoder : Resolver a -> JD.Decoder a
resolverToDecoder (Resolver resolver) =
    resolver.decoder


encodeResolver : Resolver a -> JE.Value
encodeResolver (Resolver resolver) =
    encodeTask resolver.task


resolverTimeNowMillis : Resolver Int
resolverTimeNowMillis =
    Resolver
        { task = ResolverTaskTimeNowMillis
        , decoder = JD.int
        }


resolverRandomGenerate : Random.Generator value -> Resolver value
resolverRandomGenerate generator =
    resolverRandomInt32
        |> resolverMap
            (Random.initialSeed
                >> Random.step generator
                >> Tuple.first
            )


resolverRandomInt32 : Resolver Int
resolverRandomInt32 =
    Resolver
        { task = ResolverTaskRandomSeed
        , decoder = JD.int
        }


type ResolverTask
    = ResolverTaskTimeNowMillis
    | ResolverTaskRandomSeed


encodeTask : ResolverTask -> JE.Value
encodeTask task =
    case task of
        ResolverTaskTimeNowMillis ->
            JE.string "ResolverTaskTimeNowMillis"

        ResolverTaskRandomSeed ->
            JE.string "ResolverTaskRandomSeed"
