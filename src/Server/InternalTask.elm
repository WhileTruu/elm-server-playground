module Server.InternalTask exposing (Task, fail, fromEffect, succeed, toEffect)

import Server.Effect as Effect exposing (Effect)


type Task err ok
    = Task (Effect (Result err ok))


succeed : ok -> Task err ok
succeed ok =
    Task (Effect.always (Ok ok))


fail : err -> Task err ok
fail err =
    Task (Effect.always (Err err))


fromEffect : Effect (Result err ok) -> Task err ok
fromEffect effect =
    Task effect


toEffect : Task err ok -> Effect (Result err ok)
toEffect (Task effect) =
    effect
