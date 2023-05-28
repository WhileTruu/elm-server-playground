module Generate exposing (main)

{-| -}

import Elm
import Elm.Annotation as Annotation
import Elm.Op
import Gen.Basics
import Gen.CodeGen.Generate as Generate
import Gen.Dict
import Gen.Json.Decode
import Gen.Json.Encode
import Gen.Maybe
import Gen.Platform
import Gen.Platform.Cmd
import Gen.Platform.Sub
import Gen.Tuple
import Json.Decode
import String.Extra as String


main : Program Json.Decode.Value () ()
main =
    Generate.fromJson Json.Decode.string <|
        \flags ->
            let
                modules =
                    modulesFromFlags { flags = flags }
            in
            [ modules
                |> List.map file
                |> List.map (\a -> { a | path = "pages/" ++ a.path })
            , [ workerFile modules
              ]
            ]
                |> List.concat


toPageModuleName : List String -> List String
toPageModuleName moduleName =
    "Pages" :: List.map String.toSentenceCase moduleName


modulesFromFlags : { flags : String } -> List (List String)
modulesFromFlags { flags } =
    flags
        |> String.toLower
        |> String.split ","
        |> List.map (String.dropRight 4)
        |> List.map (String.split "/")


file : List String -> Elm.File
file moduleName =
    Elm.file moduleName
        [ Elm.declaration "main"
            (Elm.apply
                (Elm.value
                    { importFrom = [ "Server" ]
                    , name = "generatedToBrowserDocument"
                    , annotation = Nothing
                    }
                )
                [ Elm.value
                    { importFrom = toPageModuleName moduleName
                    , name = "program"
                    , annotation = Nothing
                    }
                ]
            )
        ]



-- WORKER


workerFile modules =
    Elm.file [ "Worker" ]
        [ Elm.declaration "resolvers" <|
            Gen.Dict.fromList <|
                (modules
                    |> List.map toPageModuleName
                    |> List.map
                        (\pageModuleName ->
                            Elm.value
                                { importFrom = pageModuleName
                                , name = "program"
                                , annotation = Nothing
                                }
                                |> Elm.Op.pipe
                                    (Elm.value
                                        { importFrom = [ "Server" ]
                                        , name = "generatedToTask"
                                        , annotation = Nothing
                                        }
                                    )
                                |> Elm.Op.pipe
                                    (Elm.value
                                        { importFrom = [ "Server", "InternalTask" ]
                                        , name = "toEffect"
                                        , annotation = Nothing
                                        }
                                    )
                                |> Elm.Op.pipe
                                    (Elm.value
                                        { importFrom = [ "Server", "Effect" ]
                                        , name = "effectResultFrom"
                                        , annotation = Nothing
                                        }
                                    )
                                |> Elm.Op.pipe
                                    (Elm.fn ( "effectResultFromValue", Nothing )
                                        (\effectResultFromValue ->
                                            Elm.fn ( "value", Just Gen.Json.Decode.annotation_.value )
                                                (\value ->
                                                    Elm.apply effectResultFromValue [ value ]
                                                        |> Elm.Op.pipe
                                                            (Elm.value
                                                                { importFrom = [ "Server", "Effect" ]
                                                                , name = "encodeEffectResult"
                                                                , annotation = Nothing
                                                                }
                                                            )
                                                        |> Elm.withType Gen.Json.Decode.annotation_.value
                                                )
                                        )
                                    )
                                |> Elm.tuple (Elm.string (String.join "." pageModuleName))
                        )
                )
        , Elm.declaration "main" <|
            Gen.Platform.worker
                { init =
                    \_ ->
                        Elm.tuple Elm.unit Gen.Platform.Cmd.none
                , update =
                    \msg _ ->
                        let
                            encodedEffectResult =
                                Gen.Dict.get (Gen.Tuple.first msg) (Elm.val "resolvers")
                                    |> Elm.Op.pipe
                                        (Elm.apply Gen.Maybe.values_.map
                                            [ Elm.fn ( "f", Nothing )
                                                (\f ->
                                                    Elm.apply f [ Gen.Tuple.second msg ]
                                                )
                                            ]
                                        )
                                    |> Elm.Op.pipe
                                        (Elm.apply
                                            Gen.Maybe.values_.withDefault
                                            [ Gen.Json.Encode.null ]
                                        )
                        in
                        Elm.tuple Elm.unit
                            (Elm.apply (Elm.val "put")
                                [ encodedEffectResult
                                ]
                            )
                , subscriptions =
                    \_ ->
                        Elm.apply (Elm.val "get")
                            [ Elm.fn
                                ( "a"
                                , Just
                                    (Annotation.tuple
                                        Annotation.string
                                        Gen.Json.Encode.annotation_.value
                                    )
                                )
                                (\a -> a)
                            ]
                }
        , Elm.portOutgoing "put" Gen.Json.Encode.annotation_.value
        , Elm.portIncoming "get"
            [ Annotation.tuple
                Annotation.string
                Gen.Json.Encode.annotation_.value
            ]
        ]
        |> replaceInvalidImports
        |> (\a ->
                { a
                    | contents =
                        String.replace
                            "main : Platform.Program () () ()"
                            "main : Platform.Program () () ( String, Json.Encode.Value )"
                            a.contents
                }
           )



-- HELPERS


replaceInvalidImports : Elm.File -> Elm.File
replaceInvalidImports elmFile =
    { elmFile
        | contents =
            elmFile.contents
                |> String.replace "import Sub\n" ""
                |> String.replace "import Cmd\n" ""
    }
