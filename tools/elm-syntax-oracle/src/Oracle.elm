port module Oracle exposing (main)

{-| Parse Elm sources with stil4m/elm-syntax and return the File JSON.

Flags: a list of `{ name, source }`. For each input the `result` port sends
`{ name, ok: true, file: <Elm.Syntax.File JSON> }` or
`{ name, ok: false, error: <dead ends as text> }`.
-}

import Elm.Parser
import Elm.Syntax.File
import Json.Decode as Decode
import Json.Encode as Encode
import Parser


port result : Encode.Value -> Cmd msg


type alias Input =
    { name : String
    , source : String
    }


main : Program Decode.Value () ()
main =
    Platform.worker
        { init = init
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


init : Decode.Value -> ( (), Cmd () )
init flags =
    case Decode.decodeValue (Decode.list inputDecoder) flags of
        Ok inputs ->
            ( (), Cmd.batch (List.map (parse >> result) inputs) )

        Err err ->
            ( (), result (Encode.object [ ( "fatal", Encode.string (Decode.errorToString err) ) ]) )


inputDecoder : Decode.Decoder Input
inputDecoder =
    Decode.map2 Input
        (Decode.field "name" Decode.string)
        (Decode.field "source" Decode.string)


parse : Input -> Encode.Value
parse input =
    case Elm.Parser.parseToFile input.source of
        Ok file ->
            Encode.object
                [ ( "name", Encode.string input.name )
                , ( "ok", Encode.bool True )
                , ( "file", Elm.Syntax.File.encode file )
                ]

        Err deadEnds ->
            Encode.object
                [ ( "name", Encode.string input.name )
                , ( "ok", Encode.bool False )
                , ( "error", Encode.string (Parser.deadEndsToString deadEnds) )
                ]
