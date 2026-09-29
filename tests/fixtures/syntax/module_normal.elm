module Fixture.Normal exposing
    ( Msg(..)
    , Model
    , view
    , (|>)
    )

import Html
import Html.Attributes as Attr exposing (..)
import Json.Decode as Decode exposing (Decoder, field, (|.))


{-| The model.
-}
type alias Model =
    { count : Int }


type Msg
    = Inc
    | Set Int


view : Model -> Int
view model =
    model.count
