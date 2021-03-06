module Language.Pepa.Rates
  ( -- * Types for rate representations
    Rate            ( .. )
  , ModelRate
  , RateValue
  , RateNumber
  , RateNumberClass ( .. )
  , RateWeight
  , defaultWeight
  , RateIdentifier
  , RateExpr        ( .. )

    -- * Arithmetic operations over rates
  , genRateBinop
  , scaleRate
  , (*.)
  , (+.)
  , (/.)
  , sumRates
  , sumModelRates
  , minRates
  , apparentRate
  , apparentRateExpr
  , rateExprIncr
  , rateExprDecr
  , rateExpressionInt

    -- * Rate evaluation and number extraction
  , rateNumber
  , reduceRate
  , reduceRateExpr
  , reduceRateExprWith
  , namesOfRateExpr

    -- * Rate transformations
  , modifyRate
  , renameRateExpr
  , remapRateExpr
  , transformRateExpr
  , normaliseRateExpr

  , topRate
  , namedRateExp
  , realRateExp
  , integerRateExp
  , andRateConditions
  , addRateExprs
  , sumRateExprs
  , subtractRateExprs
  , multiplyRateExprs
  , divideRateExprs


  , isTimedRate
  , isImmediateRate
  , isPassiveRate
  , isNonReducable
  , isIrreducible
  )
where

{- Standard Library Modules Imported -}
import Data.List
  ( union )
import qualified Data.Map as Map
import Data.Map 
  ( Map )
import qualified Data.Maybe as Maybe
{- External Library Modules Imported -}
{- Local Modules Imported -}
import Language.Pepa.QualifiedName
  ( QualifiedName
  , ShowOrig      ( .. )
  )
{- End of Module Imports -}

{-| The main data type exported here. The representation of a PEPA rate
    the actual timed rate representation is left as a type parameter.
    It may be an expression type when it is first parsed in but later
    when the model is evaluated and we have enough information to reduce
    that expression to a concrete value then parameterised type can be
    a value.
-}
data Rate a =
   RateTop a         -- ^ The special passive rate
 | RateImmediate a   -- ^ An immediate weight
 | RateTimed a       -- ^ A timed rate expression when parsed
                     -- this will be an expression but when
                     -- the state space is worked out this will
                     -- be a value (Double).
 deriving (Show, Read, Eq, Ord)

{-| The type of an immediate weight -}
type RateWeight        = Double

{-| The default weight of a passive or immediate action -}
defaultWeight :: RateExpr
defaultWeight = Creal 1.0

{-|
  So a rate within a model is a Rate RateExpr because some of the rates
  may be expressions which we cannot yet fully reduce because they are
  functional rates for which we require the full state space to reduce.
-}
type ModelRate = Rate RateExpr

-- | The type associated with rate names
type RateIdentifier    = QualifiedName

{-| 
   However a transition rate, that is a rate used during state space
   generation can only have the rate part filled in by an actual rate
   value. This is because at this point we know the full configuration
   of the state we are transitioning from and are hence in a position to
   fully reduce any rate.
-}
type RateValue = Rate RateNumber

{-| A 'RateNumber' on the other than is the actual representation of the
    numbers held within a rate representation.
-}
type RateNumber = Double

{-| While in general a rate value is a double, we also use rate expressions
    for other purposes such as array concentrations and initial populations.
    Therefore it is nice to be able to reduce a rate expression to an
    integer rather than a double.
-}
class (Num a, Ord a) => RateNumberClass a where
  rnFromDouble   :: Double -> a
  rnToDouble     :: a -> Double
  rnFromIntegral :: Integral b => b -> a
  rnDivide       :: a -> a -> a


instance RateNumberClass Double where
  rnFromDouble   = id
  rnToDouble     = id
  rnFromIntegral = fromIntegral
  rnDivide       = (/)


instance RateNumberClass Int where
  rnFromDouble   = round
  rnToDouble     = fromIntegral
  rnFromIntegral = fromIntegral
  rnDivide       = div

{-| 
   The type of rate expressions used in PEPA model files is essentially
   a subset of C expressions. This data type is a little bit of a superset
   of the set of rates which may be parsed by the PEPA parser since we also
   use this representation for other model description files such as
   hydra and prism.
   [@todo@] consider using the C library from the gtk2hs project

   Note we derive the equality and ordering classes, of course this
   isn't really correct. We're not saying that we can do any meaningful
   equality check on expressions, eg @(4 * 3)@ will be different to @(3 * 4)@
   but could conceivably be seen to be the same expression.
   These though are actually there to allow us to derive the ordering class
   which is needed in the probe translation for state machines. There it doesn't
   matter if the ordering is meaningful in any sense.
-}
data RateExpr =
   Cident RateIdentifier            -- ^ Variable access
 | Cconstant Int                    -- ^ Represents a C integer constant
 | Creal Double                     -- ^ Represents a C real constant
 | Cadd  RateExpr RateExpr          -- ^ Addition
 | Csub  RateExpr RateExpr          -- ^ Subtraction
 | Cmult RateExpr RateExpr          -- ^ Multiplication
 | Cdiv  RateExpr RateExpr          -- ^ Division
 | Cifte RateExpr RateExpr RateExpr -- ^ C-style if then else *expression*
 | Cand RateExpr RateExpr           -- ^ anded boolean expression
 | Cor  RateExpr RateExpr           -- ^ or'ed boolean expression
 | Cgt  RateExpr RateExpr           -- ^ greater than
 | Cge  RateExpr RateExpr           -- ^ greater than or equal to
 | Clt  RateExpr RateExpr           -- ^ less than
 | Cle  RateExpr RateExpr           -- ^ less than or equal to
 | Ceq  RateExpr RateExpr           -- ^ equal to
 | Cnot RateExpr                    -- ^ boolean negation
   {- These last three are really all legacy, well maybe not so much minimum -}
 | Cminimum RateExpr RateExpr       -- ^ Take the minimum of two values
   -- | The apparent rate function apply to the two rates plus the
   -- two rate divisors. Note do NOT apply this if one of but not both
   -- of the rates are passive.
 {-
 | CAppRate RateExpr RateExpr 
            RateExpr RateExpr
   -- | Some apparent rates are active vs passive if this is the case
   -- then there is no need for a minimum, in fact it is WRONG to apply
   -- the above, we must do more or less the same calculation but the
   -- minimum is just deemed to be the left (or first) hand side.
 | CActPass RateExpr RateExpr 
            RateExpr RateExpr
 -}
 deriving (Eq, Ord, Show, Read)



{-|
   Multiply a rate by a rate scalar
-}
scaleRate :: RateNumberClass a => a -> Rate a -> Rate a
scaleRate k (RateTimed d)     = RateTimed $ d * k
-- Actually not entirely sure how we should scale immediate rates.
scaleRate k (RateImmediate m) = RateImmediate $ m * k
scaleRate k (RateTop i)       = RateTop $ i * k


{-|
   Okay so again I don't really know how a binary operator should work on
   an immediate rate so I have currently left the weight undefined if we ever
   actually try to evaluate it then I guess I will know what we should be doing.
   Also note that we can only use this in the case that the binop doesn't make
   sense for mixed rate kinds. For example we cannot use it for 'minRates' since
   we want minRate (RateTimed r1) (RateTop m) = RateTimed r1

   We wish to maintain the following properties:
   mT + nT = (m + n)T : for all m,n in Rationals
   (mT/nT) = (m/n)    : for all m,n in Rationals
  
   'minRates' also defines the properties we require of 'minRates' such that it
   isn't defined by 'rateBinop'

   The reason for the separate 'rateBinop' and 'genRateBinop' functions is
   historical and a result of RateTop previously not taking a whole expression
   argument.
-}
rateBinop :: RateNumberClass a => (a -> a -> a) -> Rate a -> Rate a -> Rate a
rateBinop = genRateBinop

{-|
  The same as rateBinop but for general rates rather than necessarily those filled in
  with a number.
  This shouldn't really require 'Show' it is just there for giving an error message
  that should never actually occur.
-}
genRateBinop :: Show a => (a -> a -> a) -> Rate a -> Rate a -> Rate a
genRateBinop _bin1 (RateImmediate _) (RateImmediate _) = 
  RateImmediate undefined
genRateBinop bin1  (RateTimed r1)    (RateTimed r2)    = 
  RateTimed $ bin1 r1 r2
genRateBinop bin1  (RateTop n)       (RateTop m)       = 
  RateTop $ bin1 n m
genRateBinop _bin1 (RateImmediate _) _                 = 
  error "Mixing immediate and timed rates"
genRateBinop _bin1 _                 (RateImmediate _) =
  error "Mixing immediate and timed rates"
genRateBinop _bin1 left              right             =
  error $ unlines [ "Mixing passive and active rates over an undefined operator"
                  , show left
                  , show right
                  ]

{-| Multiply two rate values -}
(*.) :: RateNumberClass a => Rate a -> Rate a -> Rate a
(*.) = rateBinop (*)

{-| Add together two rate values -}
(+.) :: RateNumberClass a => Rate a -> Rate a -> Rate a
(+.) = rateBinop (+)

{- Divide one rate value by another -}
(/.) :: RateNumberClass a => Rate a -> Rate a -> Rate a
(/.) = rateBinop rnDivide

{-|
   Sum together a list of rate values. Note that the list must not
   be empty. This is used primarily to sum the rates within an
   apparentRate calculation and can therefore not be an empty list.
-}
sumRates :: RateNumberClass a => [ Rate a ] -> Rate a
sumRates = foldl1 (+.)

{-| Sum a list of model rates -}
sumModelRates :: [ ModelRate ] -> ModelRate
sumModelRates rates
  | (length timed)   == number = RateTimed $ foldr1 Cadd timed
  | (length passive) == number = RateTop   $ foldr1 Cadd passive
  | (length imms)    == number = RateImmediate $ foldr1 Cadd imms
  | otherwise                  =
    error "Mixing passive/active or immediates"
  where
  number  = length rates
  timed   = [ t | RateTimed t <- rates ]
  passive = [ p | RateTop p <- rates ]
  imms    = [ i | RateImmediate i <- rates ]


{-|
   The minimum of two rates as defined in the apparent rate function.
   Hence we have the following properties:
   mT < nT            : for m < n and m,n in Rationals
   r < nT             : for all r in Reals and n in Rationals
-}
minRates :: RateValue -> RateValue -> RateValue
minRates (RateTimed r1)    (RateTimed r2)      = RateTimed $ min r1 r2
minRates (RateTop m)       (RateTop n)         = RateTop $ min m n
minRates (RateTimed r1)    (RateTop _)         = RateTimed r1
minRates (RateTop _)       (RateTimed r2)      = RateTimed r2
minRates (RateImmediate _) (RateImmediate _)   = 
  error "Taking the minimum of immediate rates"
minRates (RateImmediate _) _                   =
  error "Mixing immediate and timed rates"
minRates _                 (RateImmediate _)   =
  error "Mixing immediate and timed rates"


{-|  Calculate the apparent rate of two rates given the two rate
    and the sum of the competing rate sets of each activity.
    So if we're calculating the apparent rate of
    (a, r1).P < a > (a, r2).Q
    Then raP = the sum of all ways the left hand component can do
    an 'a' activity (in the current state) and similarly raQ is
    the sum of the rates of all ways the right hand component can do
    an 'a' activity. Then we call
    @apparentRate r1 r2 raP raQ@
-}
apparentRate :: RateValue -> RateValue -> RateValue -> RateValue -> RateValue
apparentRate (RateTimed r1) (RateTimed r2) 
             (RateTimed raP) (RateTimed raQ)          = 
  RateTimed $ (r1 / raP) * (r2 / raQ) * (min raP raQ)
apparentRate (RateTimed r1) (RateTop m)
             (RateTimed raP) (RateTop n)              =
  RateTimed $ (r1 / raP) * (m / n) * raP
apparentRate (RateTop m) (RateTimed r2)
             (RateTop n) (RateTimed raQ)              =
  RateTimed $ (m / n) * (r2 / raQ) * raQ
apparentRate (RateTop m1) (RateTop m2)
             (RateTop n1) (RateTop n2)                =
  RateTop $ (m1 / n1) * (m2 / n2) * (min n1 n2)
apparentRate (RateImmediate r1) (RateImmediate r2)    
             (RateImmediate _w) (RateImmediate _x)    =
  -- Please note I have no idea if this is the correct weighting
  -- it seems like it won't be. We want something similar to
  -- the timed appparent rate calculation.
  RateImmediate $ min r1 r2
apparentRate r1 r2 raP raQ                   =
  error $ unlines [ mixing
                  , "r1 = "  ++ show r1
                  , "r2 = "  ++ show r2
                  , "raP = " ++ show raP
                  , "raQ = " ++ show raQ
                  ]
  where
  mixing = "Mixing passive and active rates in apparent rate calculation"


apparentRateExpr :: ModelRate  -- ^ The left rate
                 -> ModelRate  -- ^ The right rate
                 -> ModelRate  -- ^ The left overall rate
                 -> ModelRate  -- ^ The right overall rate
                 -> ModelRate  -- ^ The result
apparentRateExpr (RateTimed r1) (RateTimed r2)
                 (RateTimed raP) (RateTimed raQ)       =
  RateTimed appRate 
  where 
  appRate  = (r1 `Cdiv` raP) `Cmult` 
             (r2 `Cdiv` raQ) `Cmult` (Cminimum raP raQ)
apparentRateExpr (RateTimed r1) (RateTop m)
                 (RateTimed raP) (RateTop n)           =
  RateTimed appRate
  where 
  appRate = (r1 `Cdiv` raP)  `Cmult` 
            (m `Cdiv` n)     `Cmult` raP
apparentRateExpr (RateTop m) (RateTimed r2)
                 (RateTop n) (RateTimed raQ)           =
  RateTimed appRate
  where
  appRate = (m `Cdiv` n)    `Cmult`
            (r2 `Cdiv` raQ) `Cmult` raQ
apparentRateExpr (RateTop m1) (RateTop m2)
                 (RateTop n1) (RateTop n2)             =
   RateTimed appRate
  where
  appRate = (m1 `Cdiv` n1) `Cmult`
            (m2 `Cdiv` n2) `Cmult` (Cminimum m2 n2) 
apparentRateExpr (RateImmediate r1) (RateImmediate r2)
                 (RateImmediate _w) (RateImmediate _x) =
  -- Please note I have no idea if this is the correct weighting
  -- it seems like it won't be. We want something similar to
  -- the timed appparent rate calculation.
  RateImmediate $ min r1 r2
apparentRateExpr r1 r2 raP raQ                         =
  error $ unlines [ mixing
                  , "r1 = "  ++ show r1
                  , "r2 = "  ++ show r2
                  , "raP = " ++ show raP
                  , "raQ = " ++ show raQ
                  ]
  where
  mixing = "Mixing passive and active rates in apparent rate calculation"



{-| Incrementing a rate expression. This is generally more useful when
    the "rate expression" is being used for a process concentration,
    for example in an array component. We take care to simple increment
    the number if the current expression is just a number but make up
    an expression in the case that it is already a complex one.
-}
rateExprIncr :: RateExpr -> RateExpr
rateExprIncr (Cconstant x) = Cconstant $ x + 1
rateExprIncr (Creal x)     = Creal $ x + 1.0
rateExprIncr expr          = Cadd (Cconstant 1) expr

{-| Equivalent to 'rateExprIncr' -}
rateExprDecr :: RateExpr -> RateExpr
rateExprDecr (Cconstant x) = Cconstant $ x - 1
rateExprDecr (Creal x)     = Creal $ x - 1.0
rateExprDecr expr          = Csub expr (Cconstant 1)

{-| Returns the number as an 'Int' which a rate expression represents.
    If the rate expression is a complex one then we error.
    This should only be called if the rate in question should already have
    been reduced to a number.
-}
rateExpressionInt :: RateExpr -> Int
rateExpressionInt (Cconstant x) = x
rateExpressionInt (Creal x)     = round x
rateExpressionInt r             = 
  -- We should of course use 'hprintRateExpr' but that requires it to be
  -- defined within here.
  error $ unwords [ "rateExpressionInt:"
                  , "Encountered a complex rate expression:"
                  , show r
                  ]

rateNumber :: RateValue -> RateNumber
rateNumber (RateTimed d)      = d
rateNumber (RateImmediate _)  = error "rateNumber: no double of immediate"
rateNumber (RateTop _)        = error "rateNumber: no double of top"


andRateConditions :: RateExpr -> RateExpr -> RateExpr
andRateConditions = Cand

addRateExprs :: RateExpr -> RateExpr -> RateExpr
addRateExprs = Cadd

sumRateExprs :: [ RateExpr ] -> RateExpr
sumRateExprs = foldr1 addRateExprs

subtractRateExprs :: RateExpr -> RateExpr -> RateExpr
subtractRateExprs = Csub

multiplyRateExprs :: RateExpr -> RateExpr -> RateExpr
multiplyRateExprs = Cmult

divideRateExprs :: RateExpr -> RateExpr -> RateExpr
divideRateExprs = Cdiv

type ValueMapping a = Map QualifiedName a

{-|
  The point of the two representations of model rates and rate values
  is that we should be able to reduce the model rates to rate values
  once we know the configuration of the rate. This function reduces
  a model rate to a rate value based on a mapping from names to
  rate numbers. Note that if a name used within an expression is
  not in the mapping then it is assumed to map to zero. This correponds
  for example in mapping a component states to concentrations where
  not being in the mapping means that it is zero.
-}
reduceRate :: RateNumberClass a => ValueMapping a -> ModelRate -> Rate a
reduceRate = modifyRate . reduceRateExpr


{-| Reduces a rate expression based on a mapping of names which 
    may occur within the rate expression to rate numbers.
    see 'reduceRate'
    In particular note that if a name is not found within the
    the mapping it is assumed to map to zero.
-}
reduceRateExpr :: RateNumberClass a => ValueMapping a -> RateExpr -> a
reduceRateExpr mapping = 
  -- So note here if we do not find the name in the mapping
  -- then we default to a rate of zero.
  reduceRateExprWith lookupRate
  where
  lookupRate p = Maybe.fromMaybe 0 $ Map.lookup p mapping



{-| Reduces a rate expression given a function mapping identifiers to
    numbers. A generalisation of 'reduceRateExpr'.
    TODO: Here we would like the ability to reduce the number to an
    integer for doing variable process array sizes.
-}
reduceRateExprWith :: RateNumberClass a => (RateIdentifier -> a) -> RateExpr -> a
reduceRateExprWith _m (Creal d)          = rnFromDouble d
reduceRateExprWith m  (Cident p)         = m p
reduceRateExprWith _m  (Cconstant i)     = rnFromIntegral i
reduceRateExprWith m  (Cadd left right)  =
   (reduceRateExprWith m left) +
   (reduceRateExprWith m right)
reduceRateExprWith m  (Csub left right)  =
   (reduceRateExprWith m left) -
   (reduceRateExprWith m right)
reduceRateExprWith m  (Cmult left right) =
   (reduceRateExprWith m left) *
   (reduceRateExprWith m right)
reduceRateExprWith m  (Cdiv left right)  =
   rnDivide (reduceRateExprWith m left)
            (reduceRateExprWith m right)
reduceRateExprWith m  (Cifte cond left right)
   | (reduceRateExprWith m cond) /= 0 = reduceRateExprWith m left
   | otherwise                       = reduceRateExprWith m right
reduceRateExprWith m  (Cand left right)
   | leftV /= 0 && rightV /= 0   = 1
   | otherwise                = 0
   where
   leftV  = (reduceRateExprWith m left)
   rightV = (reduceRateExprWith m right)
reduceRateExprWith m  (Cor left right)
   | leftV /= 0 || rightV /= 0 = 1
   | otherwise              = 0
   where
   leftV  = (reduceRateExprWith m left)
   rightV = (reduceRateExprWith m right)
reduceRateExprWith m  (Ceq left right)
   | leftV == rightV   = 1
   | otherwise        = 0
   where
   leftV  = (reduceRateExprWith m left)
   rightV = (reduceRateExprWith m right)
reduceRateExprWith m  (Cgt left right)
   | leftV > rightV   = 1
   | otherwise        = 0
   where
   leftV  = (reduceRateExprWith m left)
   rightV = (reduceRateExprWith m right)
reduceRateExprWith m  (Cge left right)
   | leftV >= rightV = 1
   | otherwise      = 0
   where
   leftV  = (reduceRateExprWith m left)
   rightV = (reduceRateExprWith m right)
reduceRateExprWith m  (Clt left right)
   | leftV < rightV = 1
   | otherwise      = 0
   where
   leftV  = (reduceRateExprWith m left)
   rightV = (reduceRateExprWith m right)
reduceRateExprWith m  (Cle left right)
   | leftV <= rightV  = 1
   | otherwise       = 0
   where
   leftV  = (reduceRateExprWith m left)
   rightV = (reduceRateExprWith m right)
reduceRateExprWith m  (Cnot rexp)
   | (reduceRateExprWith m rexp) == 0 = 1
   | otherwise                       = 0
reduceRateExprWith m (Cminimum left right) =
  min (reduceRateExprWith m left) (reduceRateExprWith m right)
{-

 | CAppRate RateExpr RateExpr 
            RateExpr RateExpr
   -- | Some apparent rates are active vs passive if this is the case
   -- then there is no need for a minimum, in fact it is WRONG to apply
   -- the above, we must do more or less the same calculation but the
   -- minimum is just deemed to be the left (or first) hand side.
 | CActPass RateExpr RateExpr 
            RateExpr RateExpr
-}


{-| The names used within a rate expression -}
namesOfRateExpr :: RateExpr -> [ RateIdentifier ]
namesOfRateExpr (Cident ident)   = [ ident ]
namesOfRateExpr (Cconstant _)    = []
namesOfRateExpr (Creal _)        = []
namesOfRateExpr (Cadd  e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Csub  e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Cmult e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Cdiv  e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Cifte e1 e2 e3) = union (namesOfRateExpr e1) $
                                   union (namesOfRateExpr e2) (namesOfRateExpr e3)
namesOfRateExpr (Cand  e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Cor   e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Cgt   e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Cge   e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Clt   e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Cle   e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Ceq   e1 e2)    = union (namesOfRateExpr e1) (namesOfRateExpr e2)
namesOfRateExpr (Cnot  e)        = namesOfRateExpr e
namesOfRateExpr (Cminimum e1 e2) = union (namesOfRateExpr e1) (namesOfRateExpr e2)

{-|
   This is a very simple function, however should note that if a conditional
   can have 'RateTop' (or an immediate weight) as either branch then this will
   have to check the rate expression for that.
-}
isTimedRate :: Rate a -> Bool
isTimedRate (RateTimed _)     = True
isTimedRate (RateTop _)       = True
isTimedRate (RateImmediate _) = False

{-| Relates whether the rate is immediate or not -}
isImmediateRate :: Rate a -> Bool
isImmediateRate (RateImmediate _) = True
isImmediateRate (RateTop _)       = False
isImmediateRate (RateTimed _)     = False

{-| Relates whether the given rate is passive or not -}
isPassiveRate :: Rate a -> Bool
isPassiveRate (RateTop _)       = True
isPassiveRate (RateTimed _)     = False
isPassiveRate (RateImmediate _) = False

{-| Create a passive rate -}
topRate :: Rate RateExpr
topRate = RateTop $ Creal 1.0

{-| Create a rate expression referring to the given identifier -}
namedRateExp :: RateIdentifier -> RateExpr
namedRateExp = Cident

{-| Create a rate expression with the given numeric value -}
realRateExp :: Double -> RateExpr
realRateExp = Creal

{-| Create a rate expression with the given integer value -}
integerRateExp :: Int -> RateExpr
integerRateExp = Cconstant

{-|
  This function allows convenient modification of the timed rate representation
  contained within a  'Rate' data structure. 
  Essentially it allows you to "see through" the 'Rate' constructors.
  For example one could reduce all rate expressions within a rate with
  @modifyRate (reduceRateExp c)@
-}
modifyRate :: (a -> b) -> Rate a -> Rate b
modifyRate f (RateTimed r)     = RateTimed $ f r
modifyRate f (RateImmediate w) = RateImmediate $ f w
modifyRate f (RateTop m)       = RateTop $ f m



{-| Transform a rate expression by applying the given function to
    all rate identifiers within the expression
-}
transformRateExpr :: (RateIdentifier -> RateExpr) -> RateExpr -> RateExpr
transformRateExpr f (Cident ident)          = f ident
transformRateExpr _f cexp@(Cconstant _)     = cexp
transformRateExpr _f cexp@(Creal _)         = cexp
transformRateExpr f (Cadd e1 e2)            = Cadd  (transformRateExpr f e1) 
                                                    (transformRateExpr f e2)
transformRateExpr f (Csub e1 e2)            = Csub  (transformRateExpr f e1) 
                                                    (transformRateExpr f e2)
transformRateExpr f (Cmult e1 e2)           = Cmult (transformRateExpr f e1) 
                                                    (transformRateExpr f e2)
transformRateExpr f (Cdiv e1 e2)            = Cdiv  (transformRateExpr f e1) 
                                                    (transformRateExpr f e2)
transformRateExpr f (Cifte e1 e2 e3)        = Cifte (transformRateExpr f e1) 
                                                    (transformRateExpr f e2)
                                                    (transformRateExpr f e3)
transformRateExpr f (Cand e1 e2)            = Cand  (transformRateExpr f e1) 
                                                    (transformRateExpr f e2)
transformRateExpr f (Cor  e1 e2)            = Cor   (transformRateExpr f e1)
                                                    (transformRateExpr f e2)
transformRateExpr f (Cnot e1)               = Cnot  (transformRateExpr f e1)
transformRateExpr f (Cgt  e1 e2)            = Cgt   (transformRateExpr f e1)
                                                    (transformRateExpr f e2)
transformRateExpr f (Cge  e1 e2)            = Cge   (transformRateExpr f e1)
                                                    (transformRateExpr f e2)
transformRateExpr f (Clt  e1 e2)            = Clt   (transformRateExpr f e1)
                                                    (transformRateExpr f e2)
transformRateExpr f (Cle  e1 e2)            = Cle   (transformRateExpr f e1) 
                                                    (transformRateExpr f e2)
transformRateExpr f (Ceq  e1 e2)            = Ceq   (transformRateExpr f e1)
                                                    (transformRateExpr f e2)
transformRateExpr f (Cminimum  e1 e2)       = Cminimum (transformRateExpr f e1)
                                                       (transformRateExpr f e2)
   
{-| 
  Rename a rate expression, here we take in a dictionary mapping original
  names to Cexpressions and use this to transform a C expression.
  This can be useful when mapping from a an unqualified model to a
  qualified model as we can map the identifier @P@ to @P_1 + P_2 + P_3@
  where those three names are the qualified instances of @P@.
-}
renameRateExpr :: [ (String, RateExpr) ] -> RateExpr -> RateExpr
renameRateExpr dict = 
  transformRateExpr origToRexp
  where
  origToRexp :: RateIdentifier -> RateExpr
  origToRexp ident = Maybe.fromMaybe (Cident ident) $ 
                     lookup (showOrig ident) dict

{-|
  Essentially the same as 'renameRateExpr' except we take in a mapping
  in the form of a 'Map' rather than an association list.
-}
remapRateExpr :: Map String RateExpr -> RateExpr -> RateExpr
remapRateExpr mapping =
  transformRateExpr origToRexp
  where
  origToRexp :: RateIdentifier -> RateExpr
  origToRexp ident = Maybe.fromMaybe (Cident ident) $
                     Map.lookup (showOrig ident) mapping


{-| Normalise a rate expression. This is similar to the above 'reduceRateExpr'
    in that we hope to reduce the expression to a concrete value. However here
    we are less hopeful of being able to do so (generally because we do not
    have all the information). For example this is the kind of transformation
    applied after parsing when we have enough information to substitute
    rate identifiers for their definitions. However we do not (in general)
    have enough information to fully reduce the rate expressions since they
    may contain functional rates which we cannot reduce until we are generating
    the state space.
-}
normaliseRateExpr :: [ (RateIdentifier, RateExpr) ] -> RateExpr -> RateExpr
normaliseRateExpr _m rexp@(Creal _)         = rexp
normaliseRateExpr m  rexp@(Cident p)        =  
  -- it's a good question, should we reduce the replaced
  -- expression? it may contain some identifiers in the
  -- mapping, for now I'll say no.
  Maybe.fromMaybe rexp $ lookup p m
normaliseRateExpr _m  rexp@(Cconstant _)    = rexp
normaliseRateExpr m (Cifte cond left right) =
  case ( normaliseRateExpr m cond
       , normaliseRateExpr m left
       , normaliseRateExpr m right)
  of
   (Cconstant 0, _, r) -> r
   (Creal 0.0, _, r)   -> r
   (Cconstant _, l, _) -> l
   (Creal _, l, _)     -> l
   (c, l, r)           -> Cifte c l r
normaliseRateExpr m  (Cadd left right)      =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant d1, Cconstant d2) -> Cconstant $ d1 + d2
    (Creal r1    , Creal r2)     -> Creal     $ r1 + r2
    (rexp1       , rexp2)        -> Cadd  rexp1 rexp2
normaliseRateExpr m  (Csub left right)      =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant d1, Cconstant d2) -> Cconstant $ d1 - d2
    (Creal r1    , Creal r2)     -> Creal     $ r1 - r2

    {-
      These next two lines are very questionable. Basically we're allowing
      implicit cast from integer to real. We do this for 'sub' because
      we often wish to overide the number of processes within an array.
      rate options are parsed as doubles (rather than rate expressions)
      this allows us to give a label for graphs etc. (I think ultimately
      I wish to change that.) If we add a probe to a single component of
      an array then we split the array up and we get
      (Probe <actions> Client) <> (Client[n - 1]) and we'll represent
      the "n - 1" as Csub (Cident n) (Cconstant 1), now if we override
      'n' say with --rate n = 10, then it will be substituted for a double
      so we'll end up with Csub (Creal 9.0) (Cconstant 1). Which we of
      course wish to end up as (Cconstant 8) or (Creal 8.0). 
      So for now we allow this. Ultimately I should either:
      1. Allow --rate to take in an expression rather than a double.
      2. Allow implicit casting in all expressions.
      The former seems more appealing to me.
    -}
    (Creal r1    , Cconstant d2) -> Creal     $ r1 - (fromIntegral d2)
    (Cconstant d1, Creal r2)     -> Creal     $ (fromIntegral d1) - r2

    (rexp1       , rexp2)        -> Csub  rexp1 rexp2
normaliseRateExpr m  (Cmult left right)     =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant d1, Cconstant d2) -> Cconstant $ d1 * d2
    (Creal r1    , Creal r2)     -> Creal     $ r1 * r2
    (rexp1       , rexp2)        -> Cmult  rexp1 rexp2
normaliseRateExpr m  (Cdiv left right)      =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant d1, Cconstant d2) -> Creal     $ (fromIntegral d1) / 
                                                (fromIntegral d2)
    (Creal r1    , Creal r2)     -> Creal     $ r1 / r2
    -- I still think that implicit casting is dangerous thing to do
    -- although it happens later in the compiler anyway.
    -- (Cconstant d1, Creal r2)     -> Creal     $ (fromIntegral d1) / r2
    -- (Creal r1, Cconstant d2)     -> Creal     $ r1 / (fromIntegral d2)
    (rexp1       , rexp2)        -> Cdiv  rexp1 rexp2
normaliseRateExpr m  (Cand left right)      =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant 0, _)          -> Cconstant 0
    (_, Cconstant 0)          -> Cconstant 0
    (Cconstant _, rexp2)      -> rexp2
    (rexp1, Cconstant _)      -> rexp1
    -- The same but for reals
    (Creal 0.0, _)            -> Creal 0.0
    (_, Creal 0.0)            -> Creal 0.0
    (Creal _, rexp2)          -> rexp2
    (rexp1, Creal _)          -> rexp1
    (rexp1, rexp2)            -> Cand rexp1 rexp2
normaliseRateExpr m  (Cor left right)       =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant 0, rexp2)       -> rexp2
    (rexp1, Cconstant 0)       -> rexp1
    (Cconstant _, _)           -> Cconstant 1
    (_, Cconstant _)           -> Cconstant 1
    -- The same but for reals
    (Creal 0.0, rexp2)         -> rexp2
    (rexp1, Creal 0.0)         -> rexp1
    (Creal _, _)               -> Creal 1.0
    (_, Creal _)               -> Creal 1.0
    (rexp1, rexp2)             -> Cor rexp1 rexp2
normaliseRateExpr m  (Ceq left right)       =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant d1, Cconstant d2)
      | d1 == d2                 -> Cconstant 1
      | otherwise                -> Cconstant 0
    (Creal r1    , Creal r2)
      | r1 == r2                 -> Creal 1.0
      | otherwise                -> Creal 0.0
    (rexp1       , rexp2)        -> Ceq  rexp1 rexp2
normaliseRateExpr m  (Cgt left right)       =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant d1, Cconstant d2)
      | d1 >  d2                 -> Cconstant 1
      | otherwise                -> Cconstant 0
    (Creal r1    , Creal r2)
      | r1 >  r2                 -> Creal 1.0
      | otherwise                -> Creal 0.0
    (rexp1       , rexp2)        -> Cgt  rexp1 rexp2
normaliseRateExpr m  (Cge left right)       =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant d1, Cconstant d2)
      | d1 >= d2                 -> Cconstant 1
      | otherwise                -> Cconstant 0
    (Creal r1    , Creal r2)
      | r1 >= r2                 -> Creal 1.0
      | otherwise                -> Creal 0.0
    (rexp1       , rexp2)        -> Cge  rexp1 rexp2
normaliseRateExpr m  (Clt left right)       =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant d1, Cconstant d2)
      | d1 <  d2                 -> Cconstant 1
      | otherwise                -> Cconstant 0
    (Creal r1    , Creal r2)
      | r1 <  r2                 -> Creal 1.0
      | otherwise                -> Creal 0.0
    (rexp1       , rexp2)        -> Clt  rexp1 rexp2
normaliseRateExpr m  (Cle left right)       =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant d1, Cconstant d2)
      | d1 <= d2                 -> Cconstant 1
      | otherwise                -> Cconstant 0
    (Creal r1    , Creal r2)
      | r1 <= r2                 -> Creal 1.0
      | otherwise                -> Creal 0.0
    (rexp1       , rexp2)        -> Cle  rexp1 rexp2
normaliseRateExpr m  (Cnot left)            = 
  case normaliseRateExpr m left of
    Cconstant 0 -> Cconstant 1
    Cconstant _ -> Cconstant 0
    Creal 0.0   -> Creal 1.0
    Creal _     -> Creal 0.0
    rexp        -> Cnot rexp
normaliseRateExpr m  (Cminimum left right)  =
  case (normaliseRateExpr m left, normaliseRateExpr m right) of
    (Cconstant d1, Cconstant d2) -> Cconstant $ min d1 d2
    (Creal r1    , Creal r2)     -> Creal     $ min r1 r2
    (rexp1       , rexp2)        -> Cminimum rexp1 rexp2

{-| Determines if a rate expression cannot be further reduced, that
    is it is already a constant.
-}
isNonReducable :: RateExpr -> Bool
isNonReducable (Cconstant _) = True
isNonReducable (Creal _)     = True
isNonReducable _             = False

{-| Is similar to 'isNonReducable' however we also take a list of names
    and consider any name NOT in the list to be irreducible but any list
    in that list is considered to be reducible since the list is supposed
    to be a list of definitions which we have and hence could substitute in.
-}
isIrreducible :: [ QualifiedName ] -> RateExpr -> Bool
isIrreducible names =
  cannotReduce 
  where
  -- Note that this is slightly wrong in some cases, for example:
  -- if true then 1 else P
  -- which is reducible to '1' but I don't think worth worrying about here
  cannotReduce :: RateExpr -> Bool
  cannotReduce (Cident name)      = not $ elem name names
  cannotReduce (Cconstant _)      = True
  cannotReduce (Creal _)          = True
  cannotReduce (Cadd  left right) = all cannotReduce [ left, right ]
  cannotReduce (Csub  left right) = all cannotReduce [ left, right ]
  cannotReduce (Cmult left right) = all cannotReduce [ left, right ]
  cannotReduce (Cdiv  left right) = all cannotReduce [ left, right ]
  cannotReduce (Cifte c l r)      = all cannotReduce [ c, l, r ]
  cannotReduce (Cand  left right) = all cannotReduce [ left, right ]
  cannotReduce (Cor   left right) = all cannotReduce [ left, right ]
  cannotReduce (Cgt   left right) = all cannotReduce [ left, right ]
  cannotReduce (Cge   left right) = all cannotReduce [ left, right ]
  cannotReduce (Clt   left right) = all cannotReduce [ left, right ]
  cannotReduce (Cle   left right) = all cannotReduce [ left, right ]
  cannotReduce (Ceq   left right) = all cannotReduce [ left, right ]
  cannotReduce (Cnot  expr)       = cannotReduce expr
  cannotReduce (Cminimum l r)     = all cannotReduce [ l, r ]
