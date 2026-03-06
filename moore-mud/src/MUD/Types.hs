module MUD.Types
  ( PlayerId (..),
  )
where

newtype PlayerId = PlayerId {getPlayerId :: Int}
  deriving (Show, Eq, Ord)
