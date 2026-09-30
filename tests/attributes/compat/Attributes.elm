module Fixture exposing (Account, balance, tag)

{-| Accounts with attributes in their doc comments.

@morphir { package = "Bank" }

@docs Account, balance, tag

-}


{-| A customer account.

@deprecated "Use Account.V2"
@derive [ Json.encoder, Json.decoder ]
@morphir { kind = "entity", key = "id" }
@unit "EUR"

-}
type alias Account =
    { id : String, balance : Float }


{-| The balance. Some prose first.
@pure
@morphir
{ kind = "function"
, total = True
}
-}
balance : Account -> Float
balance account =
    account.balance


{-| A tag.

@tag one two

-}
tag : Int
tag =
    1
