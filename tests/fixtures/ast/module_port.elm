port module Fixture.Port exposing (..)


port send : String -> Cmd msg


port receive : (String -> msg) -> Sub msg
