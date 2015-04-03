{-# LANGUAGE TemplateHaskell #-}

module Data.Aencode
    ( BDict
    , BValue(..)
    , asString
    , asInt
    , asList
    , asDict
  --
    , parseBValue
    , parseBString
    , parseBInt
    , parseBList
    , parseBDict
  --
    , Stringable(..)
    , buildBValue
    , buildBString
    , buildBInt
    , buildBList
    , buildBDict
  --
    , IBuilder
    , prefix
    , prefixed
    ) where

import           Control.Applicative
import           Control.Monad
import           Data.Attoparsec.ByteString
import           Data.Attoparsec.ByteString.Char8 (char, decimal, signed)
import qualified Data.Attoparsec.ByteString.Lazy as A
import qualified Data.ByteString as B
import           Data.ByteString.Builder
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as L
import qualified Data.ByteString.Lazy.Char8 as LC
import           Data.Function
import           Data.Monoid
import qualified Data.Map.Strict as M
import           Data.Wordplay
import           Prelude hiding (take)

type BDict a = M.Map a (BValue a)

-- A bencoded value.
data BValue a = BString a
              | BInt Integer
              | BList [BValue a]
              | BDict (BDict a)
              deriving Show

instance Functor BValue where
    fmap f (BString x) = BString $ f x
    fmap f (BList   x) = BList $ (fmap.fmap) f x
    fmap f (BDict   x) = BDict . (fmap.fmap) f $ mapKeys f x
    fmap _ i = i

asString :: BValue a -> Maybe a
asString (BString x) = Just x
asString _ = Nothing

asInt :: BValue a -> Maybe Int
asInt (BInt x) = Just x
asInt _ = Nothing

asList :: BValue a -> Maybe [BValue a]
asList (BList x) = Just x
asList _ = Nothing

asDict :: BValue a -> Maybe (BDict a)
asDict (BDict x) = Just x
asDict _ = Nothing

----------------------------------------
-- PARSERS
----------------------------------------

-- Parse a Bencoded value
parseBValue :: Parser (BValue B.ByteString)
parseBValue =  BString <$> parseBString
           <|> BInt    <$> parseBInt
           <|> BList   <$> parseBList
           <|> BDict   <$> parseBDict

parseBString :: Parser B.ByteString
parseBString = decimal <* char ':' >>= take

parseBInt :: Parser Integer
parseBInt = char 'i' *> signed decimal <* char 'e'

parseBList :: Parser [BValue B.ByteString]
parseBList = char 'l' *> many' parseBValue <* char 'e'

parseBDict :: Parser (BDict B.ByteString)
parseBDict = char 'd' *> inner <* char 'e'
  where
    inner = do
        pairs <- many' $ (,) <$> parseBString <*> parseBValue
        if sorted pairs
         then return (M.fromAscList pairs)
         else empty
    sorted x@(_:y) = all (== LT) $ zipWith (compare `on` fst) x y
    sorted _ = True

----------------------------------------
-- BUILDERS
----------------------------------------

buildBValue :: Stringable a => BValue a -> Builder
buildBValue (BString x) = buildBString x
buildBValue (BInt    x) = buildBInt    x
buildBValue (BList   x) = buildBList   x
buildBValue (BDict   x) = buildBDict   x

buildBString :: Stringable a => a -> Builder
buildBString x = intDec (lengthify x) <> char8 ':' <> builder a

buildBInt :: Integer -> Builder
buildBInt = surround 'i' . integerDec

buildBList :: Stringable a => [BValue a] -> Builder
buildBList = surround 'l' . mconcat . map buildBValue

buildBDict :: Stringable a => BDict a -> Builder
buildBDict x = surround 'd' $ mconcat [ buildBString k <> (foldMap f) v
                                      | (k, v) <- M.toAscList x
                                      ]

surround :: Stringable => Char -> a -> a
surround = (.) (<> char8' 'e') . mappend . char8'

----------------------------------------
-- STRINGABLE
----------------------------------------

class Stringable a where
    lengthify :: a -> Int
    builder :: a -> Builder

instance Stringable B.ByteString where
    lengthify = B.length
    builder = byteString

instance Stringable L.ByteString where
    lengthify = L.length
    builder = lazyByteString

type IBuilder = (Sum Int, Builder)

instance Stringable IBuilder where
    lengthify = fst
    builder = snd

----------------------------------------
-- USEFUL FOR IBUILDERS
----------------------------------------

prefix :: Stringable a => a -> IBuilder
prefix a = (Sum (lengthify a), builder a)

prefixed :: FiniteBits a -> (a -> Builder) -> IBuilder
prefixed f a = (finiteByteSize a, f a)

finiteByteSize :: FiniteBits a => a -> Int
finiteByteSize _ = case r of 0 -> q
                             _ -> q + 1
  where
    (q, r) = finiteBitSize (undefined :: a) `quotRem` 8

