# Seller role / POS (2026-07-13)

## Layout (phone)
Tezkor: pastki savat `SizedBox(height: 42%|20%)` + ichida ListView — qatorlar (nima×qancha) tepada, to‘lov pastga scroll. Qidiruv maydoni YO‘Q.

## Catalog
- Food: `food_catalog` + `food_inventory`.
- Bread: **tayyor** + **ёпиш qoldiq** (`totalStock>0` va remaining>0). Toy — yo‘q. CF `resolveSellerCatalogLine` shu qoida.
- Yopish qoldiq kartada `(qoldiq)` yorlig‘i.

## P0–P2 DONE
… (oldingi).
