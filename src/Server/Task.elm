module Server.Task exposing
    ( Task
    , andMap
    , andThen
    , await
    , fail
    , map
    , map2
    , mapError
    , succeed
    )

import Server.Effect as Effect
import Server.InternalTask as InternalTask


type alias Task err ok =
    InternalTask.Task err ok


succeed : ok -> Task err ok
succeed ok =
    InternalTask.succeed ok


fail : err -> Task err ok
fail err =
    InternalTask.fail err


map : (a -> b) -> Task err a -> Task err b
map transform task =
    let
        effect =
            InternalTask.toEffect task
                |> Effect.andThen
                    (\result ->
                        case result of
                            Ok ok ->
                                succeed (transform ok) |> InternalTask.toEffect

                            Err err ->
                                fail err |> InternalTask.toEffect
                    )
    in
    InternalTask.fromEffect effect


mapError : (a -> b) -> Task a ok -> Task b ok
mapError transform task =
    let
        effect =
            InternalTask.toEffect task
                |> Effect.andThen
                    (\result ->
                        case result of
                            Ok ok ->
                                succeed ok |> InternalTask.toEffect

                            Err err ->
                                fail (transform err) |> InternalTask.toEffect
                    )
    in
    InternalTask.fromEffect effect


andThen : (a -> Task err b) -> Task err a -> Task err b
andThen transform task =
    let
        effect =
            InternalTask.toEffect task
                |> Effect.andThen
                    (\result ->
                        case result of
                            Ok ok ->
                                transform ok |> InternalTask.toEffect

                            Err err ->
                                fail err |> InternalTask.toEffect
                    )
    in
    InternalTask.fromEffect effect


await : Task err a -> (a -> Task err b) -> Task err b
await task transform =
    andThen transform task


map2 : (a -> b -> c) -> Task err a -> Task err b -> Task err c
map2 transform taskA taskB =
    Effect.map2 (Result.map2 transform)
        (InternalTask.toEffect taskA)
        (InternalTask.toEffect taskB)
        |> InternalTask.fromEffect


andMap : Task err a -> Task err (a -> b) -> Task err b
andMap =
    map2 (|>)
