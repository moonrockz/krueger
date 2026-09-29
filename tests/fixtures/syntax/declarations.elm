module Fixture.Declarations exposing (..)


infix right 0 (<|) = apL
infix left  0 (|>) = apR
infix non   4 (==) = eq


type Tree a
    = Leaf
    | Node (Tree a) a (Tree a)


type alias Pair a b =
    ( a, b )


type alias Named r =
    { r | name : String }


type alias Callback =
    () -> Int -> String
