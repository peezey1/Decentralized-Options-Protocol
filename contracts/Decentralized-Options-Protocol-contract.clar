;; Decentralized Options Protocol
;; An options trading platform built entirely on Clarity

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-asset-exists (err u102))
(define-constant err-asset-not-found (err u103))
(define-constant err-option-not-found (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-insufficient-collateral (err u106))
(define-constant err-invalid-parameters (err u107))
(define-constant err-option-expired (err u108))
(define-constant err-option-not-expired (err u109))
(define-constant err-option-not-exercisable (err u110))
(define-constant err-option-already-settled (err u111))
(define-constant err-option-not-liquidatable (err u112))
(define-constant err-already-exercised (err u113))
(define-constant err-oracle-error (err u114))
(define-constant err-price-too-old (err u115))
(define-constant err-min-collateral (err u116))
(define-constant err-invalid-expiry (err u117))
(define-constant err-invalid-option-type (err u118))
(define-constant err-invalid-option-style (err u119))
(define-constant err-option-in-grace-period (err u120))
(define-constant err-option-not-in-grace-period (err u121))
(define-constant err-position-not-found (err u122))
(define-constant err-invalid-position-state (err u123))
(define-constant err-emergency-shutdown (err u124))
(define-constant err-maintenance-margin-too-low (err u125))
(define-constant err-premium-too-small (err u126))
(define-constant err-unsupported-calculation (err u127))

;; Option types enumeration
;; 0 = Call, 1 = Put
(define-data-var option-types (list 2 (string-ascii 4)) (list "Call" "Put"))

;; Option styles enumeration
;; 0 = American, 1 = European
(define-data-var option-styles (list 2 (string-ascii 9)) (list "American" "European"))

;; Position states enumeration
;; 0 = Active, 1 = Exercised, 2 = Expired, 3 = Liquidated
(define-data-var position-states (list 4 (string-ascii 10)) (list "Active" "Exercised" "Expired" "Liquidated"))

;; Supported underlying assets
(define-map assets
  { asset-id: (string-ascii 20) }
  {
    name: (string-ascii 40),
    price-oracle: principal,
    token-contract: principal,
    decimals: uint,
    historical-volatility: uint, ;; Annualized volatility in basis points
    volatility-history: (list 30 uint), ;; Last 30 days of volatility data
    is-stx: bool, ;; STX is handled specially
    minimum-increment: uint, ;; Smallest tradable amount
    last-price: uint, ;; Latest price in STX with 8 decimals
    last-price-update: uint, ;; Block height of last price update
    risk-factor: uint, ;; Risk factor 1-100
    enabled: bool
  }
)

;; Options contracts
(define-map options
  { option-id: uint }
  {
    creator: principal,
    underlying-asset: (string-ascii 20),
    strike-price: uint, ;; In STX with 8 decimals
    expiry-height: uint,
    option-type: uint, ;; 0=Call, 1=Put
    option-style: uint, ;; 0=American, 1=European
    collateral-amount: uint,
    premium: uint, ;; In STX
    contract-size: uint, ;; Number of units of underlying
    creation-height: uint,
    settlement-price: (optional uint),
    is-settled: bool,
    settlement-height: (optional uint),
    collateral-token: (string-ascii 20), ;; Token used for collateral
    holder: (optional principal),
    is-exercised: bool,
    exercise-height: (optional uint),
    is-liquidated: bool,
    liquidation-height: (optional uint),
    iv-at-creation: uint, ;; Implied volatility at creation in basis points
    premium-calculation-method: (string-ascii 10) ;; "black-scholes" or "custom"
  }
)
;; Option positions
(define-map positions
  { position-id: uint }
  {
    option-id: uint,
    holder: principal,
    purchase-height: uint,
    purchase-price: uint, ;; Premium paid
    size: uint, ;; Number of contracts
    state: uint, ;; 0=Active, 1=Exercised, 2=Expired, 3=Liquidated
    pnl: (optional int), ;; Profit/loss calculated at settlement
    exercise-price: (optional uint),
    exercise-height: (optional uint),
    liquidation-price: (optional uint),
    liquidation-height: (optional uint)
  }
)

;; User positions
(define-map user-positions
  { user: principal }
  { position-ids: (list 100 uint) }
)

;; Oracle price data
(define-map price-data
  { asset-id: (string-ascii 20) }
  {
    current-price: uint,
    last-update: uint,
    historical-prices: (list 30 { price: uint, height: uint }),
    twap-price: uint, ;; Time-weighted average price
    source: principal
  }
)

;; Black-Scholes calculation parameters table
;; This table stores saved calculation results to avoid complex calculations on-chain
(define-map bs-params
  { 
    option-type: uint, 
    time-to-expiry-days: uint,
    volatility-bp: uint,
    spot-price-5pct: uint, ;; Divided by strike price, quantized to 5% increments
    interest-rate-bp: uint
  }
  {
    d1: int,
    d2: int,
    call-price: uint, ;; ATM call price as percentage of spot price (8 decimals)
    put-price: uint,  ;; ATM put price as percentage of spot price (8 decimals)
    call-delta: int,  ;; Delta value scaled to -100 to 100
    put-delta: int,   ;; Delta value scaled to -100 to 100
    gamma: uint,      ;; Gamma value
    vega: uint,       ;; Vega value
    theta: uint       ;; Theta value
  }
)

;; Initialize the protocol
(define-public (initialize (treasury principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set treasury-address treasury)
    (var-set protocol-fee-bp u50) ;; 0.5%
    (var-set min-collateral-ratio u12000) ;; 120%
    (var-set maintenance-margin-ratio u11000) ;; 110%
    (var-set min-expiry-period u144) ;; 1 day minimum
    (var-set max-expiry-period u262800) ;; 6 months maximum
    (var-set liquidation-penalty u1000) ;; 10% penalty
    (var-set price-validity-period u72) ;; 12 hours
    (var-set emergency-shutdown false)
    
    (ok true)
  )
)

;; Register a new underlying asset
(define-public (register-asset
  (asset-id (string-ascii 20))
  (name (string-ascii 40))
  (price-oracle principal)
  (token-contract principal)
  (decimals uint)
  (is-stx bool)
  (minimum-increment uint)
  (risk-factor uint))
  
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    (asserts! (is-none (map-get? assets { asset-id: asset-id })) err-asset-exists)
    (asserts! (<= risk-factor u100) err-invalid-parameters) ;; Risk factor must be between 1-100
    
    ;; Create asset entry
    (map-set assets
      { asset-id: asset-id }
      {
        name: name,
        price-oracle: price-oracle,
        token-contract: token-contract,
        decimals: decimals,
        historical-volatility: u2000, ;; Default to 20% annualized volatility
        volatility-history: (list u2000 u2000 u2000 u2000 u2000), ;; Initialize with default volatility
        is-stx: is-stx,
        minimum-increment: minimum-increment,
        last-price: u0,
        last-price-update: block-height,
        risk-factor: risk-factor,
        enabled: true
      }
    )
    
    ;; Initialize price data
    (map-set price-data
      { asset-id: asset-id }
      {
        current-price: u0,
        last-update: block-height,
        historical-prices: (list),
        twap-price: u0,
        source: price-oracle
      }
    )
    
    (ok asset-id)
  )
)

;; Update asset price from oracle
(define-public (update-asset-price (asset-id (string-ascii 20)) (price uint))
  (let (
    (oracle tx-sender)
    (asset (unwrap! (map-get? assets { asset-id: asset-id }) err-asset-not-found))
    (price-data-entry (default-to {
      current-price: u0,
      last-update: block-height,
      historical-prices: (list),
      twap-price: u0,
      source: oracle
    } (map-get? price-data { asset-id: asset-id })))
  )
    ;; Ensure the caller is the registered price oracle
    (asserts! (is-eq oracle (get price-oracle asset)) err-not-authorized)
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    
    ;; Update price data
    (let (
      (historical-prices (get historical-prices price-data-entry))
      (updated-history (if (>= (len historical-prices) u30)
                         (add-price-to-history (buff-to-list (list-to-buff historical-prices) u1 u30) price)
                         (append historical-prices { price: price, height: block-height })))
      (twap (calculate-twap updated-history))
    )
      (map-set price-data
        { asset-id: asset-id }
        {
          current-price: price,
          last-update: block-height,
          historical-prices: updated-history,
          twap-price: twap,
          source: oracle
        }
      )
      
 ;; Update asset's last price
      (map-set assets
        { asset-id: asset-id }
        (merge asset {
          last-price: price,
          last-price-update: block-height
        })
      )
      
      ;; Check for options that need liquidation
      (check-liquidations asset-id price)
      
      (ok { asset: asset-id, price: price, twap: twap })
    )
  )
)

;; Helper to add price to history
(define-private (add-price-to-history 
  (history (list 30 { price: uint, height: uint }))
  (new-price uint))
  
  (append (buff-to-list (list-to-buff history) u1 u29)
          { price: new-price, height: block-height })
)

;; Helper to calculate TWAP (Time-Weighted Average Price)
(define-private (calculate-twap 
  (history (list 30 { price: uint, height: uint })))
  
  (let (
    (history-length (len history))
    (sum (fold sum-price u0 history))
  )
    (if (> history-length u0)
      (/ sum history-length)
      u0
    )
  )
)

;; Helper to sum prices for TWAP
(define-private (sum-price 
  (total uint) 
  (entry { price: uint, height: uint }))
  
  (+ total (get price entry))
)

;; Check options for liquidation
(define-private (check-liquidations 
  (asset-id (string-ascii 20))
  (price uint))
  
  ;; In a full implementation, this would scan all options for under-collateralized positions
  ;; For simplicity, we'll assume this is handled differently or through callbacks
  (ok true)
)

;; Update volatility for an asset
(define-public (update-volatility (asset-id (string-ascii 20)) (volatility-bp uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    (asserts! (<= volatility-bp u10000) err-invalid-parameters) ;; Max 100% volatility
    
    (let (
      (asset (unwrap! (map-get? assets { asset-id: asset-id }) err-asset-not-found))
      (old-history (get volatility-history asset))
    )
      ;; Update asset volatility
      (map-set assets
        { asset-id: asset-id }
        (merge asset {
          historical-volatility: volatility-bp,
          volatility-history: (append (buff-to-list (list-to-buff old-history) u1 u29) volatility-bp)
        })
      )
      
      (ok { asset: asset-id, volatility: volatility-bp })
    )
  )
)

;; Create a new option contract
(define-public (create-option
  (underlying-asset (string-ascii 20))
  (strike-price uint)
  (expiry-height uint)
  (option-type uint)
  (option-style uint)
  (contract-size uint)
  (premium uint)
  (collateral-token (string-ascii 20)))
  
  (let (
    (writer tx-sender)
    (option-id (var-get next-option-id))
    (asset (unwrap! (map-get? assets { asset-id: underlying-asset }) err-asset-not-found))
    (asset-price (unwrap! (get current-price (map-get? price-data { asset-id: underlying-asset })) err-oracle-error))
    (current-height block-height)
    (expiry-blocks (- expiry-height current-height))
  )
    ;; Validation
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    (asserts! (get enabled asset) err-asset-not-found)
    (asserts! (< option-type u2) err-invalid-option-type) ;; 0=Call, 1=Put
    (asserts! (< option-style u2) err-invalid-option-style) ;; 0=American, 1=European
    (asserts! (>= expiry-blocks (var-get min-expiry-period)) err-invalid-expiry)
    (asserts! (<= expiry-blocks (var-get max-expiry-period)) err-invalid-expiry)
    (asserts! (>= premium (var-get min-premium)) err-premium-too-small)
    (asserts! (> contract-size u0) err-invalid-parameters)
    (asserts! (> strike-price u0) err-invalid-parameters)
    
    ;; Validate latest price is fresh enough
    (asserts! (< (- current-height (get last-price-update asset)) (var-get price-validity-period)) err-price-too-old)
    
    ;; Calculate required collateral
    (let (
      (collateral-amount (calculate-required-collateral option-type underlying-asset strike-price contract-size))
      (iv (get historical-volatility asset))
    )
      ;; Ensure minimum collateral
      (asserts! (>= collateral-amount (/ (* contract-size u1) u100)) err-min-collateral)
      
      ;; Transfer collateral from writer
      (if (is-eq collateral-token "stx")
        ;; STX collateral
        (try! (stx-transfer? collateral-amount writer (as-contract tx-sender)))
        ;; Other token as collateral
        (try! (transfer-token collateral-token collateral-amount writer (as-contract tx-sender)))
      )
      
      ;; Create option
      (map-set options
        { option-id: option-id }
        {
          creator: writer,
          underlying-asset: underlying-asset,
          strike-price: strike-price,
          expiry-height: expiry-height,
          option-type: option-type,
          option-style: option-style,
          collateral-amount: collateral-amount,
          premium: premium,
          contract-size: contract-size,
          creation-height: current-height,
          settlement-price: none,
          is-settled: false,
          settlement-height: none,
          collateral-token: collateral-token,
          holder: none,
          is-exercised: false,
          exercise-height: none,
          is-liquidated: false,
          liquidation-height: none,
          iv-at-creation: iv,
          premium-calculation-method: "black-scholes"
        }
      )
      
      ;; Increment option ID
      (var-set next-option-id (+ option-id u1))
      
      (ok {
        option-id: option-id,
        collateral: collateral-amount,
        premium: premium
      })
    )
  )
)

;; Calculate required collateral based on option type and parameters
(define-private (calculate-required-collateral
  (option-type uint)
  (underlying-asset (string-ascii 20))
  (strike-price uint)
  (contract-size uint))
  
  (let (
    (asset (unwrap! (map-get? assets { asset-id: underlying-asset }) err-asset-not-found))
    (asset-price (unwrap! (get current-price (map-get? price-data { asset-id: underlying-asset })) err-oracle-error))
    (min-collateral-ratio (var-get min-collateral-ratio))
  )
    (if (is-eq option-type u0)
      ;; Call option collateral
      (if (get is-stx asset)
        ;; STX-settled call option needs full collateral
        contract-size
        ;; Regular call option
        (/ (* contract-size asset-price min-collateral-ratio) u10000)
      )
      ;; Put option collateral
      (/ (* contract-size strike-price min-collateral-ratio) u10000)
    )
  )
)

;; Buy an option
(define-public (buy-option (option-id uint))
  (let (
    (buyer tx-sender)
    (option (unwrap! (map-get? options { option-id: option-id }) err-option-not-found))
    (premium (get premium option))
    (position-id (var-get next-position-id))
  )
    ;; Validation
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    (asserts! (is-none (get holder option)) err-option-not-found) ;; Option must not be bought yet
    (asserts! (< block-height (get expiry-height option)) err-option-expired)
    
    ;; Transfer premium to writer
    (try! (stx-transfer? premium buyer (get creator option)))
    
    ;; Transfer protocol fee to treasury
    (let (
      (protocol-fee (/ (* premium (var-get protocol-fee-bp)) u10000))
    )
      (try! (stx-transfer? protocol-fee buyer (var-get treasury-address)))
      
      ;; Update option with new holder
      (map-set options
        { option-id: option-id }
        (merge option { holder: (some buyer) })
      )
      
      ;; Create position for buyer
      (map-set positions
        { position-id: position-id }
        {
          option-id: option-id,
          holder: buyer,
          purchase-height: block-height,
          purchase-price: premium,
          size: u1, ;; Each position represents one contract
          state: u0, ;; Active
          pnl: none,
          exercise-price: none,
          exercise-height: none,
          liquidation-price: none,
          liquidation-height: none
        }
      )
      
      ;; Update user positions list
      (let (
        (user-pos (default-to { position-ids: (list) } (map-get? user-positions { user: buyer })))
      )
        (map-set user-positions
          { user: buyer }
          { position-ids: (append (get position-ids user-pos) position-id) }
        )
      )
      
      ;; Increment position ID
      (var-set next-position-id (+ position-id u1))
      
      (ok {
        position-id: position-id,
        premium: premium,
        fee: protocol-fee
      })
    )
  )
)

;; Exercise an option
(define-public (exercise-option (position-id uint))
  (let (
    (holder tx-sender)
    (position (unwrap! (map-get? positions { position-id: position-id }) err-position-not-found))
    (option-id (get option-id position))
    (option (unwrap! (map-get? options { option-id: option-id }) err-option-not-found))
    (underlying-asset (get underlying-asset option))
    (asset (unwrap! (map-get? assets { asset-id: underlying-asset }) err-asset-not-found))
    (asset-price (unwrap! (get current-price (map-get? price-data { asset-id: underlying-asset })) err-oracle-error))
    (creator (get creator option))
  )
    ;; Validation
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    (asserts! (is-eq holder (get holder position)) err-not-authorized)
    (asserts! (is-eq (get state position) u0) err-invalid-position-state)
    (asserts! (< block-height (get expiry-height option)) err-option-expired)
    (asserts! (not (get is-exercised option)) err-already-exercised)
    
    ;; For European options, can only exercise at expiration
    (asserts! (or 
               (is-eq (get option-style option) u0) ;; American style
               (>= block-height (- (get expiry-height option) u6)) ;; Within 1 hour of expiry
              ) 
              err-option-not-exercisable)
    
    ;; Check if the option is in-the-money
    (let (
      (is-call (is-eq (get option-type option) u0))
      (strike-price (get strike-price option))
      (intrinsic-value (if is-call
                          (if (> asset-price strike-price) (- asset-price strike-price) u0)
                          (if (< asset-price strike-price) (- strike-price asset-price) u0)))
      (contract-size (get contract-size option))
      (collateral-amount (get collateral-amount option))
      (collateral-token (get collateral-token option))
      (settlement-amount (calculate-settlement-amount option asset-price))
    )
      ;; Ensure option has value
      (asserts! (> intrinsic-value u0) err-option-not-exercisable)
      
      ;; Transfer settlement amount to holder
      (if (is-eq collateral-token "stx")
        ;; STX settlement
        (as-contract (try! (stx-transfer? settlement-amount (as-contract tx-sender) holder)))
        ;; Other token settlement
        (as-contract (try! (transfer-token collateral-token settlement-amount (as-contract tx-sender) holder)))
      )
      
      ;; Return remaining collateral to creator if any
      (let (
        (remaining-collateral (- collateral-amount settlement-amount))
      )
        (if (> remaining-collateral u0)
          (if (is-eq collateral-token "stx")
            ;; STX return
            (as-contract (try! (stx-transfer? remaining-collateral (as-contract tx-sender) creator)))
            ;; Other token return
            (as-contract (try! (transfer-token collateral-token remaining-collateral (as-contract tx-sender) creator)))
          )
          true
        )
      )
      
      ;; Update option
      (map-set options
        { option-id: option-id }
        (merge option {
          is-exercised: true,
          exercise-height: (some block-height),
          settlement-price: (some asset-price),
          is-settled: true,
          settlement-height: (some block-height)
        })
      )
      
      ;; Update position
      (map-set positions
        { position-id: position-id }
        (merge position {
          state: u1, ;; Exercised
          pnl: (some (- (to-int settlement-amount) (to-int (get purchase-price position)))),
          exercise-price: (some asset-price),
          exercise-height: (some block-height)
        })
      )
      
      (ok {
        position-id: position-id,
        settlement-amount: settlement-amount,
        intrinsic-value: intrinsic-value
      })
    )
  )
)

;; Calculate settlement amount for an option
(define-private (calculate-settlement-amount
  (option (tuple 
    creator: principal, 
    underlying-asset: (string-ascii 20), 
    strike-price: uint, 
    expiry-height: uint, 
    option-type: uint, 
    option-style: uint, 
    collateral-amount: uint, 
    premium: uint, 
    contract-size: uint, 
    creation-height: uint, 
    settlement-price: (optional uint), 
    is-settled: bool, 
    settlement-height: (optional uint), 
    collateral-token: (string-ascii 20), 
    holder: (optional principal), 
    is-exercised: bool, 
    exercise-height: (optional uint), 
    is-liquidated: bool, 
    liquidation-height: (optional uint), 
    iv-at-creation: uint, 
    premium-calculation-method: (string-ascii 10)))
  (asset-price uint))
  
  (let (
    (is-call (is-eq (get option-type option) u0))
    (strike-price (get strike-price option))
    (contract-size (get contract-size option))
  )
    (if is-call
      ;; Call option settlement
      (if (> asset-price strike-price)
        (min (get collateral-amount option) (* contract-size (/ (- asset-price strike-price) strike-price)))
        u0
      )
      ;; Put option settlement
      (if (< asset-price strike-price)
        (min (get collateral-amount option) (* contract-size (/ (- strike-price asset-price) strike-price)))
        u0
      )
    )
  )
)
