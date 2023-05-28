module Server exposing (..)

import Browser
import Json.Decode as JD
import Json.Encode as JE
import Random


type GeneratedProgram flags model msg
    = GeneratedProgram
        { init : flags -> ( model, Cmd msg )
        , view : model -> Browser.Document msg
        , update : msg -> model -> ( model, Cmd msg )
        , subscriptions : model -> Sub msg
        , resolver : Resolver flags
        }


generatedDocument :
    { init : flags -> ( model, Cmd msg )
    , view : model -> Browser.Document msg
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , resolver : Resolver flags
    }
    -> GeneratedProgram flags model msg
generatedDocument impl =
    GeneratedProgram impl


generatedToBrowserDocument : GeneratedProgram flags model msg -> Program JD.Value model msg
generatedToBrowserDocument (GeneratedProgram impl) =
    Browser.document
        { init =
            let
                myInit : JD.Value -> ( model, Cmd msg )
                myInit value =
                    JD.decodeValue (resolverToDecoder impl.resolver) value
                        |> Result.map impl.init
                        |> resultWithDefaultLazy
                            (\_ ->
                                -- FIXME avoid crash
                                myInit value
                            )
            in
            myInit
        , view = impl.view
        , update = impl.update
        , subscriptions = impl.subscriptions
        }


generatedToResolver : GeneratedProgram flags model msg -> Resolver flags
generatedToResolver (GeneratedProgram impl) =
    impl.resolver


resultWithDefaultLazy : (() -> a) -> Result x a -> a
resultWithDefaultLazy toDef result =
    case result of
        Ok a ->
            a

        Err _ ->
            toDef ()


type Resolver a
    = Resolver (List ResolverTask) (JD.Value -> Resolver a)
    | ResolverSuccess a


resolverSucceed : a -> Resolver a
resolverSucceed =
    ResolverSuccess


resolverMap : (a -> b) -> Resolver a -> Resolver b
resolverMap f resolver =
    case resolver of
        Resolver tasks lookup ->
            Resolver tasks (\value -> resolverMap f (lookup value))

        ResolverSuccess a ->
            ResolverSuccess (f a)


resolverMap2 : (a -> b -> c) -> Resolver a -> Resolver b -> Resolver c
resolverMap2 f resolverA resolverB =
    case ( resolverA, resolverB ) of
        ( Resolver tasksA lookupA, Resolver tasksB lookupB ) ->
            Resolver (tasksA ++ tasksB) (\value -> resolverMap2 f (lookupA value) (lookupB value))

        ( ResolverSuccess a, ResolverSuccess b ) ->
            ResolverSuccess (f a b)

        ( ResolverSuccess a, Resolver tasksB lookupB ) ->
            Resolver tasksB (\value -> resolverMap2 f (ResolverSuccess a) (lookupB value))

        ( Resolver tasksA lookupA, ResolverSuccess b ) ->
            Resolver tasksA (\value -> resolverMap2 f (lookupA value) (ResolverSuccess b))


resolverAndMap : Resolver a -> Resolver (a -> b) -> Resolver b
resolverAndMap =
    resolverMap2 (|>)



-- {-| FIXME Each resolve in andThen depends on previous, cannot parallelize.
--
-- The andThen stuff could live in a worker dealing with `JD.Value -> List Task`
-- this way, the worker could inform the server about the next tasks or a success.
--
-- -}
-- resolverAndThen : (a -> Resolver b) -> Resolver a -> Resolver b
-- resolverAndThen f resolver =
--     case resolver of
--         ResolverSuccess a ->
--             f a
--
--         Resolver tasks lookup ->
--             Resolver tasks (\value -> resolverAndThen f (lookup value))


resolverToDecoder : Resolver a -> JD.Decoder a
resolverToDecoder resolver =
    case resolver of
        Resolver _ lookup ->
            JD.value |> JD.andThen (resolverToDecoder << lookup)

        ResolverSuccess a ->
            JD.succeed a


encodeResolver : Resolver a -> JE.Value
encodeResolver resolver =
    case resolver of
        Resolver tasks _ ->
            JE.list encodeTask tasks

        ResolverSuccess _ ->
            JE.list (\_ -> JE.null) []


resolverTimeNowMillis : Resolver Int
resolverTimeNowMillis =
    Resolver [ ResolverTaskTimeNowMillis ]
        (\value ->
            JD.decodeValue
                (JD.field (resolverTaskToString ResolverTaskTimeNowMillis) JD.int)
                value
                -- FIXME handle error, or not somehow?
                |> Result.withDefault -420
                |> ResolverSuccess
        )


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
    Resolver [ ResolverTaskRandomSeed ]
        (\value ->
            JD.decodeValue
                (JD.field (resolverTaskToString ResolverTaskRandomSeed) JD.int)
                value
                -- FIXME handle error, or not somehow?
                |> Result.withDefault -420
                |> ResolverSuccess
        )


type ResolverTask
    = ResolverTaskTimeNowMillis
    | ResolverTaskRandomSeed


resolverTaskToString : ResolverTask -> String
resolverTaskToString task =
    case task of
        ResolverTaskTimeNowMillis ->
            "ResolverTaskTimeNowMillis"

        ResolverTaskRandomSeed ->
            "ResolverTaskRandomSeed"


encodeTask : ResolverTask -> JE.Value
encodeTask task =
    JE.string (resolverTaskToString task)
