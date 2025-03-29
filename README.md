# Asset Management & Options Contract

## Overview
This project provides a smart contract implementation for managing financial assets, tracking volatility, and enabling options trading. It includes functionalities for updating asset prices, monitoring volatility, and handling option creation, exercise, and liquidation.

## Features
### 1. Asset Price & Volatility Updates
- Updates an asset's last traded price.
- Tracks and maintains historical volatility.
- Ensures accurate market data for contract execution.

### 2. Liquidation Check
- Identifies under-collateralized options.
- Prevents invalid contract executions due to insufficient collateral.
- Ensures fair trading practices.

### 3. Options Contract Functionality
- Allows users to create, exercise, and settle options.
- Ensures proper collateral validation before contract execution.
- Tracks option positions, including active and exercised states.

## How It Works
### Updating Asset Price & Volatility
The smart contract provides a method to update an asset’s last price and volatility:
```clojure
;; Update asset price
(map-set assets
  { asset-id: asset-id }
  (merge asset {
    last-price: price,
    last-price-update: block-height
  })
)

;; Update asset volatility
(map-set assets
  { asset-id: asset-id }
  (merge asset {
    historical-volatility: volatility-bp,
    volatility-history: (append (buff-to-list (list-to-buff old-history) u1 u29) volatility-bp)
  })
)
```

### Liquidation Check
The `check-liquidations` function scans for under-collateralized positions and flags them for further action.

### Options Contract Execution
1. **Create an Option:** Ensures collateral is deposited before contract initiation.
2. **Exercise an Option:** Verifies asset price movement before execution.
3. **Liquidation:** Flags and processes insufficiently backed options.

## Testing & Deployment
1. Deploy the smart contract and initialize asset data.
2. Use functions to update asset prices and volatility.
3. Create an option contract and verify collateralization.
4. Run liquidation checks for risk assessment.

## Future Enhancements
- Automated liquidation execution.
- Advanced risk management tools.
- Support for multi-asset options.

---
Developed for secure and efficient decentralized trading.

