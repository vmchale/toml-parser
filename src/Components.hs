{-|
Module      : Components
Description : /Internal:/ Type and operations for raw top-level TOML elements
Copyright   : (c) Eric Mertens, 2017
License     : ISC
Maintainer  : emertens@gmail.com

This module provides an intermediate representation for TOML files.
The parser produces a list of top-level table components, and this
module gathers those together in the form of tables and lists of
tables.

-}
module Components where

import           Control.Monad
import           Data.Foldable
import           Data.List
import           Data.Maybe
import           Data.Ord
import           Data.Text (Text)
import qualified Data.Text as Text

import Value

-- | Various top-level elements that can be returned by the TOML parser.
data Component
  = InitialEntry    [(Text,Value)] -- ^ key value pairs before any @[header]@
  | TableEntry Path [(Text,Value)] -- ^ key value pairs after any @[header]@
  | ArrayEntry Path [(Text,Value)] -- ^ key value pairs after any @[[header]]@
  deriving (Read, Show)

-- | Non-empty list of table keys
type Path = [Text]


-- | Merge a list of top-level components into a single
-- table, or throw an error with an ambiguous path.
componentsToTable :: [Component] -> Either Path [(Text,Value)]
componentsToTable = flattenTableList . collapseComponents


-- | Collapse the various components generated by the parser into a
-- single list of path-value pairs. This operations is particularly
-- responsible for gathering top-level array entries together.
collapseComponents :: [Component] -> [(Path,Value)]
collapseComponents [] = []
collapseComponents (InitialEntry kvs : xs) =
  [ ([k],v) | (k,v) <- kvs ] ++ collapseComponents xs
collapseComponents (TableEntry k kvs : xs) =
  (k, Table kvs) : collapseComponents xs
collapseComponents xs@(ArrayEntry k _ : _) =
  case splitArrays k xs of
    (kvss, xs') -> (k, List (map Table kvss)) : collapseComponents xs'


-- | Extract all of the leading 'ArrayEntry' components that match
-- the given path.
splitArrays :: Path -> [Component] -> ([[(Text,Value)]], [Component])
splitArrays k1 (ArrayEntry k2 kvs : xs)
  | k1 == k2 =
     case splitArrays k1 xs of
       (kvss, xs2) -> (kvs:kvss, xs2)
splitArrays _ xs = ([],xs)


-- | Given a list of key-value pairs ordered by key, group the list
-- by equality on the head of the key-path list.
factorHeads :: Eq k => [([k],v)] -> [(k,[([k],v)])]
factorHeads xs = [ (h, [ (k, v) | (_:k,v) <- g ])
                 | let eq (x,_) (y,_) = take 1 x == take 1 y
                 , g@((h:_,_):_) <- groupBy eq xs
                 ]


-- | Flatten a list of path-value pairs into a single table.
-- If in the course of flattening the pairs if the value at a
-- particular path is assigned twice, that path will be returned
-- instead.
flattenTableList :: [(Path, Value)] -> Either Path [(Text, Value)]
flattenTableList = go [] . order
  where
    go path xs = sequenceA [ flattenGroup path x ys | (x,ys) <- factorHeads xs ]

    flattenGroup :: Path -> Text -> [(Path,Value)] -> Either Path (Text,Value)
    flattenGroup path k (([],Table t):kvs) =
      flattenGroup path k (mergeInlineTable t kvs)
    flattenGroup path k (([],v):rest)
      | null rest = (k,v) <$ validateInlineTables (k:path) v
      | otherwise = Left (reverse (k:path))
    flattenGroup path k kvs =
      do kvs' <- go (k:path) kvs
         return (k, Table kvs')


-- | Merge a table into the current list of path-value pairs. The
-- resulting list is sorted to make it appropriate for subsequent
-- grouping operations.
mergeInlineTable :: [(Text,value)] -> [(Path,value)] -> [(Path,value)]
mergeInlineTable t kvs = order ([([i],j) | (i,j) <- t] ++ kvs)


-- | Order a list of path-value pairs lexicographically by path.
order :: [(Path,value)] -> [(Path,value)]
order = sortBy (comparing fst)


-- | Throw an error with the problematic path if a duplicate is found.
validateInlineTables :: Path -> Value -> Either Path ()
validateInlineTables path (Table t) =
  case findDuplicate (map fst t) of
    Just k  -> Left (reverse (k:path))
    Nothing -> traverse_ (\(k,v) -> validateInlineTables (k:path) v) t
validateInlineTables path (List xs) =
  zipWithM_ (\i x -> validateInlineTables (Text.pack (show i):path) x)
        [0::Int ..] xs
validateInlineTables _ _ = Right ()


-- | Find an entry that appears in the given list more than once.
findDuplicate :: Ord a => [a] -> Maybe a
findDuplicate = listToMaybe . map head . filter (not . null . tail) . group . sort
