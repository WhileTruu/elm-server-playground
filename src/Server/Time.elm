module Server.Time exposing (now)

import Server.Effect as Effect
import Server.InternalTask as InternalTask
import Server.Task exposing (Task)


now : Task err Int
now =
    Effect.posixTime
        |> Effect.map Ok
        |> InternalTask.fromEffect
