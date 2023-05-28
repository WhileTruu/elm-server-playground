module Pages.Home exposing (program)

import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)
import Json.Decode
import Random
import Server
import Server.Http as Http
import Server.Random
import Server.Task as Task exposing (Task)
import Server.Time


type alias Resolved =
    { now : Int
    , cardSuit : CardSuit
    , publicOpinion : String
    }


resolver : Task Http.Error Resolved
resolver =
    Task.succeed
        (\cardSuit timeNowMillis publicOpinion ->
            { now = timeNowMillis
            , cardSuit = cardSuit
            , publicOpinion = publicOpinion
            }
        )
        |> Task.andThen (\f -> Task.map f (Server.Random.generate cardSuitRandomGenerator))
        |> Task.andThen (\f -> Task.map f Server.Time.now)
        |> Task.mapError never
        |> Task.andThen
            (\f ->
                Task.map f
                    (Http.get
                        { url = "https://elm-lang.org/assets/public-opinion.txt"
                        , decoder = Json.Decode.string
                        }
                    )
            )


type alias Model =
    { count : Int
    , cardSuit : CardSuit
    , publicOpinion : String
    }


type CardSuit
    = CardSuitDiamond
    | CardSuitClub
    | CardSuitHeart
    | CardSuitSpade


cardSuitRandomGenerator : Random.Generator CardSuit
cardSuitRandomGenerator =
    Random.uniform CardSuitDiamond [ CardSuitClub, CardSuitHeart, CardSuitSpade ]


cardSuitToString : CardSuit -> String
cardSuitToString cardSuit =
    case cardSuit of
        CardSuitDiamond ->
            "Diamond"

        CardSuitClub ->
            "Club"

        CardSuitHeart ->
            "Heart"

        CardSuitSpade ->
            "Spade"


init : Resolved -> Model
init { now, cardSuit, publicOpinion } =
    { count = now
    , cardSuit = cardSuit
    , publicOpinion = publicOpinion
    }


type Msg
    = Increment
    | Decrement


update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = model.count + 1 }

        Decrement ->
            { model | count = model.count - 1 }


view : Model -> List (Html Msg)
view model =
    [ div []
        [ button [ onClick Increment ] [ text "+1" ]
        , div [] [ text <| String.fromInt model.count ]
        , div [] [ text <| cardSuitToString model.cardSuit ]
        , button [ onClick Decrement ] [ text "-1" ]
        , Html.p []
            [ text model.publicOpinion
            ]
        ]
    ]


program : Server.GeneratedProgram Http.Error Resolved Model Msg
program =
    Server.generatedDocument
        { init = \flags -> ( init flags, Cmd.none )
        , view =
            \model ->
                { title = "Home"
                , body = view model
                }
        , update = \msg model -> ( update msg model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        , resolver = resolver
        }
