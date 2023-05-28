module Server exposing (..)

import Browser
import Json.Decode as JD
import Server.Effect as Effect
import Server.InternalTask as InternalTask
import Server.Task as Task exposing (Task)


type GeneratedProgram resolved model msg
    = GeneratedProgram
        { init : resolved -> ( model, Cmd msg )
        , view : model -> Browser.Document msg
        , update : msg -> model -> ( model, Cmd msg )
        , subscriptions : model -> Sub msg
        , resolver : Task Never resolved
        }


generatedDocument :
    { init : resolved -> ( model, Cmd msg )
    , view : model -> Browser.Document msg
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , resolver : Task Never resolved
    }
    -> GeneratedProgram resolved model msg
generatedDocument impl =
    GeneratedProgram impl


generatedToBrowserDocument :
    GeneratedProgram resolved model msg
    -> Program JD.Value model msg
generatedToBrowserDocument (GeneratedProgram impl) =
    Browser.document
        { init =
            let
                myInit : JD.Value -> ( model, Cmd msg )
                myInit value =
                    InternalTask.toEffect impl.resolver
                        |> Effect.toDecoder
                        -- JD.Decoder (Result err ok)
                        |> (\decoder -> JD.decodeValue decoder value)
                        |> (\res ->
                                Result.andThen
                                    (Result.mapError (\_ -> ()))
                                    (Result.mapError (\_ -> ()) res)
                           )
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


generatedToTask : GeneratedProgram flags model msg -> Task Never flags
generatedToTask (GeneratedProgram impl) =
    impl.resolver


resultWithDefaultLazy : (() -> a) -> Result x a -> a
resultWithDefaultLazy toDef result =
    case result of
        Ok a ->
            a

        Err _ ->
            toDef ()
