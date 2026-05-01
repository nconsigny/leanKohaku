/-!
# Unix-domain socket FFI

Linux-only AF_UNIX stream socket bindings shared by the thin CLI client and
the daemon. The native side sets socket mode `0600`; the daemon additionally
enforces same-uid peer checks before dispatch.
-/

namespace LeanKohaku.Transport.Uds

structure Listener where
  fd : UInt32
  deriving Repr

structure Conn where
  fd : UInt32
  deriving Repr

structure PeerCred where
  uid : UInt32
  deriving Repr, DecidableEq

@[extern "lk_uds_bind"]
opaque bindRaw (path : @& String) : IO UInt32

@[extern "lk_uds_accept"]
opaque acceptRaw (fd : UInt32) : IO UInt32

@[extern "lk_uds_connect"]
opaque connectRaw (path : @& String) : IO UInt32

@[extern "lk_uds_read"]
opaque readRaw (fd maxBytes : UInt32) : IO ByteArray

@[extern "lk_uds_write"]
opaque writeRaw (fd : UInt32) (bytes : @& ByteArray) : IO UInt32

@[extern "lk_uds_close"]
opaque closeRaw (fd : UInt32) : IO Unit

@[extern "lk_uds_shutdown"]
opaque shutdownRaw (fd : UInt32) : IO Unit

@[extern "lk_uds_peer_uid"]
opaque peerUidRaw (fd : UInt32) : IO UInt32

@[extern "lk_uds_current_uid"]
opaque currentUid : IO UInt32

def bind (path : String) : IO Listener := do
  let fd ← bindRaw path
  pure { fd := fd }

def accept (listener : Listener) : IO Conn := do
  let fd ← acceptRaw listener.fd
  pure { fd := fd }

def connect (path : String) : IO Conn := do
  let fd ← connectRaw path
  pure { fd := fd }

def read (conn : Conn) (maxBytes : UInt32 := 65536) : IO ByteArray :=
  readRaw conn.fd maxBytes

def write (conn : Conn) (bytes : ByteArray) : IO UInt32 :=
  writeRaw conn.fd bytes

def close (conn : Conn) : IO Unit :=
  closeRaw conn.fd

def closeListener (listener : Listener) : IO Unit :=
  closeRaw listener.fd

def shutdown (conn : Conn) : IO Unit :=
  shutdownRaw conn.fd

def peerCred (conn : Conn) : IO PeerCred := do
  let uid ← peerUidRaw conn.fd
  pure { uid := uid }

def peerUidMatchesCurrent (conn : Conn) : IO Bool := do
  let peer ← peerCred conn
  let uid ← currentUid
  pure (peer.uid == uid)

end LeanKohaku.Transport.Uds
