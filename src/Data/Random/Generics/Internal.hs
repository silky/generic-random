{-# LANGUAGE RecordWildCards #-}
module Data.Random.Generics.Internal where

import Control.Monad.State
import Control.Monad.Trans.Maybe
import Data.Data
import Data.Random.Generics.Boltzmann.Oracle

-- * Helper functions

makeGenerator :: (Data a, Monad m)
  => PrimRandom m -> proxy a -> Int -> Int -> m a
makeGenerator primRandom a k size =
  getGenerator dd generators a k
  where
    dd = iterate point (collectTypes (undefined `asProxyTypeOf` a)) !! (k + 1)
    -- We need the next pointing to capture the average size in an equation.
    t = typeRep a
    oracle = makeOracle dd t size
    generators = makeGenerators dd oracle primRandom

ceiledRejectionSampler
  :: (Data a, Monad m) => PrimRandom m
  -> proxy a -> Int -> Int -> Maybe (Int, Int) -> m a
ceiledRejectionSampler primRandom a k size Nothing =
  makeGenerator primRandom a k size
ceiledRejectionSampler primRandom a k size (Just (minSize, maxSize)) =
  runRejectT' (makeGenerator primRandom' a k size)
  where
    primRandom' = ceilPrimRandom maxSize primRandom
    runRejectT' = runRejectT minSize

epsilon :: Double
epsilon = 0.1

tolerance :: Double -> Int -> (Int, Int)
tolerance epsilon size = (size - delta, size + delta)
  where
    delta = floor (fromIntegral size * epsilon)

type RejectT m = StateT Int (MaybeT m)

-- | Set upper bound
ceilPrimRandom
  :: Monad m => Int -> PrimRandom m
  -> PrimRandom (RejectT m)
ceilPrimRandom maxSize pr = ((liftPrimRandom . liftPrimRandom) pr)
  { incr = do
      size <- get
      guard (size < maxSize)
      put (size + 1)
  }

-- | Set lower bound
runRejectT :: Monad m => Int -> RejectT m a -> m a
runRejectT minSize m = fix $ \go -> do
  x' <- runMaybeT (m `runStateT` 0)
  case x' of
    Just (x, size) | size >= minSize -> return x
    _ -> go

liftPrimRandom
  :: (MonadTrans t, Monad m) => PrimRandom m -> PrimRandom (t m)
liftPrimRandom PrimRandom{..} = PrimRandom
  (lift incr)
  (fmap lift getRandomR_)
  (lift int)
  (lift double)
  (lift char)

asProxyTypeOf :: a -> proxy a -> a
asProxyTypeOf = const
