module Server.Random exposing (generate, int32)

import Random
import Server.Effect as Effect
import Server.InternalTask as InternalTask
import Server.Task as Task exposing (Task)


generate : Random.Generator a -> Task err a
generate generator =
    int32
        |> Task.map
            (Random.initialSeed
                >> Random.step generator
                >> Tuple.first
            )


int32 : Task err Int
int32 =
    Effect.randomInt32
        |> Effect.map Ok
        |> InternalTask.fromEffect
