// Run the elm-syntax oracle on files given as arguments; print one JSON line per file.
const fs = require("fs");
const path = require("path");
const { Elm } = require(path.join(__dirname, "oracle.js"));

const inputs = process.argv.slice(2).map((name) => ({ name, source: fs.readFileSync(name, "utf8") }));
const app = Elm.Oracle.init({ flags: inputs });
app.ports.result.subscribe((value) => {
  process.stdout.write(JSON.stringify(value) + "\n");
});
