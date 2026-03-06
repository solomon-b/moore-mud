-- | Chat subsystem — a pure Moore coalgebra.
--
-- State is a bounded message log. Input is a chat command (say,
-- whisper, shout). Output is the list of messages produced this step.
-- Spatial filtering (say = same room, shout = global) is handled by
-- the wiring diagram, not here.
module MUD.World.Chat
  ( -- * Types
    PlayerId,
    ChatState (..),
    ChatCmd (..),
    ChatMsg (..),
    ChatOutput (..),

    -- * Coalgebra
    chatMachine,

    -- * Initial state
    initialChatState,
  )
where

--------------------------------------------------------------------------------

import Data.Functor.Identity (Identity (..))
import Data.Machine.FRP.Core (MooreC, MooreTC (..))
import Data.Text (Text)

--------------------------------------------------------------------------------

-- | Opaque player identifier.
type PlayerId = Int

-- | A chat message with its origin and content.
data ChatMsg
  = SayMsg PlayerId Text
  | -- | sender, recipient, content
    WhisperMsg PlayerId PlayerId Text
  | ShoutMsg PlayerId Text
  deriving (Show, Eq)

-- | Chat subsystem state: a bounded log of recent messages.
data ChatState = ChatState
  { chatLog :: [ChatMsg],
    chatLogMax :: Int
  }
  deriving (Show, Eq)

-- | Chat commands.
data ChatCmd
  = Say PlayerId Text
  | -- | sender, recipient, content
    Whisper PlayerId PlayerId Text
  | Shout PlayerId Text
  deriving (Show, Eq)

-- | Chat output: messages produced this step.
newtype ChatOutput = ChatOutput {chatMessages :: [ChatMsg]}
  deriving (Show, Eq)

--------------------------------------------------------------------------------

-- | Initial chat state with an empty log.
initialChatState :: ChatState
initialChatState = ChatState {chatLog = [], chatLogMax = 100}

-- | The chat Moore coalgebra.
--
-- Observation: all messages currently in the log.
-- Transition: append the new message and trim to the max size.
chatMachine :: MooreC ChatState ChatCmd ChatOutput
chatMachine = MooreTC $ \s ->
  Identity
    ( ChatOutput (chatLog s),
      \cmd ->
        let msg = cmdToMsg cmd
            log' = take (chatLogMax s) (msg : chatLog s)
         in s {chatLog = log'}
    )

-- | Convert a command to a message.
cmdToMsg :: ChatCmd -> ChatMsg
cmdToMsg (Say pid txt) = SayMsg pid txt
cmdToMsg (Whisper from to txt) = WhisperMsg from to txt
cmdToMsg (Shout pid txt) = ShoutMsg pid txt
