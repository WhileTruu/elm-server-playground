module Pages.Home exposing (application)

import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)
import MyApplication


resolver : MyApplication.Resolver Int
resolver =
    MyApplication.resolverTimeNowMillis


type alias Model =
    { count : Int }


init : Int -> Model
init timeNowMillis =
    { count = timeNowMillis
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
        , button [ onClick Decrement ] [ text "-1" ]
        ]
    ]


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
