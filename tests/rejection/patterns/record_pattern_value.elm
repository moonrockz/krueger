module Fixture exposing (..)


x =
    1


f =
    case { a = 1 } of
        { a = 1 } ->
            1

        _ ->
            2
