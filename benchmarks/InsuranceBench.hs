{-# LANGUAGE BangPatterns,
             DataKinds,
             FlexibleContexts,
             TemplateHaskell #-}
import Criterion.Main
import qualified Data.Foldable as F
import Data.Functor.Identity
import Frames
import Lens.Family
import qualified Pipes as P
import qualified Pipes.Prelude as P

csv :: FilePath
csv = "data/FL2.csv"

tableTypes "Ins" "data/FL2.csv"

type TinyIns = Rec [PolicyID, PointLatitude, PointLongitude]

tblP :: P.Producer Ins IO ()
tblP = readTable csv

-- Strict pair
data P a = P !a !a

-- | Perform two consecutive folds of streamed-in data.
pipeBench :: IO (P Double)
pipeBench = do (n,sumLat) <-
                 P.fold (\ !(!i, !s) r -> (i+1, s+rget pointLatitude r))
                        (0::Int,0)
                        id
                        tbl
               sumLong <- P.fold (\s r -> (s + rget pointLongitude r)) 0 id tbl
               return $! P (sumLat / fromIntegral n) (sumLong / fromIntegral n)
  where tbl = P.for tblP (P.yield . rcast) :: P.Producer TinyIns IO ()

-- | Perform two consecutive folds after first streaming all data into
-- an in-memory representation.
pipeBenchInCore :: IO (P Double)
pipeBenchInCore =
  do tbl <- inCore tblP :: IO (P.Producer Ins Identity ())
     let Identity (n,sumLat) =
           P.fold (\ !(!i, !s) r -> (i+1, s+rget pointLatitude r))
                  (0::Int,0)
                  id
                  tbl
         Identity sumLong =
           P.fold (\s r -> (s + rget pointLongitude r)) 0 id tbl
     return $! P (sumLat / fromIntegral n) (sumLong / fromIntegral n)

-- | Perform two consecutive folds after first projecting a subset of
-- fields while streaming data into an in-memory representation.
pipeBenchInCore' :: IO (P Double)
pipeBenchInCore' =
  do tbl <- inCore $ P.for tblP (P.yield . rcast)
         :: IO (P.Producer TinyIns Identity ())
     let Identity (n,sumLat) =
           P.fold (\ !(!i, !s) r -> (i+1, s+rget pointLatitude r))
                  (0::Int,0)
                  id
                  tbl
         Identity sumLong =
           P.fold (\s r -> (s + rget pointLongitude r)) 0 id tbl
     return $! P (sumLat / fromIntegral n) (sumLong / fromIntegral n)

-- | Perform two consecutive folds after projecting a subset of an
-- in-memory reprsentation.
pipeBenchAoS :: IO (P Double)
pipeBenchAoS = do tbl <- inCoreAoS' rcast tblP :: IO (Frame TinyIns)
                  let (n,sumLat) =
                        F.foldl' (\ !(!i,!s) r -> (i+1, s+rget pointLatitude r))
                                 (0::Int,0)
                                 tbl
                      sumLong =
                        F.foldl' (\ !s r -> (s + rget pointLongitude r)) 0 tbl
                  return $! P (sumLat / fromIntegral n) (sumLong / fromIntegral n)

main :: IO ()
main = defaultMain [ bench "pipes" $ whnfIO pipeBench
                   , bench "pipes in-core" $ whnfIO pipeBenchInCore
                   , bench "pipes in-core subset" $ whnfIO pipeBenchInCore'
                   , bench "pipes AoS" $ whnfIO pipeBenchAoS ]
