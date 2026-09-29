module Fixture.Patterns exposing (..)


patterns x =
    case x of
        _ ->
            ()

        () ->
            1

        'c' ->
            1

        "s" ->
            1

        1 ->
            1

        0x10 ->
            1

        ( a, b ) ->
            1

        { f, g } ->
            1

        h :: t ->
            1

        [ i, j ] ->
            1

        Just (Maybe.Just k) ->
            1

        ((Ok v) as whole) ->
            1
