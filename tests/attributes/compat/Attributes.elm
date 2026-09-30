module Fixture exposing (Account, balance, rate, tag)

{-| Accounts with attributes in their doc comments.

@morphir `{ package = "Bank" }`

@docs Account, balance, rate, tag

-}


{-| A customer account.

```-attributes:
@deprecated "Use Account.V2"
@derive [ Json.encoder, Json.decoder ]
@morphir
    { kind = "entity"
    , key = "account_id"
    , note = "a*b*c"
    }
```

-}
type alias Account =
    { id : String, balance : Float }


{-| The balance.

    -attributes:
    @pure
    @morphir { kind = "function", url = "http://x.org/a_b" }

-}
balance : Account -> Float
balance account =
    account.balance


{-| A rate.

@unit `"EUR"`
@tag `one two`

-}
rate : Float
rate =
    1.5


{-| A tag.

@tag one two

-}
tag : Int
tag =
    1
