import LeanKohaku.Crypto.Hacl
import LeanKohaku.Crypto.Hex
import LeanKohaku.Crypto.Random
import LeanKohaku.Encoding.Json

/-!
# Encrypted EOA seed storage

Small JSON store for encrypted EOA seeds. The daemon will call this module;
the CLI must not import it after the library split.
-/

namespace LeanKohaku.Wallet.EoaStore

open LeanKohaku.Encoding.Json

structure Record where
  version        : Nat
  name           : String
  kdfSalt        : ByteArray
  kdfIters       : Nat
  aeadNonce      : ByteArray
  ciphertext     : ByteArray
  derivationPath : String
  address        : String
  createdAt      : Nat

def defaultKdfIters : Nat := 100000

private def dirMode : IO.FileRight :=
  { user := { read := true, write := true, execution := true } }

private def fileMode : IO.FileRight :=
  { user := { read := true, write := true } }

def dataHome : IO System.FilePath := do
  match ← IO.getEnv "XDG_DATA_HOME" with
  | some dir => pure dir
  | none =>
      match ← IO.getEnv "HOME" with
      | some home => pure (home ++ "/.local/share")
      | none => pure ".leankohaku"

def storeDir : IO System.FilePath := do
  pure ((← dataHome) / "leankohaku" / "eoa")

def slotPath (name : String) : IO System.FilePath := do
  pure ((← storeDir) / (name ++ ".json"))

def ensureStoreDir : IO Unit := do
  let dir ← storeDir
  IO.FS.createDirAll dir
  IO.setAccessRights dir dirMode

private def hex (bytes : ByteArray) : Json :=
  .str (LeanKohaku.Crypto.Hex.encode bytes)

def Record.toJson (r : Record) : Json :=
  .obj #[
    ("version", .num (Int.ofNat r.version)),
    ("name", .str r.name),
    ("kdfSalt", hex r.kdfSalt),
    ("kdfIters", .num (Int.ofNat r.kdfIters)),
    ("aeadNonce", hex r.aeadNonce),
    ("ciphertext", hex r.ciphertext),
    ("derivationPath", .str r.derivationPath),
    ("address", .str r.address),
    ("createdAt", .num (Int.ofNat r.createdAt))
  ]

private def fieldString (obj : Json) (key : String) : Except String String :=
  match getField key obj >>= asString with
  | some value => .ok value
  | none => .error s!"missing string field: {key}"

private def fieldNat (obj : Json) (key : String) : Except String Nat :=
  match getField key obj >>= asNat with
  | some value => .ok value
  | none => .error s!"missing natural-number field: {key}"

private def fieldBytes (obj : Json) (key : String) : Except String ByteArray :=
  match getField key obj >>= asBytes with
  | some value => .ok value
  | none => .error s!"missing hex field: {key}"

def Record.fromJson (json : Json) : Except String Record := do
  let version ← fieldNat json "version"
  let name ← fieldString json "name"
  let kdfSalt ← fieldBytes json "kdfSalt"
  let kdfIters ← fieldNat json "kdfIters"
  let aeadNonce ← fieldBytes json "aeadNonce"
  let ciphertext ← fieldBytes json "ciphertext"
  let derivationPath ← fieldString json "derivationPath"
  let address ← fieldString json "address"
  let createdAt ← fieldNat json "createdAt"
  if version != 1 then
    .error s!"unsupported EOA store version: {version}"
  else if kdfSalt.size = 0 then
    .error "empty KDF salt"
  else if aeadNonce.size != 12 then
    .error "AEAD nonce must be 12 bytes"
  else
    .ok {
      version := version,
      name := name,
      kdfSalt := kdfSalt,
      kdfIters := kdfIters,
      aeadNonce := aeadNonce,
      ciphertext := ciphertext,
      derivationPath := derivationPath,
      address := address,
      createdAt := createdAt
    }

private def deriveKey (passphrase : String) (salt : ByteArray) (iters : Nat) :
    IO (Except String ByteArray) :=
  LeanKohaku.Crypto.Hacl.pbkdf2HmacSha512IO
    (LeanKohaku.Crypto.Hex.encode passphrase.toByteArray)
    (LeanKohaku.Crypto.Hex.encode salt)
    iters
    32

private def aad (name derivationPath address : String) : ByteArray :=
  (name ++ "\n" ++ derivationPath ++ "\n" ++ address).toByteArray

def makeRecord (name passphrase : String) (seed : ByteArray)
    (derivationPath address : String) : IO (Except String Record) := do
  let salt ← LeanKohaku.Crypto.Random.getRandomBytes 16
  let nonce ← LeanKohaku.Crypto.Random.getRandomBytes 12
  let key ← deriveKey passphrase salt defaultKdfIters
  match key with
  | .error err => pure (.error err)
  | .ok keyBytes =>
      let sealed ← LeanKohaku.Crypto.Hacl.chacha20Poly1305SealIO
        (LeanKohaku.Crypto.Hex.encode keyBytes)
        (LeanKohaku.Crypto.Hex.encode nonce)
        (LeanKohaku.Crypto.Hex.encode (aad name derivationPath address))
        (LeanKohaku.Crypto.Hex.encode seed)
      match sealed with
      | .error err => pure (.error err)
      | .ok ciphertext =>
          pure <| .ok {
            version := 1,
            name := name,
            kdfSalt := salt,
            kdfIters := defaultKdfIters,
            aeadNonce := nonce,
            ciphertext := ciphertext,
            derivationPath := derivationPath,
            address := address,
            createdAt := ← IO.monoMsNow
          }

def save (record : Record) : IO Unit := do
  ensureStoreDir
  let path ← slotPath record.name
  IO.FS.writeFile path (compact record.toJson ++ "\n")
  IO.setAccessRights path fileMode

def saveEncryptedSeed (name passphrase : String) (seed : ByteArray)
    (derivationPath address : String) : IO (Except String Record) := do
  match ← makeRecord name passphrase seed derivationPath address with
  | .error err => pure (.error err)
  | .ok record =>
      save record
      pure (.ok record)

def load (name : String) : IO (Except String Record) := do
  try
    let text ← IO.FS.readFile (← slotPath name)
    match parse text with
    | .error err => pure (.error err)
    | .ok json => pure (Record.fromJson json)
  catch e =>
    pure (.error e.toString)

def unlockSeedIO (record : Record) (passphrase : String) : IO (Except String ByteArray) := do
  let key ← deriveKey passphrase record.kdfSalt record.kdfIters
  match key with
  | .error err => pure (.error err)
  | .ok keyBytes =>
      LeanKohaku.Crypto.Hacl.chacha20Poly1305OpenIO
        (LeanKohaku.Crypto.Hex.encode keyBytes)
        (LeanKohaku.Crypto.Hex.encode record.aeadNonce)
        (LeanKohaku.Crypto.Hex.encode (aad record.name record.derivationPath record.address))
        (LeanKohaku.Crypto.Hex.encode record.ciphertext)

def list : IO (List String) := do
  let dir ← storeDir
  if !(← dir.pathExists) then
    pure []
  else
    let entries ← dir.readDir
    pure <| entries.toList.filterMap fun ent =>
      let fileName := ent.fileName
      if fileName.endsWith ".json" then
        some ((fileName.dropEnd 5).toString)
      else
        none

def delete (name : String) : IO Unit := do
  IO.FS.removeFile (← slotPath name)

end LeanKohaku.Wallet.EoaStore
