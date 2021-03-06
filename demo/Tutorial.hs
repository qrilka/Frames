{-# LANGUAGE DataKinds, FlexibleContexts, OverloadedStrings,
             TemplateHaskell, TypeOperators #-}

-- This is a semi-port of a
-- [[http://ajkl.github.io/Dataframes/][dataframe tutorial]] Rosetta
-- Stone. Traditional dataframe tools built in R, Julia, Python,
-- etc. expose a richer API than Frames does (so far).

-- The example data file used does not include column headers, nor
-- does it use commas to separate values, so it does not fall into the
-- sweet spot of CSV parsing that ~Frames~ is aimed at. That said,
-- this mismatch of test data and library support is a great
-- opportunity to verify that ~Frames~ are flexible enough to meet a
-- variety of needs.

-- We begin with rather a lot of imports to support a variety of test
-- operations and parser customization. I encourage you to start with a
-- smaller test program than this!

import Control.Applicative
import qualified Control.Foldl as L
import qualified Data.Foldable as F
import Data.Monoid
import Lens.Family
import Frames
import Frames.CSV (tableTypesOpt, readTableOpt)
import Pipes hiding (Proxy)
import qualified Pipes.Prelude as P

-- A few other imports will be used for highly customized parsing [[Better Types][later]].

import Data.Proxy
import Frames.CSV (ColumnTypeable(..), tableTypesPrefixedOpt')
import TutorialUsers

-- * Data Import

-- We usually package column names with the data to keep things a bit
-- more self-documenting. This might mean adding a row to the data
-- file with the column names, but, if we must use a particular data
-- file whose column names are provided in a separate specification,
-- we can override the default parsing options.

-- The data set this example considers is rather far from the sweet spot
-- of CSV processing that ~Frames~ is aimed it: it does not include
-- column headers, nor does it use commas to separate values! However,
-- these mismatches do provide an opportunity to see that ~Frames~ are
-- flexible enough to meet a variety of needs.

tableTypesOpt  ["user id", "age", "gender", "occupation", "zip code"]
               "|" "Users" "data/ml-100k/u.user"

-- This template haskell splice explicitly specifies column names, a
-- separator string, the name for the inferred record type, and the
-- data file from which to infer the record type. The result of this
-- splice is included in an [[* Splice Dump][appendix]] below so you
-- can flip between the generated code and how it is used.

-- We can load the module into =cabal repl= to see what we have so far.

-- #+BEGIN_EXAMPLE
-- λ> :i Users
-- type Users =
--   Rec
--     '["user id" :-> Int, "age" :-> Int, "gender" :-> Text,
--       "occupation" :-> Text, "zip code" :-> Text]
-- #+END_EXAMPLE

-- This lets us perform a quick check that the types are basically what
-- we expect them to be.

-- We now define a streaming representation of the full data set. If the
-- data set is too large to keep in memory, we can process it as it
-- streams through RAM.

movieStream :: Producer Users IO ()
movieStream = readTableOpt usersParser "data/ml-100k/u.user"

-- Alternately, if we want to run multiple operations against a data set
-- that /can/ fit in RAM, we can do that. Here we define an in-core (in
-- memory) array of structures (AoS) representation.

loadMovies :: IO (Frame Users)
loadMovies = inCoreAoS movieStream

-- ** Streaming Cores?

-- A ~Frame~ is an in-memory representation of your data. The ~Frames~
-- library stores each column as compactly as it knows how, and lets you
-- index your data as a structure of arrays (where each field of the
-- structure is an array corresponding to a column of your data), or as
-- an array of structures, also known as a ~Frame~. These latter
-- structures correspond to rows of your data, and rows of data may be
-- handled in a streaming fashion so that you are not limited to
-- available RAM. In the streaming paradigm, you process each row
-- individually as a single record.

-- A ~Frame~ provides ~O(1)~ indexing, as well as any other operations
-- you are familiar with based on the ~Foldable~ class. If a data set is
-- small, keeping it in RAM is usually the fastest way to perform
-- multiple analyses on that data that you can't fuse into a single
-- traversal.

-- Alternatively, a ~Producer~ of rows is a great way to whittle down a
-- large data set before moving on to whatever you want to do next.

-- ** Sanity Check

-- We can compute some easy statistics to see how things look.

-- #+BEGIN_EXAMPLE
-- λ> ms <- loadMovies
-- λ> L.fold L.minimum (view age <$> ms)
-- Just 7
-- #+END_EXAMPLE

-- When there are multiple properties we would like to compute, we can
-- fuse multiple traversals into one pass using something like the [[http://hackage.haskell.org/package/foldl][foldl]]
-- package

-- #+BEGIN_EXAMPLE
-- λ> ms <- loadMovies
-- λ> L.fold (L.pretraverse age ((,) <$> L.minimum <*> L.maximum)) ms
-- (Just 7,Just 73)
-- #+END_EXAMPLE

-- Here we are projecting the =age= column out of each record, and
-- computing the minimum and maximum =age= for all rows.

-- * Subsetting

-- ** Row Subset

-- Data may be inspected using either Haskell's traditional list API...

-- #+BEGIN_EXAMPLE
-- λ> ms <- loadMovies
-- λ> mapM_ print (take 3 (F.toList ms))
-- {user id :-> 1, age :-> 24, gender :-> "M", occupation :-> "technician", zip code :-> "85711"}
-- {user id :-> 2, age :-> 53, gender :-> "F", occupation :-> "other", zip code :-> "94043"}
-- {user id :-> 3, age :-> 23, gender :-> "M", occupation :-> "writer", zip code :-> "32067"}
-- #+END_EXAMPLE

-- ... or =O(1)= indexing of individual rows. Here we take the last three
-- rows of the data set,

-- #+BEGIN_EXAMPLE
-- λ> mapM_ (print . frameRow ms) [frameLength ms - 3 .. frameLength ms - 1]
-- {user id :-> 941, age :-> 20, gender :-> "M", occupation :-> "student", zip code :-> "97229"}
-- {user id :-> 942, age :-> 48, gender :-> "F", occupation :-> "librarian", zip code :-> "78209"}
-- {user id :-> 943, age :-> 22, gender :-> "M", occupation :-> "student", zip code :-> "77841"}
-- #+END_EXAMPLE

-- This lets us view a subset of rows,

-- #+BEGIN_EXAMPLE
-- λ> mapM_ (print . frameRow ms) [50..55]
-- {user id :-> 51, age :-> 28, gender :-> "M", occupation :-> "educator", zip code :-> "16509"}
-- {user id :-> 52, age :-> 18, gender :-> "F", occupation :-> "student", zip code :-> "55105"}
-- {user id :-> 53, age :-> 26, gender :-> "M", occupation :-> "programmer", zip code :-> "55414"}
-- {user id :-> 54, age :-> 22, gender :-> "M", occupation :-> "executive", zip code :-> "66315"}
-- {user id :-> 55, age :-> 37, gender :-> "M", occupation :-> "programmer", zip code :-> "01331"}
-- {user id :-> 56, age :-> 25, gender :-> "M", occupation :-> "librarian", zip code :-> "46260"}
-- #+END_EXAMPLE

-- ** Column Subset

-- We can consider a single column.

-- #+BEGIN_EXAMPLE
-- λ> take 6 $ F.foldMap ((:[]) . view occupation) ms
-- ["technician","other","writer","technician","other","executive"]
-- #+END_EXAMPLE

-- Or multiple columns,

miniUser :: Users -> Rec [Occupation, Gender, Age]
miniUser = rcast

-- #+BEGIN_EXAMPLE
-- λ> mapM_ print . take 6 . F.toList $ fmap miniUser ms
-- {occupation :-> "technician", gender :-> "M", age :-> 24}
-- {occupation :-> "other", gender :-> "F", age :-> 53}
-- {occupation :-> "writer", gender :-> "M", age :-> 23}
-- {occupation :-> "technician", gender :-> "M", age :-> 24}
-- {occupation :-> "other", gender :-> "F", age :-> 33}
-- {occupation :-> "executive", gender :-> "M", age :-> 42}
-- #+END_EXAMPLE

-- ** Query / Conditional Subset

-- Filtering our frame is rather nicely done using the
-- [[http://hackage.haskell.org/package/pipes][pipes]] package. Here
-- we pick out the users whose occupation is "writer".

writers :: (Occupation ∈ rs, Monad m) => Pipe (Rec rs) (Rec rs) m r
writers = P.filter ((== "writer") . view occupation)

-- #+BEGIN_EXAMPLE
-- λ> runEffect $ movieStream >-> writers >-> P.take 6 >-> P.print
-- {user id :-> 3, age :-> 23, gender :-> "M", occupation :-> "writer", zip code :-> "32067"}
-- {user id :-> 21, age :-> 26, gender :-> "M", occupation :-> "writer", zip code :-> "30068"}
-- {user id :-> 22, age :-> 25, gender :-> "M", occupation :-> "writer", zip code :-> "40206"}
-- {user id :-> 28, age :-> 32, gender :-> "M", occupation :-> "writer", zip code :-> "55369"}
-- {user id :-> 50, age :-> 21, gender :-> "M", occupation :-> "writer", zip code :-> "52245"}
-- {user id :-> 122, age :-> 32, gender :-> "F", occupation :-> "writer", zip code :-> "22206"}
-- #+END_EXAMPLE

-- * Better Types

-- A common disappointment of parsing general data sets is the
-- reliance on text for data representation even /after/ parsing. If
-- you find that the default =ColType= spectrum of potential column
-- types that =Frames= uses doesn't capture desired structure, you can
-- go ahead and define your own universe of column types! The =Users=
-- row types we've been playing with here is rather boring: it only
-- uses =Int= and =Text= column types. But =Text= is far too vague a
-- type for a column like =gender=.

-- #+BEGIN_EXAMPLE
-- λ> L.purely P.fold L.nub (movieStream >-> P.map (view gender))
-- ["M", "F"]
-- #+END_EXAMPLE

-- Aha! The =gender= column is pretty simple, so let's go ahead and
-- define our own universe of column types.

-- -- #+BEGIN_SRC haskell
-- data GenderT = Male | Female deriving (Eq,Ord,Show)

-- data UserCol = TInt | TGender | TText deriving (Eq,Show,Ord,Enum,Bounded)
-- #+END_SRC

-- We will also need a few instance that you can find in an [[* User Types][appendix]].

-- We name this record type ~U2~, and give all the generated column types
-- and lenses a prefix, "u2", so they don't conflict with the definitions
-- we generated earlier.

tableTypesPrefixedOpt' (Proxy::Proxy UserCol) 
                       ["user id", "age", "gender", "occupation", "zip code"]
                       "|" "U2" "u2" "data/ml-100k/u.user"

movieStream2 :: Producer U2 IO ()
movieStream2 = readTableOpt u2Parser "data/ml-100k/u.user"

-- This new record type, =U2=, has a more interesting =gender=
-- column.

-- #+BEGIN_EXAMPLE
-- λ> :i U2
-- type U2 =
--   Rec
--     '["user id" :-> Int, "age" :-> Int, "gender" :-> GenderT,
--       "occupation" :-> Text, "zip code" :-> Text]
-- #+END_EXAMPLE

-- Let's take the occupations of the first 10 female users:

femaleOccupations :: (U2gender ∈ rs, U2occupation ∈ rs, Monad m)
                  => Pipe (Rec rs) Text m r
femaleOccupations = P.filter ((== Female) . view u2gender)
                    >-> P.map (view u2occupation)

-- #+BEGIN_EXAMPLE
-- λ> runEffect $ movieStream2 >-> femaleOccupations >-> P.take 10 >-> P.print
-- "other"
-- "other"
-- "other"
-- "other"
-- "educator"
-- "other"
-- "homemaker"
-- "artist"
-- "artist"
-- "librarian"
-- #+END_EXAMPLE

-- So there we go! We've done both row and column subset queries with a
-- strongly typed query (namely, ~(== Female)~). Another situation in
-- which one might want to define a custom universe of column types is
-- when dealing with dates. This would let you both reject rows with
-- badly formatted dates, for example, and efficiently query the data set
-- with richly-typed queries.

-- Even better, did you notice the types of ~writers~ and
-- ~femaleOccupations~? They are polymorphic over the full row type!
-- That's what the ~(Occupation ∈ rs)~ constraint signifies: such a
-- function will work for record types with any set of fields, ~rs~, so
-- long as ~Occupation~ is an element of that set. This means that if
-- your schema changes, or you switch to a related but different data
-- set, *these functions can still be used without even touching the
-- code*. Just recompile against the new data set, and you're good to go.

-- * Appendix
-- ** User Types

-- Here are the definitions needed to define the ~UserCol~ type with its
-- more descriptive ~GenderT~ type. We have to define these things in a
-- separate module from our main work due to GHC's stage restrictions
-- regarding Template Haskell. Specifically, ~UserCol~ and its instances
-- are used at compile time to infer the record type needed to represent
-- the data file. Notice the extension point here, though somewhat
-- buried, is not too rough: you prepend new, more refined, type
-- compatibility checks to the end of the ~inferType~ definition.

-- This is clearly a bit of a mouthful, and probably not something you'd
-- want to do for every data set. However, the /ability/ to refine the
-- structure of parsed data is in keeping with the overall goal of
-- ~Frames~: it's easy to take off, and the sky's the limit.

-- -- #+begin_src haskell
-- {-# LANGUAGE OverloadedStrings, TemplateHaskell #-}
-- module TutorialUsers where
-- import Control.Monad (liftM, mzero)
-- import Data.Bool (bool)
-- import Data.Maybe (fromMaybe)
-- import Data.Monoid
-- import Data.Readable (Readable(fromText))
-- import qualified Data.Text as T
-- import Data.Traversable (sequenceA)
-- import qualified Data.Vector as V
-- import Frames.CSV (ColumnTypeable(..))
-- import Frames.InCore (VectorFor)

-- data GenderT = Male | Female deriving (Enum,Eq,Ord,Show)

-- instance Readable GenderT where
--   fromText t
--       | t' == "m" = return Male
--       | t' == "f" = return Female
--       | otherwise = mzero
--     where t' = T.toCaseFold t

-- data UserCol = TInt | TGender | TText deriving (Eq,Show,Ord,Enum,Bounded)

-- instance Monoid UserCol where
--   mempty = maxBound
--   mappend x y = if x == y then x else TText

-- instance ColumnTypeable UserCol where
--   colType TInt = [t|Int|]
--   colType TGender = [t|GenderT|]
--   colType TText = [t|T.Text|]
--   inferType = let isInt = fmap (const TInt :: Int -> UserCol) . fromText
--                   isGen = bool Nothing (Just TGender) . (`elem` ["M","F"])
--               in fromMaybe TText . mconcat . sequenceA [isGen, isInt]

-- -- See @demo/TutorialUsers.hs@ in the repository for an example of how
-- -- to define a packed representation for a custom column type. It uses
-- -- the usual "Data.Vector.Generic" machinery.
-- type instance VectorFor GenderT = V.Vector
-- #+end_src

-- ** Splice Dump
-- The Template Haskell splices we use produce quite a lot of
-- code. The raw dumps of these splices can be hard to read, but I have
-- included some elisp code for cleaning up that output in the design
-- notes for =Frames=. Here is what we get from the ~tableTypesOpt~
-- splice shown above.

-- The overall structure is this:

-- - A ~Rec~ type called ~Users~ with all necessary columns
-- - A ~usersParser~ value that overrides parsing defaults
-- - A type synonym for each column that pairs the column name with its
--   type
-- - A lens to work with each column on any given row

-- Remember that for CSV files that include a header, the splice you
-- write in your code need not include the column names or separator
-- character.

-- #+BEGIN_EXAMPLE
--     tableTypesOpt
--       ["user id", "age", "gender", "occupation", "zip code"]
--       "|"
--       "Users"
--       "data/ml-100k/u.user"
--   ======>
--     type Users =
--         Rec ["user id" :-> Int, "age" :-> Int, "gender" :-> Text, "occupation" :-> Text, "zip code" :-> Text]

--     usersParser :: ParserOptions
--     usersParser
--       = ParserOptions
--           (Just
--              (map
--                 T.pack
--                 ["user id", "age", "gender", "occupation", "zip code"]))
--           (T.pack "|")

--     type UserId = "user id" :-> Int

--     userId ::
--       forall f_aciy rs_aciz. (Functor f_aciy,
--                               RElem UserId rs_aciz ) =>
--       (Int -> f_aciy Int) -> Rec rs_aciz -> f_aciy (Rec rs_aciz)
--     userId = rlens (Proxy :: Proxy UserId)

--     userId' ::
--       forall g_aciA f_aciB rs_aciC. (Functor f_aciB,
--                                      RElem UserId rs_aciC ) =>
--       (g_aciA Int -> f_aciB (g_aciA Int))
--       -> RecF g_aciA rs_aciC -> f_aciB (RecF g_aciA rs_aciC)
--     userId' = rlens' (Proxy :: Proxy UserId)

--     type Age = "age" :-> Int

--     age ::
--       forall f_aciD rs_aciE. (Functor f_aciD,
--                               RElem Age rs_aciE ) =>
--       (Int -> f_aciD Int) -> Rec rs_aciE -> f_aciD (Rec rs_aciE)
--     age = rlens (Proxy :: Proxy Age)

--     age' ::
--       forall g_aciF f_aciG rs_aciH. (Functor f_aciG,
--                                      RElem Age rs_aciH ) =>
--       (g_aciF Int -> f_aciG (g_aciF Int))
--       -> RecF g_aciF rs_aciH -> f_aciG (RecF g_aciF rs_aciH)
--     age' = rlens' (Proxy :: Proxy Age)

--     type Gender = "gender" :-> Text

--     gender ::
--       forall f_aciI rs_aciJ. (Functor f_aciI,
--                               RElem Gender rs_aciJ ) =>
--       (Text -> f_aciI Text) -> Rec rs_aciJ -> f_aciI (Rec rs_aciJ)
--     gender = rlens (Proxy :: Proxy Gender)

--     gender' ::
--       forall g_aciK f_aciL rs_aciM. (Functor f_aciL,
--                                      RElem Gender rs_aciM ) =>
--       (g_aciK Text -> f_aciL (g_aciK Text))
--       -> RecF g_aciK rs_aciM -> f_aciL (RecF g_aciK rs_aciM)
--     gender' = rlens' (Proxy :: Proxy Gender)

--     type Occupation = "occupation" :-> Text

--     occupation ::
--       forall f_aciN rs_aciO. (Functor f_aciN,
--                               RElem Occupation rs_aciO ) =>
--       (Text -> f_aciN Text) -> Rec rs_aciO -> f_aciN (Rec rs_aciO)
--     occupation = rlens (Proxy :: Proxy Occupation)

--     occupation' ::
--       forall g_aciP f_aciQ rs_aciR. (Functor f_aciQ,
--                                      RElem Occupation rs_aciR ) =>
--       (g_aciP Text -> f_aciQ (g_aciP Text))
--       -> RecF g_aciP rs_aciR -> f_aciQ (RecF g_aciP rs_aciR)
--     occupation' = rlens' (Proxy :: Proxy Occupation)

--     type ZipCode = "zip code" :-> Text

--     zipCode ::
--       forall f_aciS rs_aciT. (Functor f_aciS,
--                               RElem ZipCode rs_aciT ) =>
--       (Text -> f_aciS Text) -> Rec rs_aciT -> f_aciS (Rec rs_aciT)
--     zipCode = rlens (Proxy :: Proxy ZipCode)

--     zipCode' ::
--       forall g_aciU f_aciV rs_aciW. (Functor f_aciV,
--                                      RElem ZipCode rs_aciW ) =>
--       (g_aciU Text -> f_aciV (g_aciU Text))
--       -> RecF g_aciU rs_aciW -> f_aciV (RecF g_aciU rs_aciW)
--     zipCode' = rlens' (Proxy :: Proxy ZipCode)
-- #+END_EXAMPLE

-- ** Thanks
-- Thanks to Greg Hale for reviewing an early draft of this document.

-- #+DATE:
-- #+TITLE: Frames Tutorial
-- #+OPTIONS: html-link-use-abs-url:nil html-postamble:nil
