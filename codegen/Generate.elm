module Generate exposing (main)

{-| -}

import Elm
import Gen.CodeGen.Generate as Generate
import Gen.Json.Encode
import Gen.Platform
import Gen.Platform.Cmd
import Gen.Platform.Sub
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
            , [ Elm.file [ "Worker" ]
                    [ Elm.declaration "main" <|
                        Gen.Platform.worker
                            { init =
                                \_ ->
                                    Elm.tuple Elm.unit
                                        (Elm.apply (Elm.val "put")
                                            [ Gen.Json.Encode.object
                                                (modules
                                                    |> List.map toPageModuleName
                                                    |> List.map
                                                        (\pageModuleName ->
                                                            Elm.apply
                                                                (Elm.value
                                                                    { importFrom = [ "Server" ]
                                                                    , name = "encodeResolver"
                                                                    , annotation = Nothing
                                                                    }
                                                                )
                                                                [ Elm.apply
                                                                    (Elm.value
                                                                        { importFrom = [ "Server" ]
                                                                        , name = "generatedToResolver"
                                                                        , annotation = Nothing
                                                                        }
                                                                    )
                                                                    [ Elm.value
                                                                        { importFrom = pageModuleName
                                                                        , name = "program"
                                                                        , annotation = Nothing
                                                                        }
                                                                    ]
                                                                ]
                                                                |> Elm.tuple (Elm.string (String.join "." pageModuleName))
                                                        )
                                                )
                                            ]
                                        )
                            , update =
                                \_ _ ->
                                    Elm.tuple Elm.unit Gen.Platform.Cmd.none
                            , subscriptions =
                                \_ ->
                                    Gen.Platform.Sub.none
                            }
                    , Elm.portOutgoing "put" Gen.Json.Encode.annotation_.value
                    ]
                    |> replaceInvalidImports
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



-- HELPERS


replaceInvalidImports : Elm.File -> Elm.File
replaceInvalidImports elmFile =
    { elmFile
        | contents =
            elmFile.contents
                |> String.replace "import Sub\n" ""
                |> String.replace "import Cmd\n" ""
    }
