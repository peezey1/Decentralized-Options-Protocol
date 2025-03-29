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
      
