module Pages.Home exposing (program)

import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)
import Random
import Server
import Server.Random
import Server.Task as Task exposing (Task)
import Server.Time


type alias Resolved =
    { now : Int
    , cardSuit : CardSuit
    }


resolver : Task Never Resolved
resolver =
    Task.succeed
        (\cardSuit timeNowMillis ->
            { now = timeNowMillis
            , cardSuit = cardSuit
            }
        )
        |> Task.andThen (\f -> Task.map f (Server.Random.generate cardSuitRandomGenerator))
        |> Task.andThen (\f -> Task.map f Server.Time.now)


type alias Model =
    { count : Int
    , cardSuit : CardSuit
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


init : { a | now : Int, cardSuit : CardSuit } -> Model
init { now, cardSuit } =
    { count = now
    , cardSuit = cardSuit
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
        ]
    ]


program : Server.GeneratedProgram Resolved Model Msg
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
