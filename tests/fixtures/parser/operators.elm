module Main exposing (..)


chains a b c =
    a ++ b ++ c :: [] |> f <| g


math x y =
    x + y * 2 - x // y ^ 2 ^ 3


compare x y =
    x == y && x /= y || x < y


negated x =
    f -x (-x) - x
