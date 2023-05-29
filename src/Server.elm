module Server exposing (..)

import Browser
import Html
import Json.Decode as JD
import Server.Effect as Effect
import Server.InternalTask as InternalTask
import Server.Task as Task exposing (Task)


type GeneratedProgram resolverError resolved model msg
    = GeneratedProgram
        { init : resolved -> ( model, Cmd msg )
        , view : model -> Browser.Document msg
        , update : msg -> model -> ( model, Cmd msg )
        , subscriptions : model -> Sub msg
        , resolver : Task resolverError resolved
        }


generatedDocument :
    { init : resolved -> ( model, Cmd msg )
    , view : model -> Browser.Document msg
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , resolver : Task resolverError resolved
    }
    -> GeneratedProgram resolverError resolved model msg
generatedDocument impl =
    GeneratedProgram impl


generatedToBrowserDocument :
    GeneratedProgram resolverError resolved model msg
    -> Program JD.Value (Model resolverError model) (Msg msg)
generatedToBrowserDocument (GeneratedProgram impl) =
    Browser.document
        { init =
            \value ->
                let
                    result =
                        InternalTask.toEffect impl.resolver
                            |> Effect.toDecoder
                            |> (\decoder -> JD.decodeValue decoder value)
                            |> (\res ->
                                    Result.andThen
                                        (Result.mapError ResolverError)
                                        (Result.mapError PlatformError res)
                               )
                            |> Result.map impl.init
                in
                case result of
                    Ok ( model, cmd ) ->
                        ( Model model, Cmd.map Msg cmd )

                    Err errorModel ->
                        ( errorModel, Cmd.none )
        , view =
            \model ->
                case model of
                    Model implModel ->
                        let
                            { title, body } =
                                impl.view implModel
                        in
                        { title = title
                        , body = body |> List.map (Html.map Msg)
                        }

                    PlatformError platformError ->
                        { title = "Platform error"
                        , body = [ Html.text <| "Error: " ++ JD.errorToString platformError ]
                        }

                    ResolverError _ ->
                        { title = "Resolver error"
                        , body =
                            [ Html.text <| "FIXME: Resolver error, add a way to turn that info useful info?"
                            ]
                        }
        , update =
            \msg model ->
                case ( msg, model ) of
                    ( Msg implMsg, Model implModel ) ->
                        impl.update implMsg implModel
                            |> Tuple.mapBoth Model (Cmd.map Msg)

                    ( _, _ ) ->
                        ( model, Cmd.none )
        , subscriptions =
            \model ->
                case model of
                    Model implModel ->
                        impl.subscriptions implModel
                            |> Sub.map Msg

                    _ ->
                        Sub.none
        }


type Model resolverError model
    = Model model
    | PlatformError JD.Error
    | ResolverError resolverError


type Msg msg
    = Msg msg
    | ErrorMsg


generatedToTask : GeneratedProgram resolverError flags model msg -> Task resolverError flags
generatedToTask (GeneratedProgram impl) =
    impl.resolver


resultWithDefaultLazy : (() -> a) -> Result x a -> a
resultWithDefaultLazy toDef result =
    case result of
        Ok a ->
            a

        Err _ ->
            toDef ()
