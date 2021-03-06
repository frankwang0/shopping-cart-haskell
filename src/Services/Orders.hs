{-# LANGUAGE DeriveAnyClass, DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, RecordWildCards #-}
{-# LANGUAGE FlexibleInstances #-}

module Services.Orders
  ( Orders(..)
  , mkOrders
  )
where

import           Data.Aeson                     ( toJSON )
import           Data.Aeson.Types               ( Value )
import           Data.Bifunctor                 ( bimap )
import           Data.Functor                   ( void )
import           Data.Map                       ( Map )
import qualified Data.Map                      as M
import           Data.Maybe                     ( listToMaybe )
import           Data.Text                      ( Text )
import           Data.UUID                      ( UUID )
import qualified Data.UUID                     as UUID
import qualified Data.UUID.V4                  as UUID
import           Database.PostgreSQL.Simple
import           Database.PostgreSQL.Simple.FromField
import           Database.PostgreSQL.Simple.ToField
import           Domain.Cart
import           Domain.Item
import           Domain.Order
import           Domain.Payment
import           Domain.User
import           GHC.Generics                   ( Generic )

data Orders m = Orders
  { get :: UserId -> OrderId -> m (Maybe Order)
  , findBy :: UserId -> m [Order]
  , create :: UserId -> PaymentId -> [CartItem] -> Money -> m OrderId
  }

mkOrders :: Connection -> IO (Orders IO)
mkOrders conn = pure $ Orders
  { get    = \uid oid -> (fmap . fmap) toDomain (get' conn uid oid)
  , findBy = (fmap . fmap) toDomain . findBy' conn
  , create = create' conn
  }

instance FromField [CartItem] where
  fromField = fromJSONField

data OrderDTO = OrderDTO
  { _orderId :: UUID
  , _orderUserId :: UUID
  , _orderPaymentId :: UUID
  , _orderItems :: [CartItem]
  , _orderTotal :: Rational
  } deriving (Generic, FromRow, Show)

toDomain :: OrderDTO -> Order
toDomain OrderDTO {..} = Order { orderId        = OrderId _orderId
                               , orderPaymentId = PaymentId _orderPaymentId
                               , orderItems     = parseItems _orderItems
                               , orderTotal = Money $ fromRational _orderTotal
                               }

parseItems :: [CartItem] -> Map ItemId Quantity
parseItems xs =
  M.fromList $ (\i -> (itemId $ cartItem i, cartQuantity i)) <$> xs

selectByUserAndOrderQuery :: Query
selectByUserAndOrderQuery =
  "SELECT * FROM orders WHERE user_id = ? AND uuid = ?"

get' :: Connection -> UserId -> OrderId -> IO (Maybe OrderDTO)
get' conn UserId {..} OrderId {..} =
  listToMaybe <$> query conn selectByUserAndOrderQuery [unUserId, unOrderId]

findBy' :: Connection -> UserId -> IO [OrderDTO]
findBy' = flip query "SELECT * FROM orders WHERE user_id = ?"

create'
  :: Connection -> UserId -> PaymentId -> [CartItem] -> Money -> IO OrderId
create' conn UserId {..} PaymentId {..} its Money {..} = do
  oid <- OrderId <$> UUID.nextRandom
  executeMany conn "INSERT INTO orders VALUES (?, ?, ?, ?, ?)" (values oid)
  pure oid
 where
  values oid = [(unOrderId oid, unUserId, unPaymentId, toJSON its, unMoney)]
