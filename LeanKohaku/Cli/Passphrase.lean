/-!
# CLI passphrase input

Small helper for commands that need a passphrase before forwarding the request
to the daemon. `LEANKOHAKU_PASSPHRASE` is accepted for scripted tests; the
interactive fallback disables terminal echo when possible.
-/

namespace LeanKohaku.Cli.Passphrase

private def runStty (arg : String) : IO Unit := do
  try
    let child ← IO.Process.spawn
      { cmd := "sh",
        args := #["-c", "stty " ++ arg ++ " < /dev/tty"],
        stdout := .inherit,
        stderr := .inherit }
    discard <| child.wait
  catch _ =>
    pure ()

private def prompt (label : String) : IO Unit := do
  (← IO.getStderr).putStr label
  (← IO.getStderr).flush

def read (label : String := "Passphrase: ") : IO String := do
  match ← IO.getEnv "LEANKOHAKU_PASSPHRASE" with
  | some passphrase => pure passphrase
  | none =>
      prompt label
      runStty "-echo"
      try
        let line ← (← IO.getStdin).getLine
        (← IO.getStderr).putStrLn ""
        pure line.trimAsciiEnd.toString
      finally
        runStty "echo"

end LeanKohaku.Cli.Passphrase
