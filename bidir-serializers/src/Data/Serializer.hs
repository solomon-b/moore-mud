module Data.Serializer
  ( Serializer (..),
    TextSerializer,
    prefix,
  )
where

--------------------------------------------------------------------------------

import Data.Bifunctor.Monoidal (Semigroupal (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.These (These (..))

--------------------------------------------------------------------------------

-- | A bidirectional serializer between \"server\" I\/O and \"bot\" I\/O.
--
-- @so@ = server output (what the server gives us, e.g. raw text)
-- @si@ = server input (what we give the server, e.g. formatted text)
-- @bo@ = bot output (typed observation from the world)
-- @bi@ = bot input (typed command to the world)
data Serializer so si bo bi = Serializer
  { parser :: so -> Maybe bi,
    printer :: bo -> si
  }

-- | A 'Serializer' specialized to 'Text' on both server sides.
type TextSerializer = Serializer Text Text

--------------------------------------------------------------------------------

-- | Product on printer (both subsystems always observe),
-- 'These' on parser (a command targets one or both subsystems).
instance Semigroupal (->) (,) These (,) TextSerializer where
  combine :: (TextSerializer bo bi, TextSerializer bo' bi') -> TextSerializer (bo, bo') (These bi bi')
  combine (Serializer p1 pr1, Serializer p2 pr2) =
    Serializer
      { parser = \txt -> case (p1 txt, p2 txt) of
          (Just a, Just b) -> Just (These a b)
          (Just a, Nothing) -> Just (This a)
          (Nothing, Just b) -> Just (That b)
          (Nothing, Nothing) -> Nothing,
        printer = \(bo, bo') ->
          let t1 = pr1 bo
              t2 = pr2 bo'
           in case (Text.null t1, Text.null t2) of
                (True, _) -> t2
                (_, True) -> t1
                _ -> t1 <> "\n" <> t2
      }

--------------------------------------------------------------------------------

-- | Extend the parser to require a prefix keyword.
--
-- @prefix \"say\" ser@ matches input starting with @\"say \"@ and passes
-- the remainder to @ser@'s parser.
prefix :: Text -> TextSerializer bo bi -> TextSerializer bo bi
prefix pfx (Serializer p pr) =
  Serializer
    { parser = \txt ->
        case Text.stripPrefix pfx txt of
          Just rest -> p (Text.stripStart rest)
          Nothing -> Nothing,
      printer = pr
    }
