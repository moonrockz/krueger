module Fixture exposing (..)


x =
    1


f =
    case ( x, x ) of
        ( 1
        , 2 ) ->
            1

        _ ->
            3
