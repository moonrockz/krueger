effect module Fixture.Effect where { command = MyCmd, subscription = MySub } exposing (MyCmd, MySub)


type MyCmd msg
    = Go


type MySub msg
    = Watch
