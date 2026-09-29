module Fixture.Expressions exposing (..)


values =
    [ ( (), 42, 0xFF ), ( 3.14, -x ), ( "text", 'c', """multi
line""" ) ]


operators a b =
    (a + b) * 2 - a // b == 3 && True || not False


pipes x =
    x |> f |> g


composed =
    (+) 1 >> negate << abs


structures r =
    [ { r | field = 1 }, { a = 1, b = [] }, r.field, .field, List.map ]


control x =
    if x then
        let
            y =
                1

            ( p, q ) =
                pair
        in
        case y of
            0 ->
                p

            _ ->
                \n -> n + q

    else
        0


shader =
    [glsl| void main() {} |]
