module Pages.Home exposing (application)

import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)
import MyApplication exposing (MyApplication)
import Random


type CardSuit
    = CardSuitDiamond
    | CardSuitClub
    | CardSuitHeart
    | CardSuitSpade


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


resolver : MyApplication.Resolver CardSuit
resolver =
    MyApplication.resolverRandomGenerate
        (Random.uniform CardSuitDiamond [ CardSuitClub, CardSuitHeart, CardSuitSpade ])


type alias Model =
    { count : Int
    , cardSuit : CardSuit
    }


init : CardSuit -> Model
init cardSuit =
    { count = 0
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


application : MyApplication CardSuit Model Msg
application =
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
