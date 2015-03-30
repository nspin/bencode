{-# LANGUAGE TemplateHaskell #-}

module Curry.Parsers.Bencode
    (
  --
    BValue(..)
    BDict
    ToBencode
    FromBencode
  --
    , _BString
    , _BInt
    , _BList
    , _BDict
  --
    , parseBValue
    , parseBString
    , parseBInt
    , parseBList
    , parseBDict
  --
    , writeBValue
    , writeBString
    , writeBInt
    , writeBList
    , writeBDict
  --
    ) where

import           Control.Applicative
import           Control.Lens
import           Control.Monad
import           Data.Attoparsec.ByteString
import           Data.Attoparsec.ByteString.Char8 (char, decimal, signed)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as C
import           Data.Function
import qualified Data.Map as M
import           Prelude hiding (take)

-- A bencoded value.
data BValue = BString B.ByteString
            | BInt Integer
            | BList [BValue]
            | BDict BDict
            deriving Show

type BDict = M.Map B.ByteString BValue

class ToBencode a where
    encode :: a -> BValue

class FromBencode a where
    encode :: BValue -> Maybe a

----------------------------------------
-- PARSERS
----------------------------------------

-- Parse a Bencoded value
parseBValue :: Parser BValue
parseBValue =  BString <$> parseBString
           <|> BInt    <$> parseBInt
           <|> BList   <$> parseBList
           <|> BDict   <$> parseBDict

parseBString :: Parser B.ByteString
parseBString = decimal <* char ':' >>= take

parseBInt :: Parser Integer
parseBInt = char 'i' *> signed decimal <* char 'e'

parseBList :: Parser [BValue]
parseBList = char 'l' *> many' parseBValue <* char 'e'

parseBDict :: Parser BDict
parseBDict = char 'd' *> inner <* char 'e'

inner = do
    pairs <- many' $ liftA2 (,) parseBString parseBValue
    if sorted pairs
     then return (M.fromAscList pairs)
     else empty

sorted :: Ord a => [(a, b)] -> Bool
sorted x@(_:y) = all (== LT) $ zipWith (compare `on` fst) x y
sorted _ = True

----------------------------------------
-- WRITERS
----------------------------------------

writeBValue :: BValue -> B.ByteString
writeBValue (BString x) = writeBString x
writeBValue (BInt    x) = writeBInt    x
writeBValue (BList   x) = writeBList   x
writeBValue (BDict   x) = writeBDict   x

writeBString :: B.ByteString -> B.ByteString
writeBString s = C.pack (show (B.length s) ++ ":") `B.append` s

writeBInt :: Integer -> B.ByteString
writeBInt = surround 'i' . C.pack . show

writeBList :: [BValue] -> B.ByteString
writeBList = surround 'l' . B.concat . map writeBValue

writeBDict :: BDict -> B.ByteString
writeBDict = surround 'd'
           . B.concat
           . map (\(k, v) -> writeBString k `B.append` writeBValue v)
           . M.toAscList

surround :: Char -> B.ByteString -> B.ByteString
surround = (.) (`C.snoc` 'e') . C.cons

----------------------------------------
-- TEMPLATE HASKELL
----------------------------------------

makePrisms ''BValue
